import psycopg
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app import security
from app.db import get_conn
from app.errors import ApiError

router = APIRouter(prefix="/auth", tags=["auth"])


class LoginIn(BaseModel):
    username: str = Field(max_length=50)
    password: str = Field(max_length=256)


class RefreshIn(BaseModel):
    refresh_token: str


class ChangePasswordIn(BaseModel):
    old_password: str = Field(max_length=256)
    new_password: str = Field(min_length=8, max_length=256)


def _public(user: dict) -> dict:
    return {k: user[k] for k in ("id", "role", "username", "full_name", "must_change_password")}


@router.post("/login")
def login(body: LoginIn, conn: psycopg.Connection = Depends(get_conn)):
    username = body.username.strip().lower()
    security.check_login_allowed(username)
    user = conn.execute("SELECT * FROM users WHERE username = %s", (username,)).fetchone()
    ok = security.verify_password(body.password, user["password_hash"] if user else security.dummy_hash())
    if not (ok and user["is_active"]):
        left = security.record_login_failure(username)
        raise ApiError(401, "AUTH_INVALID_CREDENTIALS",
                       f"Tên đăng nhập hoặc mật khẩu không đúng. Còn {left} lần thử trước khi bị khóa tạm 15 phút.",
                       {"remaining_attempts": left})
    security.clear_login_failures(username)
    return {**security.create_tokens(user), "user": _public(user)}


@router.post("/refresh")
def refresh(body: RefreshIn, conn: psycopg.Connection = Depends(get_conn)):
    user = security.load_token_user(conn, security.decode_token(body.refresh_token, "refresh"))
    return security.create_tokens(user)


@router.post("/change-password")
def change_password(body: ChangePasswordIn, user: dict = Depends(security.token_user),
                    conn: psycopg.Connection = Depends(get_conn)):
    if not security.verify_password(body.old_password, user["password_hash"]):
        raise ApiError(401, "AUTH_INVALID_CREDENTIALS", "Mật khẩu hiện tại không đúng")
    if body.new_password == body.old_password:
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ",
                       [{"field": "new_password", "msg": "Mật khẩu mới phải khác mật khẩu hiện tại"}])
    # Tăng token_version: mọi token cũ (kể cả của máy khác) mất hiệu lực; máy này nhận cặp token mới.
    user = conn.execute(
        "UPDATE users SET password_hash = %s, must_change_password = false, token_version = token_version + 1 "
        "WHERE id = %s RETURNING *", (security.hash_password(body.new_password), user["id"])).fetchone()
    return security.create_tokens(user)
