import itertools
import secrets

import pytest
from psycopg.types.json import Jsonb

from app import crypto

CLAT, CLNG = 21.005, 105.844
M_LAT = 111_195
_n = itertools.count()


def north(m):
    return CLAT + m / M_LAT


@pytest.fixture
def world(conn, make_user, make_class, enroll):
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    students = []
    for _ in range(6):
        s = make_user("student")
        enroll(c["id"], s["id"])
        students.append(s)
    sess = conn.execute(
        "INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, base_radius_m, "
        "room_check, room_secret, expires_at) VALUES (%s, %s, %s, %s, 8, 20, false, %s, now() + interval '10 minutes') "
        "RETURNING *", (c["id"], gv["id"], CLAT, CLNG, b"k" * 32)).fetchone()
    conn.execute("INSERT INTO attendance_records (session_id, student_id, status) "
                 "SELECT %s, student_id, 'absent' FROM enrollments WHERE class_id = %s", (sess["id"], c["id"]))
    return {"gv": gv, "class": c, "students": students, "sid": sess["id"]}


def attempt(conn, world, who, result="suspicious", d_m=50.0, face=0.9, flags=("LOCATION_DRIFT",), r=40.0,
            evidence=False, status=None):
    sid, uid = world["sid"], world["students"][who]["id"]
    ch = conn.execute("INSERT INTO challenges (session_id, student_id, nonce, action, expires_at, used_at) "
                      "VALUES (%s, %s, %s, 'turn_left', now(), now()) RETURNING id",
                      (sid, uid, secrets.token_hex(8))).fetchone()
    a = conn.execute(
        "INSERT INTO checkin_attempts (session_id, student_id, challenge_id, gps_samples, lat, lng, accuracy_m, "
        "distance_m, radius_m, face_score, result, flags) VALUES (%s, %s, %s, '[]', %s, %s, 10, %s, %s, %s, %s, %s) "
        "RETURNING id", (sid, uid, ch["id"], north(d_m), CLNG, d_m, r, face, result, Jsonb(list(flags)))).fetchone()
    if evidence:
        rel = crypto.save_blob(f"evidence/{a['id']}.jpg", b"\xff\xd8jpeg")
        conn.execute("UPDATE checkin_attempts SET evidence_path = %s, evidence_expires_at = now() + interval '30 days' "
                     "WHERE id = %s", (rel, a["id"]))
    st = status or {"pass": "present", "suspicious": "suspicious"}.get(result)
    if st:
        conn.execute("UPDATE attendance_records SET status = %s, best_attempt_id = %s WHERE session_id = %s "
                     "AND student_id = %s", (st, a["id"], sid, uid))
    return a["id"]


def test_records_counts_and_last_attempt(client, auth, conn, world):
    attempt(conn, world, 0, result="fail", flags=())
    last = attempt(conn, world, 0, evidence=True)
    attempt(conn, world, 1, result="pass", d_m=5, flags=())
    r = client.get(f"/sessions/{world['sid']}/records", headers=auth(world["gv"])).json()
    assert r["counts"] == {"absent": 4, "suspicious": 1, "present": 1, "manual_present": 0, "excused": 0, "rejected": 0}
    me = next(x for x in r["records"] if x["student_id"] == world["students"][0]["id"])
    assert me["attempt_count"] == 2
    assert me["last_attempt"]["id"] == last and me["last_attempt"]["has_evidence"] is True
    assert me["last_attempt"]["flags"] == ["LOCATION_DRIFT"]
    assert r["session"]["is_open"] is True and r["session"]["class"]["code"] == world["class"]["code"]


def test_records_other_lecturer_404(client, auth, world, make_user):
    assert client.get(f"/sessions/{world['sid']}/records", headers=auth(make_user("lecturer"))).status_code == 404


def test_recenter_suggested_flag(client, auth, conn, world):
    for i in range(5):
        attempt(conn, world, i, d_m=45)  # cùng phía bắc, d > r0 = 20
    r = client.get(f"/sessions/{world['sid']}/records", headers=auth(world["gv"])).json()
    assert r["session"]["recenter_suggested"] is True


def test_recenter_upgrades_drift_only(client, auth, conn, world):
    for i in range(4):
        attempt(conn, world, i, d_m=45)  # drift (r = 40 < 45)
    attempt(conn, world, 4, d_m=45, flags=("LOCATION_DRIFT", "FACE_BORDERLINE"))
    out = client.post(f"/sessions/{world['sid']}/recenter", headers=auth(world["gv"])).json()
    assert out["re_evaluated"] == 5
    st = {r["student_id"]: r["status"] for r in conn.execute(
        "SELECT student_id, status FROM attendance_records WHERE session_id = %s", (world["sid"],))}
    ids = [s["id"] for s in world["students"]]
    assert [st[i] for i in ids[:4]] == ["present"] * 4
    assert st[ids[4]] == "suspicious"  # vẫn còn FACE_BORDERLINE
    assert st[ids[5]] == "absent"      # không ai bị hạ/đổi


def test_recenter_keeps_original_center(client, auth, conn, world):
    for i in range(5):
        attempt(conn, world, i, d_m=45)
    for _ in range(2):
        client.post(f"/sessions/{world['sid']}/recenter", headers=auth(world["gv"]))
    s = conn.execute("SELECT * FROM attendance_sessions WHERE id = %s", (world["sid"],)).fetchone()
    assert (s["orig_center_lat"], s["orig_center_lng"]) == (CLAT, CLNG)
    assert s["center_lat"] > CLAT


def test_recenter_does_not_override_manual(client, auth, conn, world):
    attempt(conn, world, 0, d_m=45)
    client.patch(f"/sessions/{world['sid']}/records/{world['students'][0]['id']}", headers=auth(world["gv"]),
                 json={"status": "rejected"})
    for i in range(1, 5):
        attempt(conn, world, i, d_m=45)
    client.post(f"/sessions/{world['sid']}/recenter", headers=auth(world["gv"]))
    assert conn.execute("SELECT status FROM attendance_records WHERE session_id = %s AND student_id = %s",
                        (world["sid"], world["students"][0]["id"])).fetchone()["status"] == "rejected"


def test_patch_record_locks_and_audits(client, auth, conn, world):
    uid = world["students"][0]["id"]
    r = client.patch(f"/sessions/{world['sid']}/records/{uid}", headers=auth(world["gv"]),
                     json={"status": "excused", "note": "Có giấy ốm"})
    assert r.status_code == 200 and r.json()["decided_by"] == world["gv"]["id"]
    log = conn.execute("SELECT * FROM audit_log WHERE action = 'record.update'").fetchone()
    assert log["before"] == {"status": "absent", "note": None}
    assert log["after"] == {"status": "excused", "note": "Có giấy ốm"}


def test_patch_after_close_allowed(client, auth, conn, world):
    conn.execute("UPDATE attendance_sessions SET closed_at = now() WHERE id = %s", (world["sid"],))
    r = client.patch(f"/sessions/{world['sid']}/records/{world['students'][0]['id']}", headers=auth(world["gv"]),
                     json={"status": "manual_present"})
    assert r.status_code == 200


def test_patch_invalid_status(client, auth, world):
    r = client.patch(f"/sessions/{world['sid']}/records/{world['students'][0]['id']}", headers=auth(world["gv"]),
                     json={"status": "present"})
    assert r.status_code == 422


def test_record_detail_lists_attempts(client, auth, conn, world):
    attempt(conn, world, 0, result="fail", flags=())
    attempt(conn, world, 0)
    r = client.get(f"/sessions/{world['sid']}/records/{world['students'][0]['id']}", headers=auth(world["gv"])).json()
    assert [a["result"] for a in r["attempts"]] == ["suspicious", "fail"]
    assert r["record"]["status"] == "suspicious"


def test_evidence_other_class_404(client, auth, conn, world, make_user):
    aid = attempt(conn, world, 0, evidence=True)
    assert client.get(f"/attempts/{aid}/evidence", headers=auth(make_user("lecturer"))).status_code == 404


def test_evidence_view_audited(client, auth, conn, world):
    aid = attempt(conn, world, 0, evidence=True)
    r = client.get(f"/attempts/{aid}/evidence", headers=auth(world["gv"]))
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg" and r.content == b"\xff\xd8jpeg"
    assert conn.execute("SELECT target FROM audit_log WHERE action = 'evidence.view'").fetchone()["target"] \
        == f"checkin_attempts:{aid}"


def test_report_counts(client, auth, conn, world, make_user):
    attempt(conn, world, 0, result="pass", d_m=5, flags=())
    attempt(conn, world, 1)
    client.patch(f"/sessions/{world['sid']}/records/{world['students'][2]['id']}", headers=auth(world["gv"]),
                 json={"status": "excused"})
    r = client.get(f"/reports/classes/{world['class']['id']}", headers=auth(world["gv"])).json()
    rows = {x["student_id"]: x for x in r["rows"]}
    ids = [s["id"] for s in world["students"]]
    assert (rows[ids[0]]["co_mat"], rows[ids[1]]["chua_duyet"], rows[ids[2]]["vang_co_phep"], rows[ids[3]]["vang"]) \
        == (1, 1, 1, 1)
    assert r["session_count"] == 1 and all(x["so_buoi"] == 1 for x in r["rows"])
    assert (r["sessions"][0]["present"], r["sessions"][0]["suspicious"], r["sessions"][0]["total"]) == (1, 1, 6)
    assert r["first_try_pct"] == 50  # 2 sinh viên có lượt: 1 đạt ngay, 1 đáng ngờ
    admin = make_user("admin")
    assert client.get(f"/reports/classes/{world['class']['id']}", headers=auth(admin)).status_code == 200
    assert client.get(f"/reports/classes/{world['class']['id']}",
                      headers=auth(make_user("lecturer"))).status_code == 404


def test_report_csv_has_bom(client, auth, world):
    r = client.get(f"/reports/classes/{world['class']['id']}?format=csv", headers=auth(world["gv"]))
    assert r.content.startswith(b"\xef\xbb\xbf")
    assert "MSSV,Họ tên" in r.content.decode("utf-8-sig")
    assert r.headers["content-type"].startswith("text/csv")


def test_me_attendance_only_mine(client, auth, conn, world):
    attempt(conn, world, 0, result="pass", d_m=5, flags=())
    r = client.get("/me/attendance", headers=auth(world["students"][0])).json()
    assert len(r) == 1 and r[0]["status"] == "present" and r[0]["class_code"] == world["class"]["code"]
    assert r[0]["checked_at"] is not None
    assert "face_score" not in r[0]
    assert client.get("/me/attendance", headers=auth(world["gv"])).status_code == 403


def test_report_xlsx_has_summary_and_session_sheets(client, auth, conn, world):
    import io

    from openpyxl import load_workbook
    attempt(conn, world, 0, result="pass", d_m=5, flags=())
    client.patch(f"/sessions/{world['sid']}/records/{world['students'][2]['id']}", headers=auth(world["gv"]),
                 json={"status": "excused"})
    r = client.get(f"/reports/classes/{world['class']['id']}?format=xlsx", headers=auth(world["gv"]))
    assert r.headers["content-type"].startswith("application/vnd.openxmlformats")
    assert f'bao-cao-chuyen-can-{world["class"]["code"]}' in r.headers["content-disposition"]
    wb = load_workbook(io.BytesIO(r.content))
    assert wb.sheetnames == ["Tổng hợp", "Chi tiết buổi"]
    cells = [c for row in wb["Tổng hợp"].iter_rows(values_only=True) for c in row if c is not None]
    assert "BÁO CÁO CHUYÊN CẦN" in cells and world["students"][0]["full_name"] in cells
    assert world["gv"]["full_name"] in cells  # chỗ ký
    detail = [c for row in wb["Chi tiết buổi"].iter_rows(values_only=True) for c in row if c is not None]
    assert detail.count("C") == 1 and detail.count("P") == 1 and detail.count("V") == 4


def test_report_pdf(client, auth, world, make_user):
    r = client.get(f"/reports/classes/{world['class']['id']}?format=pdf", headers=auth(world["gv"]))
    assert r.headers["content-type"] == "application/pdf" and r.content.startswith(b"%PDF")
    assert client.get(f"/reports/classes/{world['class']['id']}?format=pdf",
                      headers=auth(make_user("lecturer"))).status_code == 404
    assert client.get(f"/reports/classes/{world['class']['id']}?format=doc", headers=auth(world["gv"])).status_code == 422
