"""Thử thách và điểm danh 6 bước (đặc tả mục 4.4, 6, 7, 9.2, 9.5)."""
import ipaddress
import secrets
import time
from datetime import datetime, timezone

import psycopg
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field

from app import crypto
from app.config import get_settings
from app.errors import ApiError
from app.face_data import approved_template, face_state
from app.services import geo, room_token
from app.services.face.runtime import infer
from app.services.face.types import FaceEngine, FaceResult
from app.services.face.verify import verify_checkin
from app.services.sessions import is_open, not_found

QUALITY_REASONS = {"FACE_NOT_FOUND", "MULTIPLE_FACES", "LOW_LIGHT", "BLURRY"}
MESSAGES = {
    "ROOM_TOKEN_INVALID": "Mã phòng không đúng hoặc đã hết hạn, hãy quét lại",
    "GPS_ACCURACY_LOW": "GPS chưa đủ chính xác, hãy bật Wi-Fi và thử lại gần cửa sổ",
    "GPS_TOO_FAR": "Bạn đang ở xa vị trí lớp học",
    "FACE_NOT_FOUND": "Không thấy khuôn mặt trong khung hình",
    "MULTIPLE_FACES": "Chỉ một người trong khung hình",
    "LOW_LIGHT": "Thiếu sáng",
    "BLURRY": "Ảnh bị mờ, hãy giữ máy chắc tay",
    "SPOOF_DETECTED": "Không xác nhận được người thật",
    "FACE_MISMATCH": "Khuôn mặt không khớp với tài khoản",
    "FACE_NOT_ENROLLED": "Bạn chưa có mẫu khuôn mặt hợp lệ",
}
ACTION_TEXT = {"turn_left": "quay đầu sang trái", "turn_right": "quay đầu sang phải"}
BURST_WINDOW_S, BURST_COUNT = 10, 3


class SampleIn(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    acc: float = Field(gt=0, allow_inf_nan=False)
    ts: int
    mock: bool = False


class CheckinMeta(BaseModel):
    nonce: str = Field(min_length=1, max_length=200)
    device_id: str = Field(min_length=1, max_length=100)
    room_token: str | None = Field(None, max_length=50)
    gps_samples: list[SampleIn] = Field(min_length=1, max_length=100)


def _ip(ip: str | None) -> str | None:
    try:
        return str(ipaddress.ip_address(ip)) if ip else None
    except ValueError:
        return None


def _session_for_student(conn, session_id: int, student_id: int) -> dict:
    s = conn.execute("SELECT s.* FROM attendance_sessions s JOIN enrollments e ON e.class_id = s.class_id "
                     "WHERE s.id = %s AND e.student_id = %s", (session_id, student_id)).fetchone()
    if not s:
        raise not_found()
    return s


def _attempts_used(conn, session_id: int, student_id: int) -> int:
    return conn.execute("SELECT count(*) c FROM challenges WHERE session_id = %s AND student_id = %s",
                        (session_id, student_id)).fetchone()["c"]


def _closed() -> ApiError:
    return ApiError(409, "SESSION_CLOSED", "Phiên điểm danh đã đóng hoặc hết hạn")


def issue_challenge(conn: psycopg.Connection, session_id: int, student: dict, now: datetime) -> dict:
    """Mỗi thử thách là một lượt, kể cả khi không gửi lên (chống xin liên tục để chọn hành động dễ)."""
    cfg = get_settings()
    s = _session_for_student(conn, session_id, student["id"])
    if not is_open(s, now):
        raise _closed()
    if approved_template(conn, student["id"], cfg.face.model_name) is None:
        state = face_state(conn, student["id"], cfg.face.model_name)
        details = {"reason": "model_outdated"} if state["model_ok"] is False else {}
        raise ApiError(409, "FACE_NOT_ENROLLED", "Bạn cần đăng ký khuôn mặt và được duyệt trước khi điểm danh", details)
    rec = conn.execute("SELECT status FROM attendance_records WHERE session_id = %s AND student_id = %s",
                       (session_id, student["id"])).fetchone()
    if rec and rec["status"] in ("present", "manual_present"):
        raise ApiError(409, "ALREADY_PRESENT", "Bạn đã được ghi nhận có mặt")
    # ponytail: đếm rồi insert không khóa; hai request xin thử thách cùng lúc có thể vượt 5 một lượt.
    used = _attempts_used(conn, session_id, student["id"])
    if used >= cfg.session.max_attempts:
        raise ApiError(429, "ATTEMPTS_EXHAUSTED", "Bạn đã dùng hết lượt điểm danh của phiên này")
    action = secrets.choice(cfg.face.actions)
    c = conn.execute("INSERT INTO challenges (session_id, student_id, nonce, action, expires_at) "
                     "VALUES (%s, %s, %s, %s, now() + make_interval(secs => %s)) RETURNING nonce, action, expires_at",
                     (session_id, student["id"], secrets.token_urlsafe(32), action, cfg.session.challenge_ttl_s)).fetchone()
    return {**c, "attempts_left": cfg.session.max_attempts - used - 1, "room_check": s["room_check"]}


def collect_flags(face: FaceResult, loc: str, samples: list[geo.Sample], jump_prev: bool, shared_device: bool,
                  token_burst: bool) -> list[str]:
    """Cờ của một lượt đã qua đủ 6 bước; kết quả "có mặt" khi và chỉ khi danh sách rỗng."""
    flags = []
    if loc == "drift":
        flags.append("LOCATION_DRIFT")
    if face.status == "borderline":
        flags.append("FACE_BORDERLINE")
    if any(s.mock for s in samples):
        flags.append("MOCK_LOCATION")
    if jump_prev or geo.has_jump(samples, get_settings().gps.max_speed_mps):
        flags.append("LOCATION_JUMP")
    if shared_device:
        flags.append("SHARED_DEVICE")
    if token_burst:
        flags.append("ROOM_TOKEN_BURST")
    return flags


def process_checkin(conn: psycopg.Connection, session_id: int, student: dict, frames: list[bytes], meta: CheckinMeta,
                    ip: str | None, engine: FaceEngine, now: datetime) -> dict:
    cfg = get_settings()
    uid = student["id"]
    ip = _ip(ip)

    # Bước 1: phiên còn mở theo giờ server, sinh viên thuộc lớp. Dừng ở bước 1–2 thì không ghi lượt.
    s = _session_for_student(conn, session_id, uid)
    if not is_open(s, now):
        raise _closed()
    # Bước 2: đánh dấu nonce đã dùng. Câu UPDATE khóa dòng: request song song cùng nonce phải chờ và nhận 0 dòng.
    ch = conn.execute("UPDATE challenges SET used_at = now() WHERE nonce = %s AND student_id = %s AND session_id = %s "
                      "AND used_at IS NULL AND expires_at > now() RETURNING id, action",
                      (meta.nonce, uid, session_id)).fetchone()
    if not ch:
        raise ApiError(409, "CHALLENGE_INVALID", "Thử thách không hợp lệ hoặc đã hết hạn, hãy bắt đầu lại")

    samples = [geo.Sample(x.lat, x.lng, x.acc, x.ts, x.mock) for x in meta.gps_samples]
    att = {"session_id": session_id, "student_id": uid, "challenge_id": ch["id"], "device_id": meta.device_id, "ip": ip,
           "gps_samples": Jsonb([x.model_dump() for x in meta.gps_samples]), "lat": None, "lng": None,
           "accuracy_m": None, "distance_m": None, "radius_m": None, "room_token_ok": None, "face_score": None,
           "liveness_score": None, "action_ok": None, "result": "fail", "fail_step": None, "fail_reason": None,
           "flags": Jsonb([]), "evidence_path": None, "evidence_expires_at": None}

    def finish(step: int | None, reason: str | None, message: str | None = None) -> dict:
        att["fail_step"], att["fail_reason"] = step, reason
        cols = ", ".join(att)
        aid = conn.execute(f"INSERT INTO checkin_attempts ({cols}) VALUES ({', '.join('%(' + k + ')s' for k in att)}) "
                           "RETURNING id", att).fetchone()["id"]
        if att["result"] in ("pass", "suspicious"):
            if att["result"] == "suspicious" and best_frame is not None:
                rel = crypto.save_blob(f"evidence/{aid}.jpg", frames[best_frame])
                conn.execute("UPDATE checkin_attempts SET evidence_path = %s, "
                             "evidence_expires_at = received_at + make_interval(days => %s) WHERE id = %s",
                             (rel, cfg.retention.evidence_days, aid))
            # Chỉ nâng hạng; giảng viên đã quyết định tay thì không ghi đè (mục 9.2).
            conn.execute(
                """INSERT INTO attendance_records (session_id, student_id, status, best_attempt_id)
                   VALUES (%s, %s, %s, %s)
                   ON CONFLICT (session_id, student_id) DO UPDATE
                   SET status = EXCLUDED.status, best_attempt_id = EXCLUDED.best_attempt_id, updated_at = now()
                   WHERE attendance_records.decided_by IS NULL
                     AND (CASE attendance_records.status WHEN 'absent' THEN 0 WHEN 'suspicious' THEN 1
                          WHEN 'present' THEN 2 ELSE 3 END)
                       < (CASE EXCLUDED.status WHEN 'suspicious' THEN 1 WHEN 'present' THEN 2 END)""",
                (session_id, uid, "present" if att["result"] == "pass" else "suspicious", aid))
        rec = conn.execute("SELECT status FROM attendance_records WHERE session_id = %s AND student_id = %s",
                           (session_id, uid)).fetchone()
        return {"result": att["result"], "record_status": rec["status"] if rec else "absent",
                "reason": None if reason is None else {"code": reason, "message": message or MESSAGES[reason]},
                "attempts_left": max(cfg.session.max_attempts - _attempts_used(conn, session_id, uid), 0)}

    best_frame = None
    # Bước 3: mã phòng (khi phiên bật).
    if s["room_check"]:
        ok = room_token.verify_room_code(meta.room_token, bytes(s["room_secret"]), session_id, time.time(),
                                         cfg.session.room_token_window_s)
        att["room_token_ok"] = ok
        if not ok:
            return finish(3, "ROOM_TOKEN_INVALID")

    # Bước 4: vị trí. Xa quá 2r thì dừng, không chạy mô hình.
    fix = geo.aggregate(samples, cfg.gps.max_acc_student_m, cfg.gps.min_samples_student, cfg.gps.max_span_s)
    if fix is None:
        return finish(4, "GPS_ACCURACY_LOW")
    r = geo.adaptive_radius(s["base_radius_m"], s["center_accuracy_m"], fix.acc)
    d = geo.haversine_m(s["center_lat"], s["center_lng"], fix.lat, fix.lng)
    att.update(lat=fix.lat, lng=fix.lng, accuracy_m=fix.acc, distance_m=d, radius_m=r)
    loc = geo.classify(d, r)
    if loc == "far":
        return finish(4, "GPS_TOO_FAR")

    # Bước 5–6: liveness và so khớp.
    template = approved_template(conn, uid, cfg.face.model_name)
    if template is None:
        return finish(6, "FACE_NOT_ENROLLED")
    face = infer(verify_checkin, frames, ch["action"], template, engine, cfg.face)
    best_frame = face.best_frame
    att.update(face_score=face.face_score, liveness_score=face.liveness_score, action_ok=face.action_ok)
    if face.status == "fail":
        step = 6 if face.reason == "FACE_MISMATCH" else 5
        message = f"Chưa thấy bạn {ACTION_TEXT.get(ch['action'], 'làm hành động')}" \
            if face.reason == "ACTION_NOT_DETECTED" else None
        return finish(step, face.reason, message)

    prev = conn.execute("SELECT lat, lng, accuracy_m, received_at FROM checkin_attempts WHERE session_id = %s "
                        "AND student_id = %s AND lat IS NOT NULL ORDER BY id DESC LIMIT 1", (session_id, uid)).fetchone()
    jump_prev = prev is not None and geo.jump_from_previous(
        geo.Fix(prev["lat"], prev["lng"], prev["accuracy_m"]), prev["received_at"].timestamp(), fix, now.timestamp(),
        cfg.gps.max_speed_mps)
    shared = conn.execute("SELECT 1 FROM checkin_attempts WHERE session_id = %s AND device_id = %s "
                          "AND student_id <> %s LIMIT 1", (session_id, meta.device_id, uid)).fetchone() is not None
    # ponytail: không lưu chuỗi mã phòng; đếm lượt có mã đúng cùng IP trong 10 s (mã đổi 30 s nên gần như cùng mã).
    burst = bool(s["room_check"] and ip) and conn.execute(
        "SELECT count(*) c FROM checkin_attempts WHERE session_id = %s AND ip = %s AND room_token_ok "
        "AND received_at > now() - make_interval(secs => %s)", (session_id, ip, BURST_WINDOW_S)).fetchone()["c"] \
        >= BURST_COUNT - 1
    flags = collect_flags(face, loc, samples, jump_prev, shared, burst)
    att["flags"] = Jsonb(flags)
    att["result"] = "suspicious" if flags else "pass"
    return finish(None, None)


def now_utc() -> datetime:
    return datetime.now(timezone.utc)
