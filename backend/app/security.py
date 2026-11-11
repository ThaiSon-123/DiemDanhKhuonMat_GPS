"""Băm mật khẩu, JWT, khóa đăng nhập tạm và dependency phân quyền (đặc tả mục 9.3, 9.5)."""
import os
import re
import secrets
import time
from collections import deque
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from functools import lru_cache

import jwt
import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.db import get_conn
from app.errors import ApiError

_hasher = PasswordHasher()


def clock() -> float:
    """Giờ hiện tại (epoch giây); test thay hàm này để tua thời gian."""
    return time.time()


def hash_password(p: str) -> str:
    return _hasher.hash(p)


def verify_password(p: str, h: str) -> bool:
    try:
        return _hasher.verify(h, p)
    except (VerificationError, InvalidHashError):
        return False


USERNAME_RE = re.compile(r"[a-z0-9._-]{3,50}")
USERNAME_RULE = "Tên đăng nhập chỉ gồm a-z, 0-9, dấu . _ - và dài 3–50 ký tự"


def normalize_username(s: str) -> str | None:
    """Chữ thường, bỏ khoảng trắng hai đầu; None nếu sai định dạng."""
    s = s.strip().lower()
    return s if USERNAME_RE.fullmatch(s) else None


_TEMP_ALPHABET = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789"  # bỏ ký tự dễ nhầm: 0 O 1 l I


def temp_password() -> str:
    return "".join(secrets.choice(_TEMP_ALPHABET) for _ in range(10))


@lru_cache
def dummy_hash() -> str:
    """Băm giả để tên đăng nhập không tồn tại cũng tốn thời gian như tài khoản có thật."""
    return hash_password("khong-ton-tai")


# ---- JWT ----

def _secret() -> str:
    return os.environ["JWT_SECRET"]


def create_tokens(user: dict) -> dict:
    cfg = get_settings().auth
    now = datetime.fromtimestamp(clock(), timezone.utc)
    base = {"sub": str(user["id"]), "role": user["role"], "tv": user["token_version"], "iat": now}
    access = jwt.encode({**base, "typ": "access", "exp": now + timedelta(minutes=cfg.access_minutes)}, _secret())
    refresh = jwt.encode({**base, "typ": "refresh", "exp": now + timedelta(days=cfg.refresh_days)}, _secret())
    return {"access_token": access, "refresh_token": refresh, "expires_in": cfg.access_minutes * 60}


def _revoked() -> ApiError:
    return ApiError(401, "AUTH_TOKEN_REVOKED", "Phiên đăng nhập không còn hiệu lực, hãy đăng nhập lại")


def decode_token(token: str, typ: str) -> dict:
    try:
        claims = jwt.decode(token, _secret(), algorithms=["HS256"], options={"require": ["exp", "sub", "typ", "tv"]})
    except jwt.ExpiredSignatureError:
        if typ == "access":
            raise ApiError(401, "AUTH_TOKEN_EXPIRED", "Phiên đăng nhập đã hết hạn")
        raise _revoked()
    except jwt.InvalidTokenError:
        raise _revoked()
    if claims["typ"] != typ:
        raise _revoked()
    return claims


def load_token_user(conn: psycopg.Connection, claims: dict) -> dict:
    """Dòng users của token; tài khoản bị vô hiệu hóa hoặc token_version đã tăng thì coi như thu hồi."""
    user = conn.execute("SELECT * FROM users WHERE id = %s", (int(claims["sub"]),)).fetchone()
    if not user or not user["is_active"] or user["token_version"] != claims["tv"]:
        raise _revoked()
    return user


# ---- Khóa đăng nhập tạm ----
# ponytail: chỉ đúng với 1 worker uvicorn (deploy dùng 1 worker); chạy nhiều worker thì chuyển sang bảng hoặc Redis.
_failures: dict[str, deque[float]] = {}


def reset_login_failures() -> None:
    _failures.clear()


def _recent_failures(username: str) -> deque[float]:
    window = get_settings().auth.lock_minutes * 60
    q = _failures.setdefault(username, deque())
    while q and q[0] <= clock() - window:
        q.popleft()
    return q


def check_login_allowed(username: str) -> None:
    cfg = get_settings().auth
    if len(_recent_failures(username)) >= cfg.max_failures:
        raise ApiError(429, "RATE_LIMITED",
                       f"Đăng nhập sai quá nhiều lần. Hãy thử lại sau {cfg.lock_minutes} phút.")


def record_login_failure(username: str) -> int:
    """Ghi một lần sai, trả số lần còn được thử trước khi bị khóa."""
    q = _recent_failures(username)
    q.append(clock())
    return max(get_settings().auth.max_failures - len(q), 0)


def clear_login_failures(username: str) -> None:
    _failures.pop(username, None)


# ---- Dependency ----
_bearer = HTTPBearer(auto_error=False)


def token_user(cred: HTTPAuthorizationCredentials | None = Depends(_bearer),
               conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Người dùng của access token, KHÔNG chặn must_change_password. Chỉ dùng cho /me và đổi mật khẩu."""
    if cred is None:
        raise _revoked()
    return load_token_user(conn, decode_token(cred.credentials, "access"))


def current_user(user: dict = Depends(token_user)) -> dict:
    if user["must_change_password"]:
        raise ApiError(403, "PASSWORD_CHANGE_REQUIRED", "Bạn cần đổi mật khẩu trước khi tiếp tục")
    return user


def require_role(*roles: str) -> Callable[..., dict]:
    def dep(user: dict = Depends(current_user)) -> dict:
        if user["role"] not in roles:
            raise ApiError(403, "FORBIDDEN", "Bạn không có quyền thực hiện thao tác này")
        return user
    return dep
