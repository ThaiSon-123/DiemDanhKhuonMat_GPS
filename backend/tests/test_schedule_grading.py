import io

import pytest
from openpyxl import load_workbook


@pytest.fixture
def world(conn, make_user, make_class, enroll):
    """Lớp 3 sinh viên, 5 buổi đã đóng. SV0 có mặt cả 5; SV1 vắng 2 (40 %); SV2 vắng 1 + có phép 1."""
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    sv = [make_user("student") for _ in range(3)]
    for s in sv:
        enroll(c["id"], s["id"])
    sids = []
    for _ in range(5):
        sid = conn.execute(
            "INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, base_radius_m, "
            "room_secret, expires_at, closed_at) VALUES (%s, %s, 21, 105, 8, 20, %s, now(), now()) RETURNING id",
            (c["id"], gv["id"], b"k" * 32)).fetchone()["id"]
        conn.execute("INSERT INTO attendance_records (session_id, student_id, status) "
                     "SELECT %s, student_id, 'present' FROM enrollments WHERE class_id = %s", (sid, c["id"]))
        sids.append(sid)

    def mark(who, i, status):
        conn.execute("UPDATE attendance_records SET status = %s WHERE session_id = %s AND student_id = %s",
                     (status, sids[i], sv[who]["id"]))
    mark(1, 0, "absent")
    mark(1, 1, "rejected")
    mark(2, 2, "absent")
    mark(2, 3, "excused")
    return {"gv": gv, "class": c, "sv": sv, "sids": sids}


def test_schedules_crud_and_in_my_classes(client, auth, conn, world, make_user):
    admin = make_user("admin")
    h = auth(admin)
    cid = world["class"]["id"]
    r = client.post(f"/admin/classes/{cid}/schedules", headers=h,
                    json={"weekday": 2, "start_time": "07:00", "end_time": "09:30", "room": " D9-301 "})
    assert r.status_code == 201 and r.json()["room"] == "D9-301"
    client.post(f"/admin/classes/{cid}/schedules", headers=h, json={"weekday": 5, "start_time": "13:00", "end_time": "15:00"})
    bad = client.post(f"/admin/classes/{cid}/schedules", headers=h, json={"weekday": 2, "start_time": "09:00", "end_time": "08:00"})
    assert bad.status_code == 422
    assert client.post(f"/admin/classes/{cid}/schedules", headers=h,
                       json={"weekday": 8, "start_time": "07:00", "end_time": "08:00"}).status_code == 422
    assert [s["weekday"] for s in client.get(f"/admin/classes/{cid}/schedules", headers=h).json()] == [2, 5]
    mine = client.get("/me/classes", headers=auth(world["sv"][0])).json()[0]["schedules"]
    assert mine[0] == {"weekday": 2, "start": "07:00", "end": "09:30", "room": "D9-301"}
    assert len(client.get("/me/classes", headers=auth(world["gv"])).json()[0]["schedules"]) == 2
    assert client.delete(f"/admin/schedules/{r.json()['id']}", headers=h).status_code == 204
    assert client.delete(f"/admin/schedules/{r.json()['id']}", headers=h).status_code == 404
    assert [a["action"] for a in conn.execute("SELECT action FROM audit_log ORDER BY id")] == \
        ["class.schedule.add", "class.schedule.add", "class.schedule.delete"]


def test_bulk_patch_sets_status_and_audits_each(client, auth, conn, world, make_user):
    sid = world["sids"][4]
    ids = [s["id"] for s in world["sv"]]
    r = client.patch(f"/sessions/{sid}/records", headers=auth(world["gv"]),
                     json={"student_ids": ids + [999999], "status": "manual_present", "note": "Mất mạng, điểm danh tay"})
    assert r.json() == {"updated": 3, "skipped": 1}
    rows = conn.execute("SELECT status, decided_by, note FROM attendance_records WHERE session_id = %s", (sid,)).fetchall()
    assert {(x["status"], x["decided_by"], x["note"]) for x in rows} == \
        {("manual_present", world["gv"]["id"], "Mất mạng, điểm danh tay")}
    assert conn.execute("SELECT count(*) n FROM audit_log WHERE action = 'record.update'").fetchone()["n"] == 3
    assert client.patch(f"/sessions/{sid}/records", headers=auth(make_user("lecturer")),
                        json={"student_ids": ids, "status": "absent"}).status_code == 404
    assert client.patch(f"/sessions/{sid}/records", headers=auth(world["gv"]),
                        json={"student_ids": [], "status": "absent"}).status_code == 422


def test_report_grade_and_ban(client, auth, world):
    r = client.get(f"/reports/classes/{world['class']['id']}", headers=auth(world["gv"])).json()
    rows = {x["student_id"]: x for x in r["rows"]}
    s0, s1, s2 = (rows[s["id"]] for s in world["sv"])
    assert (s0["diem"], s0["cam_thi"]) == (10.0, False)
    assert (s1["diem"], s1["cam_thi"]) == (6.0, True)    # vắng 2/5 = 40 % > 20 %
    assert (s2["diem"], s2["cam_thi"]) == (8.0, False)   # có phép tính như có mặt; vắng 1/5 = 20 % (không quá)
    assert r["grading"]["ban_absent_pct"] == 20
    csv = client.get(f"/reports/classes/{world['class']['id']}?format=csv", headers=auth(world["gv"])).content.decode("utf-8-sig")
    assert "Điểm chuyên cần,Cấm thi" in csv.splitlines()[0]
    wb = load_workbook(io.BytesIO(client.get(f"/reports/classes/{world['class']['id']}?format=xlsx",
                                             headers=auth(world["gv"])).content))
    cells = [c for row in wb["Tổng hợp"].iter_rows(values_only=True) for c in row if c is not None]
    assert "Điểm CC" in cells and "Không đủ điều kiện dự thi (vắng 2 buổi)" in cells


def test_banned_list(client, auth, world, make_user):
    h = auth(make_user("admin"))
    r = client.get("/admin/banned", headers=h).json()
    assert r["semester"] == world["class"]["semester"] and r["ban_absent_pct"] == 20
    assert [(x["student_code"], x["vang"], x["pct"]) for x in r["rows"]] == [(world["sv"][1]["student_code"], 2, 40)]
    pdf = client.get("/admin/banned?format=pdf", headers=h)
    assert pdf.headers["content-type"] == "application/pdf" and pdf.content.startswith(b"%PDF")
    wb = load_workbook(io.BytesIO(client.get("/admin/banned?format=xlsx", headers=h).content))
    cells = [c for row in wb.active.iter_rows(values_only=True) for c in row if c is not None]
    assert "DANH SÁCH SINH VIÊN KHÔNG ĐỦ ĐIỀU KIỆN DỰ THI" in cells and world["sv"][1]["full_name"] in cells
    assert client.get("/admin/banned", headers=auth(world["gv"])).status_code == 403
