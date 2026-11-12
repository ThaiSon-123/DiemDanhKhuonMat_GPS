"""Lệnh quản trị chạy từ terminal:
    python -m app.cli create-admin --username <tên đăng nhập>
    python -m app.cli reset-password --username <tên đăng nhập>   (vd quản trị viên quên mật khẩu)
"""
import argparse
import sys

from dotenv import load_dotenv

from app.config import BASE_DIR


def create_admin(username: str, full_name: str, email: str | None) -> int:
    from app.db import get_pool
    from app.security import USERNAME_RULE, hash_password, normalize_username, temp_password

    name = normalize_username(username)
    if not name:
        print(USERNAME_RULE, file=sys.stderr)
        return 1
    email = (email or "").strip().lower() or None
    with get_pool().connection() as conn:
        if conn.execute("SELECT 1 FROM users WHERE username = %s OR lower(email) = %s", (name, email)).fetchone():
            print(f"Tên đăng nhập hoặc email đã tồn tại: {name}", file=sys.stderr)
            return 1
        temp = temp_password()
        conn.execute("INSERT INTO users (role, username, email, full_name, password_hash, must_change_password) "
                     "VALUES ('admin', %s, %s, %s, %s, true)", (name, email, full_name, hash_password(temp)))
    print(f"Đã tạo quản trị viên {name}. Mật khẩu tạm (đổi ở lần đăng nhập đầu): {temp}")
    return 0


def reset_password(username: str) -> int:
    from app.db import get_pool
    from app.security import hash_password, normalize_username, temp_password

    name = normalize_username(username) or username
    temp = temp_password()
    with get_pool().connection() as conn:
        row = conn.execute("UPDATE users SET password_hash = %s, must_change_password = true, "
                           "token_version = token_version + 1 WHERE username = %s RETURNING id",
                           (hash_password(temp), name)).fetchone()
        if not row:
            print(f"Không có tài khoản: {name}", file=sys.stderr)
            return 1
        from app import audit
        audit.log(conn, None, "user.reset_password.cli", f"users:{row['id']}")
    print(f"Đã đặt lại mật khẩu cho {name}. Mật khẩu tạm (đổi ở lần đăng nhập đầu): {temp}")
    return 0


def main(argv: list[str] | None = None) -> int:
    load_dotenv(BASE_DIR / ".env")  # không ghi đè biến môi trường đã có
    p = argparse.ArgumentParser(prog="python -m app.cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create-admin", help="Tạo quản trị viên đầu tiên")
    c.add_argument("--username", required=True)
    c.add_argument("--name", default="Quản trị viên")
    c.add_argument("--email")
    r = sub.add_parser("reset-password", help="Cấp mật khẩu tạm mới cho một tài khoản")
    r.add_argument("--username", required=True)
    args = p.parse_args(argv)
    if args.cmd == "reset-password":
        return reset_password(args.username)
    return create_admin(args.username, args.name, args.email)


if __name__ == "__main__":
    sys.exit(main())
