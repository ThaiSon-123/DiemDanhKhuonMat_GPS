"""Đơn xin nghỉ (leave) và khiếu nại kết quả (appeal) cho một buổi đã diễn ra.

Sinh viên gửi khi buổi đó đang ghi "vắng" hoặc "bị từ chối", trong hạn `attendance.request_days` ngày.
Giảng viên lớp đó duyệt: đơn xin nghỉ → "vắng có phép" (excused), khiếu nại → "có mặt" (manual_present);
kết quả được khóa như duyệt tay (decided_by) và ghi nhật ký trước / sau.
"""
from datetime import datetime, timedelta, timezone
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app import audit, crypto
from app.config import get_settings
from app.db import get_conn
from app.errors import ApiError
from app.security import require_role
from app.services import sessions as svc

router = APIRouter(tags=["requests"])
Student = Depends(require_role("student"))
Lecturer = Depends(require_role("lecturer"))

RESULT = {"leave": "excused", "appeal": "manual_present"}
TYPES = {"image/jpeg": "jpg", "image/png": "png"}

_COLS = """r.id, r.kind, r.session_id, r.reason, r.status, r.decision_note, r.created_at, r.decided_at,
  (r.attachment_path IS NOT NULL) AS has_attachment, s.opened_at, c.id AS class_id, c.code AS class_code,
  c.name AS class_name"""


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _bad(field: str, msg: str) -> ApiError:
    return ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ", [{"field": field, "msg": msg}])


@router.post("/me/requests", status_code=201)
def create_request(request: Request, kind: Literal["leave", "appeal"] = Form(...), session_id: int = Form(...),
                   reason: str = Form(...), attachment: UploadFile | None = File(None), user=Student,
                   conn: psycopg.Connection = Depends(get_conn)):
    cfg = get_settings().attendance
    reason = reason.strip()
    if not 5 <= len(reason) <= 1000:
        raise _bad("reason", "Lý do cần từ 5 đến 1000 ký tự")
    row = conn.execute("SELECT r.status, s.* FROM attendance_records r JOIN attendance_sessions s ON s.id = r.session_id "
                       "WHERE r.session_id = %s AND r.student_id = %s", (session_id, user["id"])).fetchone()
    if not row:
        raise svc.not_found()
    now = datetime.now(timezone.utc)
    if svc.is_open(row, now):
        raise ApiError(409, "SESSION_STILL_OPEN", "Phiên vẫn đang mở, hãy điểm danh trước")
    if now - row["opened_at"] > timedelta(days=cfg.request_days):
        raise ApiError(409, "REQUEST_TOO_LATE", f"Chỉ gửi được trong {cfg.request_days} ngày sau buổi học")
    if row["status"] not in ("absent", "rejected"):
        raise ApiError(409, "REQUEST_NOT_ALLOWED", "Buổi này không ghi vắng nên không cần gửi đơn")

    data, ext = None, None
    if attachment is not None and attachment.filename:
        ext = TYPES.get(attachment.content_type or "")
        if ext is None:
            raise _bad("attachment", "Ảnh giấy tờ phải là JPEG hoặc PNG")
        data = attachment.file.read(int(cfg.attachment_max_mb * 1024 * 1024) + 1)
        if len(data) > cfg.attachment_max_mb * 1024 * 1024:
            raise _bad("attachment", f"Ảnh giấy tờ tối đa {cfg.attachment_max_mb:g} MB")
    try:
        with conn.transaction():
            rid = conn.execute("INSERT INTO requests (kind, session_id, student_id, reason) VALUES (%s, %s, %s, %s) "
                               "RETURNING id", (kind, session_id, user["id"], reason)).fetchone()["id"]
    except psycopg.errors.UniqueViolation:
        raise ApiError(409, "REQUEST_PENDING_EXISTS", "Bạn đã có một đơn đang chờ cho buổi này")
    if data is not None:
        rel = crypto.save_blob(f"requests/{rid}.{ext}", data)
        conn.execute("UPDATE requests SET attachment_path = %s WHERE id = %s", (rel, rid))
    audit.log(conn, user["id"], f"request.{kind}", f"requests:{rid}", after={"session_id": session_id}, ip=_ip(request))
    return _one(conn, rid)


def _one(conn: psycopg.Connection, rid: int) -> dict:
    return conn.execute(f"SELECT {_COLS} FROM requests r JOIN attendance_sessions s ON s.id = r.session_id "
                        "JOIN classes c ON c.id = s.class_id WHERE r.id = %s", (rid,)).fetchone()


@router.get("/me/requests")
def my_requests(user=Student, conn: psycopg.Connection = Depends(get_conn)):
    return conn.execute(f"SELECT {_COLS} FROM requests r JOIN attendance_sessions s ON s.id = r.session_id "
                        "JOIN classes c ON c.id = s.class_id WHERE r.student_id = %s ORDER BY r.id DESC",
                        (user["id"],)).fetchall()


@router.get("/requests")
def lecturer_requests(status: Literal["pending", "all"] = "pending", user=Lecturer,
                      conn: psycopg.Connection = Depends(get_conn)):
    return conn.execute(
        f"""SELECT {_COLS}, u.id AS student_id, u.full_name, u.student_code, rec.status AS record_status
            FROM requests r JOIN attendance_sessions s ON s.id = r.session_id JOIN classes c ON c.id = s.class_id
            JOIN users u ON u.id = r.student_id
            JOIN attendance_records rec ON rec.session_id = r.session_id AND rec.student_id = r.student_id
            WHERE c.lecturer_id = %s AND (%s = 'all' OR r.status = 'pending')
            ORDER BY (r.status = 'pending') DESC, r.id DESC LIMIT 200""", (user["id"], status)).fetchall()


def _for_lecturer(conn: psycopg.Connection, rid: int, lecturer_id: int) -> dict:
    r = conn.execute("SELECT r.* FROM requests r JOIN attendance_sessions s ON s.id = r.session_id "
                     "JOIN classes c ON c.id = s.class_id WHERE r.id = %s AND c.lecturer_id = %s",
                     (rid, lecturer_id)).fetchone()
    if not r:
        raise svc.not_found()
    return r


@router.get("/requests/{rid}/attachment")
def attachment(rid: int, request: Request, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    r = _for_lecturer(conn, rid, user["id"])
    if not r["attachment_path"]:
        raise svc.not_found()
    data = crypto.load_blob(r["attachment_path"])
    audit.log(conn, user["id"], "request.attachment.view", f"requests:{rid}", ip=_ip(request))
    media = "image/png" if r["attachment_path"].endswith(".png") else "image/jpeg"
    return Response(data, media_type=media, headers={"Cache-Control": "no-store"})


class DecideIn(BaseModel):
    decision: Literal["approve", "reject"]
    note: str | None = Field(None, max_length=500)


@router.post("/requests/{rid}/decide")
def decide(rid: int, body: DecideIn, request: Request, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    r = _for_lecturer(conn, rid, user["id"])
    if r["status"] != "pending":
        raise ApiError(409, "REQUEST_DECIDED", "Đơn này đã được xử lý")
    note = (body.note or "").strip() or None
    if body.decision == "reject" and not note:
        raise _bad("note", "Từ chối thì cần ghi lý do cho sinh viên")
    ip = _ip(request)
    with conn.transaction():
        conn.execute("UPDATE requests SET status = %s, decided_by = %s, decided_at = now(), decision_note = %s "
                     "WHERE id = %s", ("approved" if body.decision == "approve" else "rejected", user["id"], note, rid))
        if body.decision == "approve":
            before = conn.execute("SELECT status, note FROM attendance_records WHERE session_id = %s AND student_id = %s",
                                  (r["session_id"], r["student_id"])).fetchone()
            label = "Đơn xin nghỉ" if r["kind"] == "leave" else "Khiếu nại"
            rec_note = f"{label} #{rid} được duyệt" + (f": {note}" if note else "")
            conn.execute("UPDATE attendance_records SET status = %s, note = %s, decided_by = %s, updated_at = now() "
                         "WHERE session_id = %s AND student_id = %s",
                         (RESULT[r["kind"]], rec_note, user["id"], r["session_id"], r["student_id"]))
            audit.log(conn, user["id"], "record.update", f"attendance_records:{r['session_id']}:{r['student_id']}",
                      dict(before), {"status": RESULT[r["kind"]], "note": rec_note}, ip)
        audit.log(conn, user["id"], "request.decide", f"requests:{rid}", {"status": "pending"},
                  {"status": body.decision, "note": note}, ip)
    return _one(conn, rid)
