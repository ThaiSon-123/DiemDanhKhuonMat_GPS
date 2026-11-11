from datetime import datetime, timedelta, timezone

import pytest

from app.services.room_token import verify_room_code

# Trong đa giác khuôn viên tạm (backend/campus.geojson: 105.840–105.848, 21.002–21.008).
LAT, LNG = 21.005, 105.844


def samples(n=5, acc=9.0, lat=LAT, lng=LNG):
    return [{"lat": lat + i * 1e-6, "lng": lng, "acc": acc, "ts": 1_794_000_000_000 + i * 1000} for i in range(n)]


def code(r):
    return r.json()["error"]["code"]


@pytest.fixture
def lop(make_user, make_class, enroll):
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    students = [make_user("student") for _ in range(3)]
    for s in students:
        enroll(c["id"], s["id"])
    return gv, c, students


def open_(client, auth, gv, c, **kw):
    body = {"class_id": c["id"], "duration_min": 10, "base_radius_m": 20, "room_check": True,
            "gps_samples": samples(), **kw}
    return client.post("/sessions", headers=auth(gv), json=body)


def test_open_creates_absent_rows(client, auth, lop, conn):
    gv, c, students = lop
    r = open_(client, auth, gv, c)
    assert r.status_code == 201
    body = r.json()
    assert body["center"]["lat"] == pytest.approx(LAT + 2e-6) and body["center"]["accuracy_m"] == 9
    expires = datetime.fromisoformat(body["expires_at"])
    assert timedelta(minutes=9, seconds=50) < expires - datetime.now(timezone.utc) <= timedelta(minutes=10)
    rows = conn.execute("SELECT student_id, status FROM attendance_records WHERE session_id = %s",
                        (body["session_id"],)).fetchall()
    assert sorted(r["student_id"] for r in rows) == sorted(s["id"] for s in students)
    assert {r["status"] for r in rows} == {"absent"}
    s = conn.execute("SELECT * FROM attendance_sessions").fetchone()
    assert (s["base_radius_m"], s["room_check"], len(bytes(s["room_secret"]))) == (20, True, 32)


def test_open_requires_5_good_samples(client, auth, lop):
    gv, c, _ = lop
    bad = samples(4) + samples(3, acc=35)  # chỉ 4 mẫu ≤ 20 m
    r = open_(client, auth, gv, c, gps_samples=bad)
    assert r.status_code == 422 and code(r) == "GPS_ACCURACY_LOW"


def test_open_garbage_samples_never_500(client, auth, lop):
    gv, c, _ = lop
    for g in ([], [{"lat": 91, "lng": 105, "acc": 5, "ts": 0}], [{"lat": 21, "lng": 105, "acc": 0, "ts": 0}],
              [{"lat": "x", "lng": 105, "acc": 5, "ts": 0}]):
        r = open_(client, auth, gv, c, gps_samples=g)
        assert r.status_code == 422 and code(r) in ("VALIDATION_ERROR", "GPS_ACCURACY_LOW"), g


def test_open_outside_campus(client, auth, lop):
    gv, c, _ = lop
    r = open_(client, auth, gv, c, gps_samples=samples(lat=21.03, lng=105.85))
    assert r.status_code == 422 and code(r) == "OUTSIDE_CAMPUS"


def test_open_twice_conflict(client, auth, lop):
    gv, c, _ = lop
    assert open_(client, auth, gv, c).status_code == 201
    r = open_(client, auth, gv, c)
    assert r.status_code == 409 and code(r) == "SESSION_ALREADY_OPEN"


def test_open_after_expired_session_ok(client, auth, lop, conn):
    gv, c, _ = lop
    sid = open_(client, auth, gv, c).json()["session_id"]
    conn.execute("UPDATE attendance_sessions SET expires_at = now() - interval '1 minute' WHERE id = %s", (sid,))
    assert open_(client, auth, gv, c).status_code == 201
    old = conn.execute("SELECT closed_at, expires_at FROM attendance_sessions WHERE id = %s", (sid,)).fetchone()
    assert old["closed_at"] == old["expires_at"]  # phiên quá hạn còn treo được đóng tại thời điểm hết hạn


@pytest.mark.parametrize("bad", [{"base_radius_m": 5}, {"base_radius_m": 60}, {"duration_min": 0},
                                 {"duration_min": 61}])
def test_r0_and_duration_out_of_range(client, auth, lop, bad):
    gv, c, _ = lop
    r = open_(client, auth, gv, c, **bad)
    assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"


def test_defaults_from_config(client, auth, lop, conn):
    gv, c, _ = lop
    r = client.post("/sessions", headers=auth(gv), json={"class_id": c["id"], "gps_samples": samples()})
    assert r.status_code == 201 and r.json()["room_check"] is False
    s = conn.execute("SELECT base_radius_m, expires_at - opened_at AS d FROM attendance_sessions").fetchone()
    assert s["base_radius_m"] == 20 and s["d"] == timedelta(minutes=10)


def test_lecturer_other_class_404(client, auth, lop, make_user):
    gv, c, _ = lop
    sid = open_(client, auth, gv, c).json()["session_id"]
    other = make_user("lecturer")
    h = auth(other)
    for r in (open_(client, auth, other, c),
              client.post(f"/sessions/{sid}/close", headers=h),
              client.get(f"/sessions/{sid}/room-token", headers=h),
              client.get(f"/classes/{c['id']}/sessions", headers=h),
              client.post("/sessions/999999/close", headers=h)):
        assert r.status_code == 404 and code(r) == "NOT_FOUND"


def test_students_cannot_open(client, auth, lop):
    gv, c, students = lop
    r = client.post("/sessions", headers=auth(students[0]), json={"class_id": c["id"], "gps_samples": samples()})
    assert r.status_code == 403 and code(r) == "FORBIDDEN"


def test_room_token(client, auth, lop, conn):
    gv, c, _ = lop
    sid = open_(client, auth, gv, c).json()["session_id"]
    r = client.get(f"/sessions/{sid}/room-token", headers=auth(gv))
    assert r.status_code == 200
    body = r.json()
    secret = bytes(conn.execute("SELECT room_secret FROM attendance_sessions").fetchone()["room_secret"])
    assert verify_room_code(body["code"], secret, sid, datetime.now().timestamp())
    assert body["qr_payload"] == f"dd:{sid}:{body['code']}"
    assert datetime.fromisoformat(body["window_ends_at"]) > datetime.now(timezone.utc)


def test_room_token_when_disabled(client, auth, lop):
    gv, c, _ = lop
    sid = open_(client, auth, gv, c, room_check=False).json()["session_id"]
    r = client.get(f"/sessions/{sid}/room-token", headers=auth(gv))
    assert r.status_code == 409 and code(r) == "ROOM_CHECK_DISABLED"


def test_room_token_after_close(client, auth, lop):
    gv, c, _ = lop
    sid = open_(client, auth, gv, c).json()["session_id"]
    client.post(f"/sessions/{sid}/close", headers=auth(gv))
    r = client.get(f"/sessions/{sid}/room-token", headers=auth(gv))
    assert r.status_code == 409 and code(r) == "SESSION_CLOSED"


def test_close_then_history(client, auth, lop, conn):
    gv, c, students = lop
    sid = open_(client, auth, gv, c).json()["session_id"]
    conn.execute("UPDATE attendance_records SET status = 'present' WHERE student_id = %s", (students[0]["id"],))
    conn.execute("UPDATE attendance_records SET status = 'suspicious' WHERE student_id = %s", (students[1]["id"],))
    r = client.post(f"/sessions/{sid}/close", headers=auth(gv))
    assert r.status_code == 200 and r.json()["is_open"] is False
    again = client.post(f"/sessions/{sid}/close", headers=auth(gv))  # đóng lại lần nữa không đổi gì
    assert again.status_code == 200 and again.json()["closed_at"] == r.json()["closed_at"]
    hist = client.get(f"/classes/{c['id']}/sessions", headers=auth(gv)).json()
    assert len(hist) == 1
    assert hist[0]["counts"] == {"present": 1, "suspicious": 1, "absent": 1, "excused": 0, "rejected": 0, "total": 3}
    assert hist[0]["is_open"] is False
    assert client.get(f"/classes/{c['id']}/sessions", headers=auth(gv)).status_code == 200
    # mở phiên mới được ngay sau khi đóng tay
    assert open_(client, auth, gv, c).status_code == 201


def test_my_classes_shows_open_session(client, auth, lop):
    gv, c, students = lop
    sid = open_(client, auth, gv, c).json()["session_id"]
    mine = client.get("/me/classes", headers=auth(students[0])).json()
    assert mine[0]["open_session"]["id"] == sid and mine[0]["open_session"]["room_check"] is True
