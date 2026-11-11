"""Mở / đóng phiên, mã phòng, lịch sử phiên của lớp (đặc tả mục 4.3, 7.2, 9.3)."""
import time
from datetime import datetime, timezone

import psycopg
from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from pydantic import BaseModel, Field, ValidationError

from app.config import get_settings
from app.db import get_conn
from app.errors import ApiError
from app.security import require_role
from app.services import checkin as ck
from app.services import geo, room_token
from app.services import sessions as svc
from app.services.checkin import SampleIn
from app.services.face.runtime import get_engine
from app.services.face.types import FaceEngine

router = APIRouter(tags=["sessions"])
Lecturer = Depends(require_role("lecturer"))


class OpenSessionIn(BaseModel):
    class_id: int
    duration_min: int | None = Field(None, ge=1, le=60)
    base_radius_m: float | None = None
    room_check: bool = False
    gps_samples: list[SampleIn] = Field(max_length=200)


def _center(s: dict) -> dict:
    return {"lat": s["center_lat"], "lng": s["center_lng"], "accuracy_m": s["center_accuracy_m"]}


@router.post("/sessions", status_code=201)
def open_session(body: OpenSessionIn, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    cfg = get_settings()
    r0 = cfg.gps.default_r0_m if body.base_radius_m is None else body.base_radius_m
    lo, hi = cfg.gps.r0_range_m
    if not lo <= r0 <= hi:
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ",
                       [{"field": "base_radius_m", "msg": f"Bán kính cơ sở phải trong {lo:.0f}–{hi:.0f} m"}])
    s = svc.open_session(conn, user, body.class_id, body.duration_min or cfg.session.default_duration_min, r0,
                         body.room_check, [geo.Sample(x.lat, x.lng, x.acc, x.ts, x.mock) for x in body.gps_samples])
    return {"session_id": s["id"], "center": _center(s), "expires_at": s["expires_at"], "room_check": s["room_check"]}


@router.post("/sessions/{session_id}/close")
def close_session(session_id: int, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    svc.load_session_for_lecturer(conn, session_id, user["id"])
    # Đã đóng (tay hoặc hết hạn) thì giữ nguyên thời điểm đóng cũ.
    s = conn.execute("UPDATE attendance_sessions SET closed_at = COALESCE(closed_at, LEAST(now(), expires_at)) "
                     "WHERE id = %s RETURNING *", (session_id,)).fetchone()
    return {"session_id": s["id"], "closed_at": s["closed_at"], "is_open": False}


@router.get("/sessions/{session_id}/room-token")
def get_room_token(session_id: int, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    s = svc.load_session_for_lecturer(conn, session_id, user["id"])
    if not s["room_check"]:
        raise ApiError(409, "ROOM_CHECK_DISABLED", "Phiên này không bật mã phòng")
    if not svc.is_open(s, datetime.now(timezone.utc)):
        raise ApiError(409, "SESSION_CLOSED", "Phiên điểm danh đã đóng")
    window = get_settings().session.room_token_window_s
    now = time.time()
    code = room_token.room_code(bytes(s["room_secret"]), s["id"], now, window)
    return {"code": code,
            "window_ends_at": datetime.fromtimestamp(room_token.window_end(now, window), timezone.utc),
            "qr_payload": f"dd:{s['id']}:{code}"}


@router.get("/classes/{class_id}/sessions")
def class_sessions(class_id: int, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    svc.class_for_lecturer(conn, class_id, user["id"])
    rows = conn.execute(
        """SELECT s.id, s.opened_at, s.expires_at, s.closed_at, s.room_check, s.base_radius_m,
                  (s.closed_at IS NULL AND now() < s.expires_at) AS is_open,
                  count(*) FILTER (WHERE r.status IN ('present', 'manual_present')) AS present,
                  count(*) FILTER (WHERE r.status = 'suspicious') AS suspicious,
                  count(*) FILTER (WHERE r.status = 'absent') AS absent,
                  count(*) FILTER (WHERE r.status = 'excused') AS excused,
                  count(*) FILTER (WHERE r.status = 'rejected') AS rejected,
                  count(r.student_id) AS total
           FROM attendance_sessions s LEFT JOIN attendance_records r ON r.session_id = s.id
           WHERE s.class_id = %s GROUP BY s.id ORDER BY s.opened_at DESC""", (class_id,)).fetchall()
    keys = ("present", "suspicious", "absent", "excused", "rejected", "total")
    return [{**{k: v for k, v in r.items() if k not in keys}, "counts": {k: r[k] for k in keys}} for r in rows]


# ---- Điểm danh (sinh viên) ----

Student = Depends(require_role("student"))
MIN_FRAMES, MAX_FRAMES = 5, 8


@router.post("/sessions/{session_id}/challenge")
def challenge(session_id: int, user=Student, conn: psycopg.Connection = Depends(get_conn)):
    return ck.issue_challenge(conn, session_id, user, ck.now_utc())


@router.post("/sessions/{session_id}/checkin")
def checkin(session_id: int, request: Request, frames: list[UploadFile] = File(...), meta: str = Form(...),
            user=Student, engine: FaceEngine = Depends(get_engine), conn: psycopg.Connection = Depends(get_conn)):
    try:
        m = ck.CheckinMeta.model_validate_json(meta)
    except ValidationError as e:
        details = [{"field": "meta." + ".".join(str(p) for p in err["loc"]), "msg": err["msg"]} for err in e.errors()]
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ", details)
    if not MIN_FRAMES <= len(frames) <= MAX_FRAMES:
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ",
                       [{"field": "frames", "msg": f"Cần từ {MIN_FRAMES} đến {MAX_FRAMES} khung hình"}])
    data = [f.file.read() for f in frames]
    ip = request.client.host if request.client else None
    return ck.process_checkin(conn, session_id, user, data, m, ip, engine, ck.now_utc())
