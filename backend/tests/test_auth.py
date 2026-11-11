import time

from fastapi import Depends

from app import security
from app.main import app
from app.security import current_user, require_role


# Route chỉ dùng cho test phân quyền; route thật của sinh viên / giảng viên làm ở các task sau.
@app.get("/__test/any")
def _any(user=Depends(current_user)):
    return {"id": user["id"]}


@app.get("/__test/lecturer")
def _lecturer(user=Depends(require_role("lecturer", "admin"))):
    return {"id": user["id"]}


def login(client, email, password="Pass1234"):
    return client.post("/auth/login", json={"email": email, "password": password})


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def code(r):
    return r.json()["error"]["code"]



def set_clock(monkeypatch, t):
    monkeypatch.setattr(security, "clock", lambda: t)


def test_login_ok_returns_tokens_and_user(client, make_user):
    u = make_user("student", email="a@x.vn")
    r = login(client, "a@x.vn")
    assert r.status_code == 200
    body = r.json()
    assert body["expires_in"] == 900 and body["access_token"] and body["refresh_token"]
    assert body["user"] == {"id": u["id"], "role": "student", "full_name": u["full_name"],
                            "must_change_password": False}


def test_login_email_is_case_insensitive(client, make_user):
    make_user("student", email="a@x.vn")
    assert login(client, "  A@X.vn ").status_code == 200


def test_login_wrong_password_and_unknown_email(client, make_user):
    make_user("student", email="a@x.vn")
    for r in (login(client, "a@x.vn", "sai-mat-khau"), login(client, "khong-co@x.vn")):
        assert r.status_code == 401 and code(r) == "AUTH_INVALID_CREDENTIALS"


def test_inactive_user_cannot_login(client, make_user):
    make_user("student", email="a@x.vn", is_active=False)
    r = login(client, "a@x.vn")
    assert r.status_code == 401 and code(r) == "AUTH_INVALID_CREDENTIALS"


def test_locked_after_10_failures_then_unlocked_after_15_minutes(client, make_user, monkeypatch):
    make_user("student", email="a@x.vn")
    t0 = time.time()
    set_clock(monkeypatch, t0)
    for _ in range(10):
        assert login(client, "a@x.vn", "sai").status_code == 401
    r = login(client, "a@x.vn")  # lần 11, mật khẩu đúng vẫn bị khóa
    assert r.status_code == 429 and code(r) == "RATE_LIMITED"
    set_clock(monkeypatch, t0 + 15 * 60 + 1)
    assert login(client, "a@x.vn").status_code == 200


def test_success_resets_failure_count(client, make_user):
    make_user("student", email="a@x.vn")
    for _ in range(2):
        for _ in range(9):
            login(client, "a@x.vn", "sai")
        assert login(client, "a@x.vn").status_code == 200


def test_missing_or_garbage_token(client):
    assert code(client.get("/__test/any")) == "AUTH_TOKEN_REVOKED"
    r = client.get("/__test/any", headers=bearer("abc.def.ghi"))
    assert r.status_code == 401 and code(r) == "AUTH_TOKEN_REVOKED"


def test_expired_access_token(client, make_user, monkeypatch):
    make_user("student", email="a@x.vn")
    set_clock(monkeypatch, time.time() - 14 * 60)  # token cấp 14 phút trước: còn hạn
    assert client.get("/__test/any", headers=bearer(login(client, "a@x.vn").json()["access_token"])).status_code == 200
    set_clock(monkeypatch, time.time() - 16 * 60)  # cấp 16 phút trước: hết hạn
    r = client.get("/__test/any", headers=bearer(login(client, "a@x.vn").json()["access_token"]))
    assert r.status_code == 401 and code(r) == "AUTH_TOKEN_EXPIRED"


def test_refresh_and_access_tokens_are_not_interchangeable(client, make_user):
    make_user("student", email="a@x.vn")
    t = login(client, "a@x.vn").json()
    assert code(client.get("/__test/any", headers=bearer(t["refresh_token"]))) == "AUTH_TOKEN_REVOKED"
    assert code(client.post("/auth/refresh", json={"refresh_token": t["access_token"]})) == "AUTH_TOKEN_REVOKED"


def test_refresh_issues_new_pair(client, make_user):
    make_user("student", email="a@x.vn")
    t = login(client, "a@x.vn").json()
    r = client.post("/auth/refresh", json={"refresh_token": t["refresh_token"]})
    assert r.status_code == 200 and r.json()["expires_in"] == 900
    assert client.get("/__test/any", headers=bearer(r.json()["access_token"])).status_code == 200


def test_refresh_expires_after_7_days(client, make_user, monkeypatch):
    make_user("student", email="a@x.vn")
    set_clock(monkeypatch, time.time() - 7 * 86400 - 60)
    rt = login(client, "a@x.vn").json()["refresh_token"]
    r = client.post("/auth/refresh", json={"refresh_token": rt})
    assert r.status_code == 401 and code(r) == "AUTH_TOKEN_REVOKED"


def test_deactivated_user_tokens_stop_working(client, make_user, conn):
    u = make_user("student", email="a@x.vn")
    t = login(client, "a@x.vn").json()
    conn.execute("UPDATE users SET is_active = false WHERE id = %s", (u["id"],))
    assert code(client.get("/__test/any", headers=bearer(t["access_token"]))) == "AUTH_TOKEN_REVOKED"
    assert code(client.post("/auth/refresh", json={"refresh_token": t["refresh_token"]})) == "AUTH_TOKEN_REVOKED"


def test_change_password_revokes_old_tokens_and_returns_new_pair(client, make_user, conn):
    u = make_user("student", email="a@x.vn", password="Tmp-4821", must_change_password=True)
    old = login(client, "a@x.vn", "Tmp-4821").json()
    r = client.post("/auth/change-password", headers=bearer(old["access_token"]),
                    json={"old_password": "Tmp-4821", "new_password": "matkhaumoi2026"})
    assert r.status_code == 200
    new = r.json()
    row = conn.execute("SELECT must_change_password, token_version FROM users WHERE id = %s", (u["id"],)).fetchone()
    assert row == {"must_change_password": False, "token_version": 1}
    # Token cũ hết hiệu lực; token mới dùng được; mật khẩu mới đăng nhập được.
    assert code(client.post("/auth/refresh", json={"refresh_token": old["refresh_token"]})) == "AUTH_TOKEN_REVOKED"
    assert code(client.get("/__test/any", headers=bearer(old["access_token"]))) == "AUTH_TOKEN_REVOKED"
    assert client.get("/__test/any", headers=bearer(new["access_token"])).status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": new["refresh_token"]}).status_code == 200
    assert login(client, "a@x.vn", "matkhaumoi2026").json()["user"]["must_change_password"] is False


def test_change_password_wrong_old_password(client, make_user, auth):
    u = make_user("student")
    r = client.post("/auth/change-password", headers=auth(u),
                    json={"old_password": "sai", "new_password": "matkhaumoi2026"})
    assert r.status_code == 401 and code(r) == "AUTH_INVALID_CREDENTIALS"


def test_change_password_rules(client, make_user, auth):
    u = make_user("student")
    for new in ("ngan", "Pass1234"):  # dưới 8 ký tự; trùng mật khẩu cũ
        r = client.post("/auth/change-password", headers=auth(u),
                        json={"old_password": "Pass1234", "new_password": new})
        assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"


def test_must_change_password_blocks_other_routes(client, make_user, auth):
    u = make_user("student", must_change_password=True)
    r = client.get("/__test/any", headers=auth(u))
    assert r.status_code == 403 and code(r) == "PASSWORD_CHANGE_REQUIRED"
    me = client.get("/me", headers=auth(u))
    assert me.status_code == 200 and me.json()["must_change_password"] is True


def test_me_returns_account(client, make_user, auth):
    u = make_user("student", email="a@x.vn")
    assert client.get("/me", headers=auth(u)).json() == {
        "id": u["id"], "role": "student", "full_name": u["full_name"], "email": "a@x.vn",
        "student_code": u["student_code"], "must_change_password": False}


def test_require_role(client, make_user, auth):
    s, gv, ad = make_user("student"), make_user("lecturer"), make_user("admin")
    r = client.get("/__test/lecturer", headers=auth(s))
    assert r.status_code == 403 and code(r) == "FORBIDDEN"
    assert client.get("/__test/lecturer", headers=auth(gv)).status_code == 200
    assert client.get("/__test/lecturer", headers=auth(ad)).status_code == 200
