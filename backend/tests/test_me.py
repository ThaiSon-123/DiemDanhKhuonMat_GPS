from datetime import datetime, timedelta, timezone

from app.config import get_settings

MODEL = get_settings().face.model_name


def code(r):
    return r.json()["error"]["code"]


def add_face(conn, student_id, status, model=MODEL, reason=None):
    conn.execute("INSERT INTO face_templates (student_id, model_name, status, reject_reason) VALUES (%s, %s, %s, %s)",
                 (student_id, model, status, reason))


def open_session(conn, class_id, lecturer_id, minutes=10, closed=False, room_check=True):
    now = datetime.now(timezone.utc)
    return conn.execute(
        "INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, "
        "base_radius_m, room_check, room_secret, expires_at, closed_at) "
        "VALUES (%s, %s, 21, 105, 9, 20, %s, 'k', %s, %s) RETURNING *",
        (class_id, lecturer_id, room_check, now + timedelta(minutes=minutes), now if closed else None)).fetchone()


def test_me_face_none_and_consent_false(client, make_user, auth):
    u = make_user("student", username="sva")
    body = client.get("/me", headers=auth(u)).json()
    assert body["username"] == "sva" and body["must_change_password"] is False
    assert body["consent"] == {"current_version": "v1", "accepted": False}
    assert body["face"] == {"status": "none", "reject_reason": None, "model_ok": None, "pending_update": False}


def test_me_lecturer_has_no_consent_or_face(client, make_user, auth):
    body = client.get("/me", headers=auth(make_user("lecturer"))).json()
    assert body["role"] == "lecturer" and body["consent"] is None and body["face"] is None


def test_me_face_approved_with_pending_update(client, conn, make_user, auth):
    u = make_user("student")
    add_face(conn, u["id"], "approved")
    add_face(conn, u["id"], "pending")
    assert client.get("/me", headers=auth(u)).json()["face"] == {
        "status": "approved", "reject_reason": None, "model_ok": True, "pending_update": True}


def test_me_face_rejected_shows_reason_until_new_enrollment(client, conn, make_user, auth):
    u = make_user("student")
    add_face(conn, u["id"], "rejected", reason="Ảnh ngược sáng")
    face = client.get("/me", headers=auth(u)).json()["face"]
    assert face["status"] == "rejected" and face["reject_reason"] == "Ảnh ngược sáng"
    add_face(conn, u["id"], "pending")
    face = client.get("/me", headers=auth(u)).json()["face"]
    assert face["status"] == "pending" and face["reject_reason"] is None


def test_me_face_model_outdated(client, conn, make_user, auth):
    u = make_user("student")
    add_face(conn, u["id"], "approved", model="mo_hinh_cu")
    face = client.get("/me", headers=auth(u)).json()["face"]
    assert face["status"] == "approved" and face["model_ok"] is False


def test_me_ignores_revoked(client, conn, make_user, auth):
    u = make_user("student")
    add_face(conn, u["id"], "revoked")
    assert client.get("/me", headers=auth(u)).json()["face"]["status"] == "none"


def test_consent_accept_and_idempotent(client, conn, make_user, auth):
    u = make_user("student")
    for _ in range(2):
        r = client.post("/me/consent", headers=auth(u), json={"version": "v1"})
        assert r.status_code == 200 and r.json() == {"current_version": "v1", "accepted": True}
    assert conn.execute("SELECT count(*) c FROM consents").fetchone()["c"] == 1
    assert client.get("/me", headers=auth(u)).json()["consent"]["accepted"] is True


def test_consent_after_revoke_is_accepted_again(client, conn, make_user, auth):
    u = make_user("student")
    conn.execute("INSERT INTO consents (user_id, version, revoked_at) VALUES (%s, 'v1', now())", (u["id"],))
    assert client.get("/me", headers=auth(u)).json()["consent"]["accepted"] is False
    client.post("/me/consent", headers=auth(u), json={"version": "v1"})
    assert conn.execute("SELECT revoked_at FROM consents").fetchone()["revoked_at"] is None


def test_consent_wrong_version_422(client, make_user, auth):
    r = client.post("/me/consent", headers=auth(make_user("student")), json={"version": "v0"})
    assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"


def test_consent_only_students(client, make_user, auth):
    r = client.post("/me/consent", headers=auth(make_user("lecturer")), json={"version": "v1"})
    assert r.status_code == 403 and code(r) == "FORBIDDEN"


def test_my_classes_student_open_session(client, conn, make_user, make_class, enroll, auth):
    gv = make_user("lecturer", full_name="TS. Trần Minh Đức")
    sv = make_user("student")
    a = make_class(gv["id"], code="IT4060", name="Học máy")
    b = make_class(gv["id"], code="IT4343")
    c = make_class(gv["id"], code="IT4310")
    make_class(gv["id"], code="IT9999")  # không học lớp này
    for k in (a, b, c):
        enroll(k["id"], sv["id"])
    s = open_session(conn, a["id"], gv["id"])
    open_session(conn, b["id"], gv["id"], minutes=-1)       # quá hạn nhưng chưa đóng tay
    open_session(conn, c["id"], gv["id"], closed=True)      # đã đóng
    rows = client.get("/me/classes", headers=auth(sv)).json()
    assert [r["code"] for r in rows] == ["IT4060", "IT4310", "IT4343"]
    first = rows[0]
    assert first["name"] == "Học máy" and first["lecturer_name"] == "TS. Trần Minh Đức"
    assert first["open_session"]["id"] == s["id"] and first["open_session"]["room_check"] is True
    assert datetime.fromisoformat(first["open_session"]["expires_at"]) == s["expires_at"]
    assert rows[1]["open_session"] is None and rows[2]["open_session"] is None
    assert "student_count" not in first


def test_my_classes_lecturer_has_student_count(client, conn, make_user, make_class, enroll, auth):
    gv, other = make_user("lecturer"), make_user("lecturer")
    a = make_class(gv["id"], code="IT4060")
    make_class(other["id"], code="IT4343")  # lớp của giảng viên khác
    for _ in range(3):
        enroll(a["id"], make_user("student")["id"])
    open_session(conn, a["id"], gv["id"])
    rows = client.get("/me/classes", headers=auth(gv)).json()
    assert len(rows) == 1 and rows[0]["student_count"] == 3 and rows[0]["open_session"] is not None


def test_my_classes_admin_forbidden(client, make_user, auth):
    assert code(client.get("/me/classes", headers=auth(make_user("admin")))) == "FORBIDDEN"
