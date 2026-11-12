import secrets

import pytest
from psycopg.types.json import Jsonb

from app.config import get_settings
from app.services.face.runtime import get_engine
from face_fakes import FakeEngine, fa

JPEG = b"\xff\xd8\xff\xe0proof"


@pytest.fixture
def world(conn, make_user, make_class, enroll):
    """Lớp 2 sinh viên; buổi 1 đã đóng (cả hai vắng), buổi 2 đang mở."""
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    sv = [make_user("student") for _ in range(2)]
    for s in sv:
        enroll(c["id"], s["id"])

    def session(open_: bool, days_ago: int = 1):
        sid = conn.execute(
            "INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, base_radius_m, "
            "room_secret, opened_at, expires_at, closed_at) VALUES (%s, %s, 21, 105, 8, 20, %s, "
            "now() - make_interval(days => %s), now() + interval '10 minutes', %s) RETURNING id",
            (c["id"], gv["id"], b"k" * 32, days_ago, None if open_ else "2000-01-01")).fetchone()["id"]
        conn.execute("INSERT INTO attendance_records (session_id, student_id, status) "
                     "SELECT %s, student_id, 'absent' FROM enrollments WHERE class_id = %s", (sid, c["id"]))
        return sid

    closed = session(False)
    conn.execute("UPDATE attendance_sessions SET closed_at = now() - interval '1 day' WHERE id = %s", (closed,))
    return {"gv": gv, "class": c, "sv": sv, "closed": closed, "session": session}


def send(client, auth, who, sid, kind="leave", reason="Em bị ốm, có giấy khám", file=True):
    files = {"attachment": ("giay.jpg", JPEG, "image/jpeg")} if file else None
    return client.post("/me/requests", headers=auth(who), data={"kind": kind, "session_id": sid, "reason": reason},
                       files=files)


def code(r):
    return r.json()["error"]["code"]


def test_leave_approved_becomes_excused_and_locked(client, auth, conn, world):
    r = send(client, auth, world["sv"][0], world["closed"])
    assert r.status_code == 201 and r.json()["status"] == "pending" and r.json()["has_attachment"] is True
    rid = r.json()["id"]
    pending = client.get("/requests", headers=auth(world["gv"])).json()
    assert [x["id"] for x in pending] == [rid] and pending[0]["record_status"] == "absent"
    img = client.get(f"/requests/{rid}/attachment", headers=auth(world["gv"]))
    assert img.content == JPEG and img.headers["content-type"] == "image/jpeg"
    d = client.post(f"/requests/{rid}/decide", headers=auth(world["gv"]), json={"decision": "approve"})
    assert d.json()["status"] == "approved"
    rec = conn.execute("SELECT status, decided_by, note FROM attendance_records WHERE session_id = %s AND student_id = %s",
                       (world["closed"], world["sv"][0]["id"])).fetchone()
    assert (rec["status"], rec["decided_by"]) == ("excused", world["gv"]["id"]) and "Đơn xin nghỉ" in rec["note"]
    actions = [r["action"] for r in conn.execute("SELECT action FROM audit_log ORDER BY id")]
    assert actions == ["request.leave", "request.attachment.view", "record.update", "request.decide"]
    assert code(client.post(f"/requests/{rid}/decide", headers=auth(world["gv"]), json={"decision": "approve"})) \
        == "REQUEST_DECIDED"


def test_appeal_approved_becomes_present(client, auth, conn, world):
    rid = send(client, auth, world["sv"][1], world["closed"], kind="appeal", reason="Em có mặt, GPS lỗi", file=False).json()["id"]
    client.post(f"/requests/{rid}/decide", headers=auth(world["gv"]), json={"decision": "approve", "note": "Đã thấy"})
    assert conn.execute("SELECT status FROM attendance_records WHERE session_id = %s AND student_id = %s",
                        (world["closed"], world["sv"][1]["id"])).fetchone()["status"] == "manual_present"
    mine = client.get("/me/requests", headers=auth(world["sv"][1])).json()
    assert (mine[0]["status"], mine[0]["kind"], mine[0]["decision_note"]) == ("approved", "appeal", "Đã thấy")


def test_reject_needs_note_and_keeps_record(client, auth, conn, world):
    rid = send(client, auth, world["sv"][0], world["closed"], file=False).json()["id"]
    assert client.post(f"/requests/{rid}/decide", headers=auth(world["gv"]), json={"decision": "reject"}).status_code == 422
    r = client.post(f"/requests/{rid}/decide", headers=auth(world["gv"]), json={"decision": "reject", "note": "Thiếu giấy"})
    assert r.json()["status"] == "rejected"
    assert conn.execute("SELECT status FROM attendance_records WHERE session_id = %s AND student_id = %s",
                        (world["closed"], world["sv"][0]["id"])).fetchone()["status"] == "absent"
    assert send(client, auth, world["sv"][0], world["closed"], file=False).status_code == 201  # gửi lại được


def test_create_rules(client, auth, conn, world, make_user):
    sv = world["sv"][0]
    assert code(send(client, auth, sv, world["session"](True))) == "SESSION_STILL_OPEN"
    old = world["session"](False, days_ago=30)
    conn.execute("UPDATE attendance_sessions SET closed_at = opened_at WHERE id = %s", (old,))
    assert code(send(client, auth, sv, old)) == "REQUEST_TOO_LATE"
    conn.execute("UPDATE attendance_records SET status = 'present' WHERE session_id = %s AND student_id = %s",
                 (world["closed"], world["sv"][1]["id"]))
    assert code(send(client, auth, world["sv"][1], world["closed"])) == "REQUEST_NOT_ALLOWED"
    assert send(client, auth, sv, world["closed"]).status_code == 201
    assert code(send(client, auth, sv, world["closed"])) == "REQUEST_PENDING_EXISTS"
    assert send(client, auth, make_user("student"), world["closed"]).status_code == 404  # không thuộc lớp
    bad = client.post("/me/requests", headers=auth(world["sv"][1]), data={"kind": "leave", "session_id": world["closed"],
                      "reason": "abc"})
    assert bad.status_code == 422
    pdf = client.post("/me/requests", headers=auth(sv), data={"kind": "leave", "session_id": world["closed"],  # loại file được kiểm tra trước khi tạo đơn
                      "reason": "Lý do đủ dài"}, files={"attachment": ("a.pdf", b"%PDF", "application/pdf")})
    assert pdf.status_code == 422


def test_other_lecturer_cannot_see_or_decide(client, auth, world, make_user):
    rid = send(client, auth, world["sv"][0], world["closed"]).json()["id"]
    other = make_user("lecturer")
    assert client.get("/requests", headers=auth(other)).json() == []
    assert client.get(f"/requests/{rid}/attachment", headers=auth(other)).status_code == 404
    assert client.post(f"/requests/{rid}/decide", headers=auth(other), json={"decision": "approve"}).status_code == 404


def test_absence_warning(client, auth, conn, world):
    for _ in range(2):
        sid = world["session"](False)
        conn.execute("UPDATE attendance_sessions SET closed_at = now() WHERE id = %s", (sid,))
    world["session"](True)  # buổi đang mở không tính
    cls = client.get("/me/classes", headers=auth(world["sv"][0])).json()[0]
    assert (cls["absences"], cls["warn"], cls["warn_absent"]) == (3, True, get_settings().attendance.warn_absent)
    rec = client.get(f"/sessions/{world['closed']}/records", headers=auth(world["gv"])).json()
    assert all(r["warn"] for r in rec["records"]) and rec["warn_absent"] == 3
    rep = client.get(f"/reports/classes/{world['class']['id']}", headers=auth(world["gv"])).json()
    assert rep["warn_absent"] == 3 and all(r["warn"] for r in rep["rows"])


def test_admin_overview(client, auth, conn, world, make_user):
    sv = world["sv"][0]
    ch = conn.execute("INSERT INTO challenges (session_id, student_id, nonce, action, expires_at) VALUES "
                      "(%s, %s, %s, 'turn_left', now()) RETURNING id", (world["closed"], sv["id"], secrets.token_hex(6))).fetchone()
    conn.execute("INSERT INTO checkin_attempts (session_id, student_id, challenge_id, gps_samples, result, flags) "
                 "VALUES (%s, %s, %s, '[]', 'suspicious', %s)", (world["closed"], sv["id"], ch["id"],
                                                                Jsonb(["LOCATION_DRIFT", "FACE_BORDERLINE"])))
    conn.execute("UPDATE attendance_records SET status = 'present' WHERE session_id = %s AND student_id = %s",
                 (world["closed"], sv["id"]))
    r = client.get("/admin/overview", headers=auth(make_user("admin"))).json()
    assert r["semester"] == world["class"]["semester"] and r["semesters"] == [world["class"]["semester"]]
    c = r["classes"][0]
    assert (c["sessions"], c["records"], c["present"], c["present_pct"]) == (1, 2, 1, 50)
    assert {f["flag"]: f["n"] for f in r["flags"]} == {"LOCATION_DRIFT": 1, "FACE_BORDERLINE": 1}
    assert (r["totals"]["attempts"], r["totals"]["suspicious"], r["totals"]["present_pct"]) == (1, 1, 50)
    assert client.get("/admin/overview", headers=auth(world["gv"])).status_code == 403


def test_precheck_pose(client, auth, make_user, monkeypatch):
    from app.main import app
    f = get_settings().face
    monkeypatch.setattr(f, "yaw_sign", 1)
    monkeypatch.setattr(f, "yaw_threshold", 0.25)
    for attr, v in dict(min_brightness=60, min_sharpness=50, min_face_px=100).items():
        monkeypatch.setattr(f, attr, v)
    eng = FakeEngine({b"front": fa(yaw_proxy=0.0), b"left": fa(yaw_proxy=-0.3), b"right": fa(yaw_proxy=0.3),
                      b"half": fa(yaw_proxy=0.2), b"dark": fa(brightness=10)})
    app.dependency_overrides[get_engine] = lambda: eng
    try:
        sv = make_user("student")
        out = {k: client.post("/faces/precheck", headers=auth(sv), files={"photo": ("a.jpg", k, "image/jpeg")}).json()
               for k in (b"front", b"left", b"right", b"half", b"dark", b"none")}
    finally:
        app.dependency_overrides.pop(get_engine, None)
    assert [out[k]["pose"] for k in (b"front", b"left", b"right", b"half")] == ["front", "left", "right", "turning"]
    assert (out[b"dark"]["ok"], out[b"dark"]["reason"]) == (False, "LOW_LIGHT")
    assert out[b"none"]["reason"] == "FACE_NOT_FOUND"
    assert eng.calls[0][1:] == (False, False)  # không trích đặc trưng, không chạy anti-spoofing
