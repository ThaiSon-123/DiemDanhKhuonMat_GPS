"""Quản trị: người dùng, lớp, danh sách lớp, nhập CSV, nhật ký (đặc tả mục 4.1, 9.3)."""
from datetime import datetime
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, Field

from app import audit, face_data, security
from app.db import get_conn
from app.errors import ApiError
from app.services import importer

router = APIRouter(prefix="/admin", tags=["admin"])
Admin = Depends(security.require_role("admin"))
Conn = Depends(get_conn)

USER_COLS = "u.id, u.role, u.username, u.email, u.full_name, u.student_code, u.is_active, u.must_change_password, u.created_at"


def invalid(field: str, msg: str) -> ApiError:
    return ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ", [{"field": field, "msg": msg}])


def not_found() -> ApiError:
    return ApiError(404, "NOT_FOUND", "Không tìm thấy")


def ip_of(request: Request) -> str | None:
    return request.client.host if request.client else None


def page_params(page: int = Query(1, ge=1), size: int = Query(50, ge=1, le=200)) -> tuple[int, int]:
    return page, size


def paginate(conn, select: str, where: list[str], params: list, order: str, page: tuple[int, int]) -> dict:
    w = " WHERE " + " AND ".join(where) if where else ""
    total = conn.execute(f"SELECT count(*) c FROM ({select}{w}) t", params).fetchone()["c"]
    items = conn.execute(f"{select}{w} ORDER BY {order} LIMIT %s OFFSET %s",
                         [*params, page[1], (page[0] - 1) * page[1]]).fetchall()
    return {"items": items, "total": total}


# ---------------- Người dùng ----------------

class UserIn(BaseModel):
    role: Literal["student", "lecturer", "admin"]
    username: str = Field(max_length=50)
    email: str | None = Field(None, max_length=254)
    full_name: str = Field(min_length=1, max_length=200)
    student_code: str | None = Field(None, max_length=50)


class UserPatch(BaseModel):
    username: str | None = Field(None, max_length=50)
    email: str | None = Field(None, max_length=254)
    full_name: str | None = Field(None, min_length=1, max_length=200)
    student_code: str | None = Field(None, max_length=50)


def get_user(conn, user_id: int) -> dict:
    u = conn.execute(f"SELECT {USER_COLS} FROM users u WHERE u.id = %s", (user_id,)).fetchone()
    if not u:
        raise not_found()
    return u


def check_unique(conn, username: str | None, email: str | None, student_code: str | None,
                 exclude_id: int = 0) -> None:
    if username and conn.execute("SELECT 1 FROM users WHERE username = %s AND id <> %s",
                                 (username, exclude_id)).fetchone():
        raise invalid("username", f"Tên đăng nhập đã tồn tại: {username}")
    if email and conn.execute("SELECT 1 FROM users WHERE lower(email) = %s AND id <> %s",
                              (email, exclude_id)).fetchone():
        raise invalid("email", f"Email đã tồn tại: {email}")
    if student_code and conn.execute("SELECT 1 FROM users WHERE student_code = %s AND id <> %s",
                                     (student_code, exclude_id)).fetchone():
        raise invalid("student_code", f"Mã sinh viên đã tồn tại: {student_code}")


def check_username(username: str) -> str:
    u = security.normalize_username(username)
    if not u:
        raise invalid("username", security.USERNAME_RULE)
    return u


def check_email(email: str | None) -> str | None:
    """Email tùy chọn: rỗng thì None."""
    email = (email or "").strip().lower()
    if not email:
        return None
    if "@" not in email or " " in email:
        raise invalid("email", "Email không hợp lệ")
    return email


@router.get("/users")
def list_users(q: str | None = None, role: str | None = None,
               face: Literal["none", "pending", "approved", "rejected"] | None = None,
               page=Depends(page_params), _=Admin, conn=Conn):
    select = f"SELECT * FROM (SELECT {USER_COLS}, {face_data.FACE_STATUS_SQL} AS face_status FROM users u) x"
    where, params = [], []
    if q:
        where.append("(full_name ILIKE %s OR username ILIKE %s OR email ILIKE %s OR student_code ILIKE %s)")
        params += [f"%{q.strip()}%"] * 4
    if role:
        where.append("role = %s")
        params.append(role)
    if face:
        where.append("face_status = %s")
        params.append(face)
    return paginate(conn, select, where, params, "id", page)


@router.post("/users", status_code=201)
def create_user(body: UserIn, request: Request, admin=Admin, conn=Conn):
    username, email = check_username(body.username), check_email(body.email)
    code = (body.student_code or "").strip() if body.role == "student" else None
    if code == "":
        raise invalid("student_code", "Sinh viên phải có mã sinh viên")
    check_unique(conn, username, email, code)
    temp = security.temp_password()
    uid = conn.execute(
        "INSERT INTO users (role, username, email, full_name, student_code, password_hash, must_change_password) "
        "VALUES (%s, %s, %s, %s, %s, %s, true) RETURNING id",
        (body.role, username, email, body.full_name.strip(), code, security.hash_password(temp))).fetchone()["id"]
    user = get_user(conn, uid)
    audit.log(conn, admin["id"], "user.create", f"users:{uid}", after=_public(user), ip=ip_of(request))
    return {"user": user, "temp_password": temp}


def _public(user: dict) -> dict:
    return {k: user[k] for k in ("role", "username", "email", "full_name", "student_code", "is_active")}


@router.patch("/users/{user_id}")
def update_user(user_id: int, body: UserPatch, request: Request, admin=Admin, conn=Conn):
    before = get_user(conn, user_id)
    changes = body.model_dump(exclude_unset=True)
    if "username" in changes:
        changes["username"] = check_username(changes["username"] or "")
    if "email" in changes:
        changes["email"] = check_email(changes["email"])
    if "student_code" in changes:
        if before["role"] != "student":
            raise invalid("student_code", "Chỉ sinh viên có mã sinh viên")
        changes["student_code"] = (changes["student_code"] or "").strip()
        if not changes["student_code"]:
            raise invalid("student_code", "Sinh viên phải có mã sinh viên")
    check_unique(conn, changes.get("username"), changes.get("email"), changes.get("student_code"), user_id)
    if changes:
        sets = ", ".join(f"{k} = %({k})s" for k in changes)
        conn.execute(f"UPDATE users SET {sets} WHERE id = %(id)s", {**changes, "id": user_id})
    after = get_user(conn, user_id)
    audit.log(conn, admin["id"], "user.update", f"users:{user_id}", _public(before), _public(after), ip_of(request))
    return after


@router.post("/users/{user_id}/reset-password")
def reset_password(user_id: int, request: Request, admin=Admin, conn=Conn):
    get_user(conn, user_id)
    temp = security.temp_password()
    conn.execute("UPDATE users SET password_hash = %s, must_change_password = true, "
                 "token_version = token_version + 1 WHERE id = %s", (security.hash_password(temp), user_id))
    audit.log(conn, admin["id"], "user.reset_password", f"users:{user_id}", ip=ip_of(request))
    return {"temp_password": temp}


def _not_self(admin: dict, user_id: int, what: str) -> None:
    if admin["id"] == user_id:
        raise invalid("id", f"Không thể {what} chính tài khoản đang đăng nhập")


@router.post("/users/{user_id}/deactivate")
def deactivate(user_id: int, request: Request, admin=Admin, conn=Conn):
    _not_self(admin, user_id, "vô hiệu hóa")
    get_user(conn, user_id)
    conn.execute("UPDATE users SET is_active = false, token_version = token_version + 1 WHERE id = %s", (user_id,))
    revoked = face_data.revoke_all(conn, user_id)  # mục 4.6: vô hiệu hóa thì xóa dữ liệu khuôn mặt
    audit.log(conn, admin["id"], "user.deactivate", f"users:{user_id}", after={"faces_revoked": revoked},
              ip=ip_of(request))
    return get_user(conn, user_id)


@router.post("/users/{user_id}/activate")
def activate(user_id: int, request: Request, admin=Admin, conn=Conn):
    get_user(conn, user_id)
    conn.execute("UPDATE users SET is_active = true WHERE id = %s", (user_id,))
    audit.log(conn, admin["id"], "user.activate", f"users:{user_id}", ip=ip_of(request))
    return get_user(conn, user_id)


@router.delete("/users/{user_id}", status_code=204)
def delete_user(user_id: int, request: Request, admin=Admin, conn=Conn):
    _not_self(admin, user_id, "xóa")
    before = get_user(conn, user_id)
    try:
        with conn.transaction():  # savepoint: lỗi khóa ngoại không làm hỏng transaction của request
            conn.execute("DELETE FROM users WHERE id = %s", (user_id,))
    except psycopg.errors.ForeignKeyViolation:
        raise ApiError(409, "USER_HAS_DATA", "Người dùng đã có dữ liệu, hãy vô hiệu hóa thay vì xóa")
    audit.log(conn, admin["id"], "user.delete", f"users:{user_id}", before=_public(before), ip=ip_of(request))
    return Response(status_code=204)


@router.delete("/users/{user_id}/face", status_code=204)
def delete_face(user_id: int, request: Request, admin=Admin, conn=Conn):
    get_user(conn, user_id)
    revoked = face_data.revoke_all(conn, user_id)
    audit.log(conn, admin["id"], "face.delete", f"users:{user_id}", after={"faces_revoked": revoked},
              ip=ip_of(request))
    return Response(status_code=204)


# ---------------- Lớp ----------------

class ClassIn(BaseModel):
    code: str = Field(min_length=1, max_length=50)
    name: str = Field(min_length=1, max_length=200)
    semester: str = Field(min_length=1, max_length=20)
    lecturer_id: int


class ClassPatch(BaseModel):
    code: str | None = Field(None, min_length=1, max_length=50)
    name: str | None = Field(None, min_length=1, max_length=200)
    semester: str | None = Field(None, min_length=1, max_length=20)
    lecturer_id: int | None = None


CLASS_SELECT = """SELECT c.id, c.code, c.name, c.semester, c.lecturer_id, l.full_name AS lecturer_name,
  (SELECT count(*) FROM enrollments e WHERE e.class_id = c.id) AS student_count
FROM classes c JOIN users l ON l.id = c.lecturer_id"""


def get_class(conn, class_id: int) -> dict:
    c = conn.execute(f"{CLASS_SELECT} WHERE c.id = %s", (class_id,)).fetchone()
    if not c:
        raise not_found()
    return c


def check_class(conn, data: dict, exclude_id: int = 0) -> None:
    if not conn.execute("SELECT 1 FROM users WHERE id = %s AND role = 'lecturer' AND is_active",
                        (data["lecturer_id"],)).fetchone():
        raise invalid("lecturer_id", "Không có giảng viên này")
    if conn.execute("SELECT 1 FROM classes WHERE code = %s AND semester = %s AND id <> %s",
                    (data["code"], data["semester"], exclude_id)).fetchone():
        raise invalid("code", f"Lớp đã tồn tại: {data['code']} ({data['semester']})")


def _class_public(c: dict) -> dict:
    return {k: c[k] for k in ("code", "name", "semester", "lecturer_id")}


@router.get("/classes")
def list_classes(q: str | None = None, semester: str | None = None, lecturer_id: int | None = None,
                 page=Depends(page_params), _=Admin, conn=Conn):
    where, params = [], []
    if q:
        where.append("(c.code ILIKE %s OR c.name ILIKE %s)")
        params += [f"%{q.strip()}%"] * 2
    if semester:
        where.append("c.semester = %s")
        params.append(semester)
    if lecturer_id:
        where.append("c.lecturer_id = %s")
        params.append(lecturer_id)
    return paginate(conn, CLASS_SELECT, where, params, "c.semester DESC, c.code", page)


@router.post("/classes", status_code=201)
def create_class(body: ClassIn, request: Request, admin=Admin, conn=Conn):
    data = {**body.model_dump(), "code": body.code.strip(), "semester": body.semester.strip()}
    check_class(conn, data)
    cid = conn.execute("INSERT INTO classes (code, name, semester, lecturer_id) "
                       "VALUES (%(code)s, %(name)s, %(semester)s, %(lecturer_id)s) RETURNING id", data).fetchone()["id"]
    audit.log(conn, admin["id"], "class.create", f"classes:{cid}", after=data, ip=ip_of(request))
    return get_class(conn, cid)


@router.patch("/classes/{class_id}")
def update_class(class_id: int, body: ClassPatch, request: Request, admin=Admin, conn=Conn):
    before = get_class(conn, class_id)
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    data = {**_class_public(before), **changes}
    check_class(conn, data, class_id)
    conn.execute("UPDATE classes SET code = %(code)s, name = %(name)s, semester = %(semester)s, "
                 "lecturer_id = %(lecturer_id)s WHERE id = %(id)s", {**data, "id": class_id})
    audit.log(conn, admin["id"], "class.update", f"classes:{class_id}", _class_public(before), data, ip_of(request))
    return get_class(conn, class_id)


@router.delete("/classes/{class_id}", status_code=204)
def delete_class(class_id: int, request: Request, admin=Admin, conn=Conn):
    before = get_class(conn, class_id)
    if conn.execute("SELECT 1 FROM attendance_sessions WHERE class_id = %s LIMIT 1", (class_id,)).fetchone():
        raise ApiError(409, "CLASS_HAS_SESSIONS", "Lớp đã có phiên điểm danh, không xóa được")
    conn.execute("DELETE FROM classes WHERE id = %s", (class_id,))  # enrollments xóa theo (ON DELETE CASCADE)
    audit.log(conn, admin["id"], "class.delete", f"classes:{class_id}", before=_class_public(before), ip=ip_of(request))
    return Response(status_code=204)


# ---------------- Danh sách lớp ----------------

class EnrollmentIn(BaseModel):
    class_id: int
    student_code: str = Field(min_length=1, max_length=50)


@router.get("/enrollments")
def list_enrollments(class_id: int, _=Admin, conn=Conn):
    get_class(conn, class_id)
    return conn.execute(
        f"SELECT u.id, u.full_name, u.username, u.email, u.student_code, u.is_active, {face_data.FACE_STATUS_SQL} AS face_status "
        "FROM enrollments e JOIN users u ON u.id = e.student_id WHERE e.class_id = %s ORDER BY u.student_code",
        (class_id,)).fetchall()


@router.post("/enrollments", status_code=201)
def add_enrollment(body: EnrollmentIn, request: Request, admin=Admin, conn=Conn):
    get_class(conn, body.class_id)
    s = conn.execute("SELECT id FROM users WHERE student_code = %s AND role = 'student'",
                     (body.student_code.strip(),)).fetchone()
    if not s:
        raise invalid("student_code", f"Không có sinh viên với mã: {body.student_code}")
    added = conn.execute("INSERT INTO enrollments (class_id, student_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                         (body.class_id, s["id"])).rowcount
    if added:
        audit.log(conn, admin["id"], "enrollment.add", f"enrollments:{body.class_id}:{s['id']}", ip=ip_of(request))
    return {"class_id": body.class_id, "student_id": s["id"]}


@router.delete("/enrollments/{class_id}/{student_id}", status_code=204)
def remove_enrollment(class_id: int, student_id: int, request: Request, admin=Admin, conn=Conn):
    if not conn.execute("DELETE FROM enrollments WHERE class_id = %s AND student_id = %s",
                        (class_id, student_id)).rowcount:
        raise not_found()
    audit.log(conn, admin["id"], "enrollment.remove", f"enrollments:{class_id}:{student_id}", ip=ip_of(request))
    return Response(status_code=204)


# ---------------- Nhập CSV ----------------

class ImportIn(BaseModel):
    kind: importer.Kind
    dry_run: bool = True
    csv_text: str


@router.post("/import")
def import_csv(body: ImportIn, request: Request, admin=Admin, conn=Conn):
    res = importer.run(conn, body.kind, body.csv_text, body.dry_run)
    if res["ok"] and not body.dry_run:
        audit.log(conn, admin["id"], f"import.{body.kind}", "import", after={"created": res["created"]},
                  ip=ip_of(request))
    return res


# ---------------- Nhật ký ----------------

@router.get("/audit-log")
def audit_log(actor_id: int | None = None, action: str | None = None,
              from_: datetime | None = Query(None, alias="from"), to: datetime | None = None,
              page=Depends(page_params), _=Admin, conn=Conn):
    select = ("SELECT a.id, a.actor_id, u.full_name AS actor_name, a.action, a.target, a.before, a.after, "
              "host(a.ip) AS ip, a.created_at FROM audit_log a LEFT JOIN users u ON u.id = a.actor_id")
    where, params = [], []
    for cond, val in (("a.actor_id = %s", actor_id), ("a.action = %s", action),
                      ("a.created_at >= %s", from_), ("a.created_at < %s", to)):
        if val is not None:
            where.append(cond)
            params.append(val)
    return paginate(conn, select, where, params, "a.id DESC", page)
