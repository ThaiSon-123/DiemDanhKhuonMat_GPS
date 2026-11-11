"""Phiên điểm danh: mở, phạm vi giảng viên, trạng thái mở (đặc tả mục 4.3, 6.2)."""
import secrets
from datetime import datetime
from functools import lru_cache

import psycopg

from app.config import BASE_DIR, get_settings
from app.errors import ApiError
from app.services import geo


def is_open(session: dict, now: datetime) -> bool:
    return session["closed_at"] is None and now < session["expires_at"]


def not_found() -> ApiError:
    return ApiError(404, "NOT_FOUND", "Không tìm thấy")


def class_for_lecturer(conn: psycopg.Connection, class_id: int, lecturer_id: int) -> dict:
    """Lớp do giảng viên dạy; lớp khác hoặc không có → 404 (không lộ sự tồn tại)."""
    c = conn.execute("SELECT * FROM classes WHERE id = %s AND lecturer_id = %s", (class_id, lecturer_id)).fetchone()
    if not c:
        raise not_found()
    return c


def load_session_for_lecturer(conn: psycopg.Connection, session_id: int, lecturer_id: int) -> dict:
    s = conn.execute("SELECT s.* FROM attendance_sessions s JOIN classes c ON c.id = s.class_id "
                     "WHERE s.id = %s AND c.lecturer_id = %s", (session_id, lecturer_id)).fetchone()
    if not s:
        raise not_found()
    return s


@lru_cache
def campus() -> list[tuple[float, float]]:
    return geo.load_campus(str(BASE_DIR / get_settings().campus_polygon_file))


def open_session(conn: psycopg.Connection, lecturer: dict, class_id: int, duration_min: int, base_radius_m: float,
                 room_check: bool, samples: list[geo.Sample]) -> dict:
    cfg = get_settings().gps
    class_for_lecturer(conn, class_id, lecturer["id"])
    fix = geo.aggregate(samples, cfg.max_acc_lecturer_m, cfg.min_samples_lecturer, cfg.max_span_s)
    if fix is None:
        raise ApiError(422, "GPS_ACCURACY_LOW",
                       f"Chưa đủ {cfg.min_samples_lecturer} mẫu GPS có độ chính xác ≤ {cfg.max_acc_lecturer_m:.0f} m. "
                       "Hãy đứng yên, bật Wi-Fi hoặc ra gần cửa sổ.")
    if not geo.in_polygon(fix.lat, fix.lng, campus()):
        raise ApiError(422, "OUTSIDE_CAMPUS", "Vị trí của bạn nằm ngoài khuôn viên trường")

    # Phiên quá hạn mà chưa đóng tay thì đóng tại thời điểm hết hạn, để không chặn phiên mới.
    conn.execute("UPDATE attendance_sessions SET closed_at = expires_at "
                 "WHERE class_id = %s AND closed_at IS NULL AND expires_at <= now()", (class_id,))
    try:
        with conn.transaction():
            s = conn.execute(
                "INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, "
                "base_radius_m, room_check, room_secret, expires_at) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now() + make_interval(mins => %s)) RETURNING *",
                (class_id, lecturer["id"], fix.lat, fix.lng, fix.acc, base_radius_m, room_check,
                 secrets.token_bytes(32), duration_min)).fetchone()
    except psycopg.errors.UniqueViolation:  # one_open_session: lớp đang có phiên mở
        raise ApiError(409, "SESSION_ALREADY_OPEN", "Lớp đang có một phiên điểm danh mở")
    # Tạo sẵn "vắng" cho cả lớp: danh sách thời gian thực đủ người, báo cáo không phải suy ra người vắng.
    conn.execute("INSERT INTO attendance_records (session_id, student_id, status) "
                 "SELECT %s, student_id, 'absent' FROM enrollments WHERE class_id = %s", (s["id"], class_id))
    return s
