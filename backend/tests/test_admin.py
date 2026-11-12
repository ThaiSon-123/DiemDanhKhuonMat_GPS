import pytest

from app import cli


def code(r):
    return r.json()["error"]["code"]


@pytest.fixture
def admin(make_user, auth):
    a = make_user("admin", email="admin@x.vn")
    return a, auth(a)


def login(client, username, password):
    return client.post("/auth/login", json={"username": username, "password": password})


def test_admin_routes_require_admin(client, make_user, auth):
    gv = make_user("lecturer")
    r = client.get("/admin/users", headers=auth(gv))
    assert r.status_code == 403 and code(r) == "FORBIDDEN"


def test_create_user_returns_temp_password(client, admin, conn):
    _, h = admin
    r = client.post("/admin/users", headers=h,
                    json={"role": "student", "username": " SV001", "email": " SV1@X.vn", "full_name": "An",
                          "student_code": "SV001"})
    assert r.status_code == 201
    body = r.json()
    assert body["user"]["username"] == "sv001" and body["user"]["email"] == "sv1@x.vn"
    assert body["user"]["must_change_password"] is True
    assert login(client, "sv001", body["temp_password"]).json()["user"]["must_change_password"] is True
    assert conn.execute("SELECT action, target FROM audit_log").fetchall() == [
        {"action": "user.create", "target": f"users:{body['user']['id']}"}]


def test_create_user_validation(client, admin, make_user):
    _, h = admin
    make_user("student", username="sva", email="a@x.vn", student_code="SV1")
    cases = [
        ({"role": "student", "username": "SVA", "full_name": "A", "student_code": "SV2"}, "username"),
        ({"role": "student", "username": "a b", "full_name": "A", "student_code": "SV2"}, "username"),
        ({"role": "student", "username": "svb", "email": "a@x.vn", "full_name": "A", "student_code": "SV2"}, "email"),
        ({"role": "student", "username": "svc", "full_name": "B", "student_code": "SV1"}, "student_code"),
        ({"role": "student", "username": "svd", "full_name": "C"}, "student_code"),
        ({"role": "boss", "username": "sve", "full_name": "D"}, "role"),
    ]
    for body, field in cases:
        r = client.post("/admin/users", headers=h, json=body)
        assert r.status_code == 422 and code(r) == "VALIDATION_ERROR", body
        assert r.json()["error"]["details"][0]["field"] == field


def test_list_users_search_filter_paginate(client, admin, make_user, conn):
    _, h = admin
    for i in range(3):
        make_user("student", full_name=f"Nguyễn {i}")
    s = make_user("student", full_name="Trần Gia Bảo")
    make_user("lecturer", full_name="Nguyễn GV")
    conn.execute("INSERT INTO face_templates (student_id, model_name, status) VALUES (%s, 'm', 'pending')", (s["id"],))
    r = client.get("/admin/users", headers=h, params={"role": "student", "q": "nguyễn", "size": 2})
    assert r.json()["total"] == 3 and len(r.json()["items"]) == 2
    assert client.get("/admin/users", headers=h, params={"role": "student", "q": "nguyễn", "size": 2, "page": 2}
                      ).json()["items"][0]["full_name"] == "Nguyễn 2"
    item = client.get("/admin/users", headers=h, params={"q": s["student_code"]}).json()["items"][0]
    assert client.get("/admin/users", headers=h, params={"q": s["username"]}).json()["items"][0]["id"] == s["id"]
    assert item["id"] == s["id"] and item["face_status"] == "pending" and "password_hash" not in item
    assert client.get("/admin/users", headers=h, params={"face": "none", "role": "student"}).json()["total"] == 3
    conn.execute("UPDATE users SET is_active = false WHERE id = %s", (s["id"],))
    assert client.get("/admin/users", headers=h, params={"active": "false"}).json()["items"][0]["id"] == s["id"]
    assert client.get("/admin/users", headers=h, params={"active": "true", "role": "student"}).json()["total"] == 3


def test_update_user(client, admin, make_user):
    _, h = admin
    u = make_user("student")
    r = client.patch(f"/admin/users/{u['id']}", headers=h, json={"full_name": "Tên mới", "username": "Moi.Ten"})
    assert r.status_code == 200 and r.json()["full_name"] == "Tên mới" and r.json()["username"] == "moi.ten"
    assert client.patch(f"/admin/users/{u['id']}", headers=h, json={"email": ""}).json()["email"] is None
    assert client.patch("/admin/users/999999", headers=h, json={"full_name": "x"}).status_code == 404


def test_reset_password_sets_must_change(client, admin, make_user, conn):
    _, h = admin
    u = make_user("student", username="sva")
    old_refresh = login(client, "sva", "Pass1234").json()["refresh_token"]
    r = client.post(f"/admin/users/{u['id']}/reset-password", headers=h)
    temp = r.json()["temp_password"]
    assert login(client, "sva", "Pass1234").status_code == 401
    assert login(client, "sva", temp).json()["user"]["must_change_password"] is True
    assert code(client.post("/auth/refresh", json={"refresh_token": old_refresh})) == "AUTH_TOKEN_REVOKED"



def test_reset_password_self_blocked(client, admin, conn):
    """Tự đặt lại thì mất ngay mật khẩu đang dùng và tự khóa mình ra ngoài."""
    a, h = admin
    assert client.post(f"/admin/users/{a['id']}/reset-password", headers=h).status_code == 422
    assert conn.execute("SELECT must_change_password FROM users WHERE id = %s", (a["id"],)).fetchone()[
        "must_change_password"] is False


def test_cli_reset_password(client, make_user, capsys):
    from app import cli
    make_user("admin", username="boss")
    assert cli.main(["reset-password", "--username", "boss"]) == 0
    temp = capsys.readouterr().out.rsplit(": ", 1)[1].strip()
    assert login(client, "boss", temp).json()["user"]["must_change_password"] is True
    assert cli.main(["reset-password", "--username", "khong.co"]) == 1


def test_deactivate_bumps_token_version_and_revokes_face(client, admin, make_user, conn):
    _, h = admin
    u = make_user("student", username="sva")
    conn.execute("INSERT INTO face_templates (student_id, model_name, status, embedding_enc) "
                 "VALUES (%s, 'm', 'approved', 'x')", (u["id"],))
    old_refresh = login(client, "sva", "Pass1234").json()["refresh_token"]
    assert client.post(f"/admin/users/{u['id']}/deactivate", headers=h).status_code == 200
    row = conn.execute("SELECT is_active, token_version FROM users WHERE id = %s", (u["id"],)).fetchone()
    assert row == {"is_active": False, "token_version": 1}
    face = conn.execute("SELECT status, embedding_enc FROM face_templates").fetchone()
    assert face == {"status": "revoked", "embedding_enc": None}
    assert code(client.post("/auth/refresh", json={"refresh_token": old_refresh})) == "AUTH_TOKEN_REVOKED"
    assert login(client, "sva", "Pass1234").status_code == 401
    assert client.post(f"/admin/users/{u['id']}/activate", headers=h).json()["is_active"] is True
    assert login(client, "sva", "Pass1234").status_code == 200


def test_admin_cannot_deactivate_or_delete_self(client, admin):
    a, h = admin
    assert client.post(f"/admin/users/{a['id']}/deactivate", headers=h).status_code == 422
    assert client.delete(f"/admin/users/{a['id']}", headers=h).status_code == 422


def test_delete_user_with_data_is_blocked(client, admin, make_user, make_class, conn):
    _, h = admin
    gv = make_user("lecturer")
    make_class(gv["id"])
    r = client.delete(f"/admin/users/{gv['id']}", headers=h)
    assert r.status_code == 409 and code(r) == "USER_HAS_DATA"
    assert conn.execute("SELECT count(*) c FROM users WHERE id = %s", (gv["id"],)).fetchone()["c"] == 1
    fresh = make_user("student")
    assert client.delete(f"/admin/users/{fresh['id']}", headers=h).status_code == 204


def test_delete_face_data(client, admin, make_user, conn):
    _, h = admin
    u = make_user("student")
    conn.execute("INSERT INTO face_templates (student_id, model_name, status, embedding_enc) "
                 "VALUES (%s, 'm', 'approved', 'x')", (u["id"],))
    assert client.delete(f"/admin/users/{u['id']}/face", headers=h).status_code == 204
    assert conn.execute("SELECT status FROM face_templates").fetchone()["status"] == "revoked"


def test_classes_crud(client, admin, make_user, conn):
    _, h = admin
    gv = make_user("lecturer", full_name="TS. Đức")
    sv = make_user("student")
    body = {"code": "IT4060", "name": "Học máy", "semester": "2026-1", "lecturer_id": gv["id"]}
    r = client.post("/admin/classes", headers=h, json=body)
    assert r.status_code == 201
    cid = r.json()["id"]
    dup = client.post("/admin/classes", headers=h, json=body)
    assert dup.status_code == 422 and dup.json()["error"]["details"][0]["field"] == "code"
    bad = client.post("/admin/classes", headers=h, json={**body, "code": "X", "lecturer_id": sv["id"]})
    assert bad.status_code == 422 and bad.json()["error"]["details"][0]["field"] == "lecturer_id"
    item = client.get("/admin/classes", headers=h, params={"semester": "2026-1"}).json()["items"][0]
    assert item["lecturer_name"] == "TS. Đức" and item["student_count"] == 0 and item["session_count"] == 0
    assert client.patch(f"/admin/classes/{cid}", headers=h, json={"name": "ML"}).json()["name"] == "ML"
    assert client.delete(f"/admin/classes/{cid}", headers=h).status_code == 204


def test_delete_class_with_session_is_blocked(client, admin, make_user, make_class, conn):
    _, h = admin
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    conn.execute("INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, "
                 "base_radius_m, room_secret, expires_at) VALUES (%s, %s, 21, 105, 9, 20, 'k', now())",
                 (c["id"], gv["id"]))
    r = client.delete(f"/admin/classes/{c['id']}", headers=h)
    assert r.status_code == 409 and code(r) == "CLASS_HAS_SESSIONS"


def test_enrollments(client, admin, make_user, make_class):
    _, h = admin
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    sv = make_user("student", student_code="SV120")
    r = client.post("/admin/enrollments", headers=h, json={"class_id": c["id"], "student_code": "SV120"})
    assert r.status_code == 201
    assert client.post("/admin/enrollments", headers=h,
                       json={"class_id": c["id"], "student_code": "SV120"}).status_code == 201  # lặp lại: không lỗi
    nf = client.post("/admin/enrollments", headers=h, json={"class_id": c["id"], "student_code": "SV404"})
    assert nf.status_code == 422 and nf.json()["error"]["details"][0]["field"] == "student_code"
    students = client.get("/admin/enrollments", headers=h, params={"class_id": c["id"]}).json()
    assert [s["id"] for s in students] == [sv["id"]] and students[0]["face_status"] == "none"
    assert client.delete(f"/admin/enrollments/{c['id']}/{sv['id']}", headers=h).status_code == 204
    assert client.get("/admin/enrollments", headers=h, params={"class_id": c["id"]}).json() == []


def test_import_endpoint(client, admin, conn):
    _, h = admin
    body = {"kind": "users", "dry_run": False, "csv_text": "role,username,full_name,student_code\nstudent,sv1,A,SV1\n"}
    r = client.post("/admin/import", headers=h, json=body)
    assert r.status_code == 200 and r.json()["created"] == 1 and len(r.json()["passwords"]) == 1
    assert conn.execute("SELECT action FROM audit_log").fetchone()["action"] == "import.users"


def test_audit_log_paginated_and_filtered(client, admin, make_user):
    a, h = admin
    for i in range(3):
        client.post("/admin/users", headers=h, json={"role": "lecturer", "username": f"gv{i}", "full_name": "G"})
    u = make_user("student")
    client.post(f"/admin/users/{u['id']}/reset-password", headers=h)
    r = client.get("/admin/audit-log", headers=h, params={"size": 2})
    assert r.json()["total"] == 4 and len(r.json()["items"]) == 2
    first = r.json()["items"][0]
    assert first["action"] == "user.reset_password" and first["actor_name"] == a["full_name"]
    assert client.get("/admin/audit-log", headers=h, params={"action": "user.create"}).json()["total"] == 3
    assert client.get("/admin/audit-log", headers=h, params={"actor_id": u["id"]}).json()["total"] == 0
    assert client.get("/admin/audit-log", headers=h, params={"action": "user."}).json()["total"] == 4
    assert client.get("/admin/audit-log", headers=h, params={"actor": a["full_name"][:4].lower()}).json()["total"] == 4
    assert client.get("/admin/audit-log", headers=h, params={"actor": "khong-co"}).json()["total"] == 0
    assert first["target_name"] == u["full_name"]


def test_cli_create_admin(conn, capsys):
    assert cli.main(["create-admin", "--username", "Root"]) == 0
    temp = capsys.readouterr().out.strip().split()[-1]
    row = conn.execute("SELECT role, username, email, must_change_password, password_hash FROM users").fetchone()
    assert (row["role"], row["username"], row["email"], row["must_change_password"]) == ("admin", "root", None, True)
    from app.security import verify_password
    assert verify_password(temp, row["password_hash"])
    assert cli.main(["create-admin", "--username", "root"]) == 1
    assert cli.main(["create-admin", "--username", "a b"]) == 1
