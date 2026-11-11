"""Tài khoản của tôi: thông tin, đồng ý dữ liệu, lớp của tôi (đặc tả mục 4.2, 8, 9.5)."""
import psycopg
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.config import get_settings
from app.db import get_conn
from app.errors import ApiError
from app.face_data import face_state
from app.security import require_role, token_user

router = APIRouter(tags=["me"])


def consent_state(conn: psycopg.Connection, user_id: int) -> dict:
    version = get_settings().consent.current_version
    accepted = conn.execute("SELECT 1 FROM consents WHERE user_id = %s AND version = %s AND revoked_at IS NULL",
                            (user_id, version)).fetchone() is not None
    return {"current_version": version, "accepted": accepted}


@router.get("/me")
def me(user: dict = Depends(token_user), conn: psycopg.Connection = Depends(get_conn)):
    # Dùng token_user: người phải đổi mật khẩu vẫn gọi được để app biết chuyển màn.
    body = {k: user[k] for k in ("id", "role", "username", "full_name", "email", "student_code", "must_change_password")}
    student = user["role"] == "student"
    body["consent"] = consent_state(conn, user["id"]) if student else None
    body["face"] = face_state(conn, user["id"], get_settings().face.model_name) if student else None
    return body


class ConsentIn(BaseModel):
    version: str


@router.post("/me/consent")
def accept_consent(body: ConsentIn, user: dict = Depends(require_role("student")),
                   conn: psycopg.Connection = Depends(get_conn)):
    current = get_settings().consent.current_version
    if body.version != current:
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ",
                       [{"field": "version", "msg": f"Phiên bản văn bản hiện hành là {current}"}])
    # Đồng ý lại sau khi đã rút: ghi thời điểm mới, xóa revoked_at.
    conn.execute("INSERT INTO consents (user_id, version) VALUES (%s, %s) "
                 "ON CONFLICT (user_id, version) DO UPDATE SET accepted_at = now(), revoked_at = NULL "
                 "WHERE consents.revoked_at IS NOT NULL", (user["id"], current))
    return consent_state(conn, user["id"])


_OPEN_SESSION = """(SELECT json_build_object('id', s.id, 'expires_at', s.expires_at, 'room_check', s.room_check)
  FROM attendance_sessions s
  WHERE s.class_id = c.id AND s.closed_at IS NULL AND s.expires_at > now()) AS open_session"""


@router.get("/me/classes")
def my_classes(user: dict = Depends(require_role("student", "lecturer")),
               conn: psycopg.Connection = Depends(get_conn)):
    if user["role"] == "student":
        sql = (f"SELECT c.id, c.code, c.name, c.semester, l.full_name AS lecturer_name, {_OPEN_SESSION} "
               "FROM enrollments e JOIN classes c ON c.id = e.class_id JOIN users l ON l.id = c.lecturer_id "
               "WHERE e.student_id = %s")
    else:
        sql = (f"SELECT c.id, c.code, c.name, c.semester, "
               f"(SELECT count(*) FROM enrollments e WHERE e.class_id = c.id) AS student_count, {_OPEN_SESSION} "
               "FROM classes c WHERE c.lecturer_id = %s")
    return conn.execute(sql + " ORDER BY c.semester DESC, c.code", (user["id"],)).fetchall()


@router.get("/me/attendance")
def my_attendance(user: dict = Depends(require_role("student")), conn: psycopg.Connection = Depends(get_conn)):
    """Mọi buổi của mọi lớp mình học, mới nhất trước. Không trả điểm số (sinh viên không bao giờ thấy)."""
    return conn.execute(
        "SELECT r.session_id, c.id AS class_id, c.code AS class_code, c.name AS class_name, s.opened_at, r.status, "
        "a.received_at AS checked_at FROM attendance_records r JOIN attendance_sessions s ON s.id = r.session_id "
        "JOIN classes c ON c.id = s.class_id LEFT JOIN checkin_attempts a ON a.id = r.best_attempt_id "
        "WHERE r.student_id = %s ORDER BY s.opened_at DESC",
        (user["id"],)).fetchall()
