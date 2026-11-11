"""Nhập CSV người dùng / lớp / danh sách lớp (mục 4.1). Có một dòng lỗi thì không ghi dòng nào."""
import csv
import io
from concurrent.futures import ThreadPoolExecutor
from typing import Literal

import psycopg

from app.security import USERNAME_RULE, hash_password, normalize_username, temp_password

Kind = Literal["users", "classes", "enrollments"]
COLUMNS = {
    "users": ["role", "username", "email", "full_name", "student_code"],
    "classes": ["code", "name", "semester", "lecturer_username"],
    "enrollments": ["class_code", "semester", "student_code"],
}
OPTIONAL = {"email"}  # cột có thể không có trong file
ROLES = ("student", "lecturer", "admin")


def _rows(csv_text: str) -> tuple[list[str], list[tuple[int, dict]]]:
    reader = csv.DictReader(io.StringIO(csv_text.lstrip("﻿")))
    header = [h.strip() for h in reader.fieldnames or []]
    reader.fieldnames = header
    rows = []
    for row in reader:
        clean = {k: (v or "").strip() for k, v in row.items() if k}
        if any(clean.values()):  # bỏ dòng trống
            rows.append((reader.line_num, clean))
    return header, rows


def run(conn: psycopg.Connection, kind: Kind, csv_text: str, dry_run: bool) -> dict:
    header, rows = _rows(csv_text)
    missing = [c for c in COLUMNS[kind] if c not in header and c not in OPTIONAL]
    if missing:
        return _result([{"line": 1, "col": None, "msg": "Thiếu cột: " + ", ".join(missing)}], total=len(rows))
    errors: list[dict] = []
    check, write = _HANDLERS[kind]
    valid = check(conn, rows, errors)
    if errors:
        return _result(errors, total=len(rows))
    if dry_run:
        return _result([], created=len(valid), total=len(rows))
    return {**write(conn, valid), "total_rows": len(rows)}


def _result(errors, created=0, passwords=None, total=0):
    """total_rows: số dòng dữ liệu; error_rows: số dòng có lỗi (một dòng có thể chỉ báo lỗi đầu tiên)."""
    return {"ok": not errors, "errors": errors, "created": created, "passwords": passwords or [],
            "total_rows": total, "error_rows": len({e["line"] for e in errors})}


def _err(errors, line, msg, col):
    errors.append({"line": line, "col": col, "msg": msg})


# ---- users ----

def _check_users(conn, rows, errors):
    names = {r["username"] for r in conn.execute("SELECT username FROM users")}
    emails = {r["email"] for r in conn.execute("SELECT lower(email) email FROM users WHERE email IS NOT NULL")}
    codes = {r["student_code"] for r in conn.execute("SELECT student_code FROM users WHERE student_code IS NOT NULL")}
    seen_name, seen_email, seen_code, valid = {}, {}, {}, []
    for line, r in rows:
        role, name, email = r["role"].lower(), normalize_username(r["username"]), r.get("email", "").lower() or None
        full_name, sc = r["full_name"], r["student_code"]
        if role not in ROLES:
            _err(errors, line, f"Vai trò không hợp lệ: {r['role']} (chỉ nhận student, lecturer, admin)", "role")
        elif not name:
            _err(errors, line, f"Tên đăng nhập không hợp lệ: {r['username']} ({USERNAME_RULE})", "username")
        elif email and ("@" not in email or " " in email):
            _err(errors, line, f"Email không hợp lệ: {email}", "email")
        elif not full_name:
            _err(errors, line, "Thiếu họ tên", "full_name")
        elif role == "student" and not sc:
            _err(errors, line, "Sinh viên phải có mã sinh viên", "student_code")
        elif name in seen_name:
            _err(errors, line, f"Tên đăng nhập trùng với dòng {seen_name[name]}: {name}", "username")
        elif name in names:
            _err(errors, line, f"Tên đăng nhập đã tồn tại: {name}", "username")
        elif email and email in seen_email:
            _err(errors, line, f"Email trùng với dòng {seen_email[email]}: {email}", "email")
        elif email and email in emails:
            _err(errors, line, f"Email đã tồn tại: {email}", "email")
        elif sc and sc in seen_code:
            _err(errors, line, f"Mã sinh viên trùng với dòng {seen_code[sc]}: {sc}", "student_code")
        elif sc and sc in codes:
            _err(errors, line, f"Mã sinh viên đã tồn tại: {sc}", "student_code")
        else:
            valid.append({"role": role, "username": name, "email": email, "full_name": full_name,
                          "student_code": sc if role == "student" else None})
        for seen, key in ((seen_name, name), (seen_email, email), (seen_code, sc)):
            if key:
                seen.setdefault(key, line)
    return valid


def _write_users(conn, valid):
    passwords = [temp_password() for _ in valid]
    with ThreadPoolExecutor() as ex:  # argon2 nhả GIL: băm song song cho file vài trăm dòng
        hashes = list(ex.map(hash_password, passwords))
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO users (role, username, email, full_name, student_code, password_hash, must_change_password) "
            "VALUES (%(role)s, %(username)s, %(email)s, %(full_name)s, %(student_code)s, %(h)s, true)",
            [{**v, "h": h} for v, h in zip(valid, hashes)])
    return _result([], created=len(valid),
                   passwords=[{"username": v["username"], "temp_password": p} for v, p in zip(valid, passwords)])


# ---- classes ----

def _check_classes(conn, rows, errors):
    lecturers = {r["username"]: r["id"] for r in
                 conn.execute("SELECT username, id FROM users WHERE role = 'lecturer' AND is_active")}
    existing = {(r["code"], r["semester"]) for r in conn.execute("SELECT code, semester FROM classes")}
    seen, valid = {}, []
    for line, r in rows:
        key = (r["code"], r["semester"])
        lecturer = lecturers.get(r["lecturer_username"].lower())
        if not (r["code"] and r["name"] and r["semester"]):
            _err(errors, line, "Thiếu mã lớp, tên lớp hoặc học kỳ", "code")
        elif lecturer is None:
            _err(errors, line, f"Không có giảng viên với tên đăng nhập: {r['lecturer_username']}", "lecturer_username")
        elif key in seen:
            _err(errors, line, f"Lớp trùng với dòng {seen[key]}: {key[0]} ({key[1]})", "code")
        elif key in existing:
            _err(errors, line, f"Lớp đã tồn tại: {key[0]} ({key[1]})", "code")
        else:
            valid.append({"code": key[0], "name": r["name"], "semester": key[1], "lecturer_id": lecturer})
        seen.setdefault(key, line)
    return valid


def _write_classes(conn, valid):
    with conn.cursor() as cur:
        cur.executemany("INSERT INTO classes (code, name, semester, lecturer_id) "
                        "VALUES (%(code)s, %(name)s, %(semester)s, %(lecturer_id)s)", valid)
    return _result([], created=len(valid))


# ---- enrollments ----

def _check_enrollments(conn, rows, errors):
    classes = {(r["code"], r["semester"]): r["id"] for r in conn.execute("SELECT id, code, semester FROM classes")}
    students = {r["student_code"]: r["id"] for r in
                conn.execute("SELECT id, student_code FROM users WHERE role = 'student' AND student_code IS NOT NULL")}
    existing = {(r["class_id"], r["student_id"]) for r in conn.execute("SELECT class_id, student_id FROM enrollments")}
    valid = set()
    for line, r in rows:
        cid = classes.get((r["class_code"], r["semester"]))
        sid = students.get(r["student_code"])
        if cid is None:
            _err(errors, line, f"Không có lớp: {r['class_code']} ({r['semester']})", "class_code")
        elif sid is None:
            _err(errors, line, f"Không có sinh viên với mã: {r['student_code']}", "student_code")
        elif (cid, sid) not in existing:  # đã có thì bỏ qua, không báo lỗi
            valid.add((cid, sid))
    return sorted(valid)


def _write_enrollments(conn, valid):
    with conn.cursor() as cur:
        cur.executemany("INSERT INTO enrollments (class_id, student_id) VALUES (%s, %s)", valid)
    return _result([], created=len(valid))


_HANDLERS = {
    "users": (_check_users, _write_users),
    "classes": (_check_classes, _write_classes),
    "enrollments": (_check_enrollments, _write_enrollments),
}
