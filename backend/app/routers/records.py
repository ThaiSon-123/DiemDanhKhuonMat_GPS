"""Theo dõi phiên, duyệt tay, tính lại tâm, ảnh bằng chứng (đặc tả mục 4.5, 9.5)."""
from datetime import datetime, timezone
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field

from app import audit, crypto
from app.config import get_settings
from app.db import get_conn
from app.errors import ApiError
from app.security import require_role
from app.services import geo
from app.services import sessions as svc

router = APIRouter(tags=["records"])
Lecturer = Depends(require_role("lecturer"))
STATUSES = ("absent", "suspicious", "present", "manual_present", "excused", "rejected")

_ATTEMPT_COLS = """a.id, a.result, a.received_at, a.face_score, a.distance_m, a.radius_m, a.accuracy_m, a.flags,
  a.fail_step, a.fail_reason, a.room_token_ok, a.liveness_score, a.action_ok,
  (a.evidence_path IS NOT NULL AND a.evidence_expires_at > now()) AS has_evidence"""


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _passed_face_positions(conn: psycopg.Connection, session_id: int) -> list[tuple[float, float]]:
    """Vị trí lượt mới nhất đã qua khuôn mặt (điểm ≥ ngưỡng chấp nhận) của mỗi sinh viên."""
    rows = conn.execute(
        "SELECT DISTINCT ON (student_id) lat, lng FROM checkin_attempts WHERE session_id = %s AND lat IS NOT NULL "
        "AND face_score >= %s ORDER BY student_id, id DESC",
        (session_id, get_settings().face.accept_threshold)).fetchall()
    return [(r["lat"], r["lng"]) for r in rows]


def _session_info(conn: psycopg.Connection, s: dict) -> dict:
    c = conn.execute("SELECT id, code, name, semester FROM classes WHERE id = %s", (s["class_id"],)).fetchone()
    center = (s["center_lat"], s["center_lng"])
    return {"id": s["id"], "class_id": s["class_id"], "class": c, "opened_at": s["opened_at"],
            "expires_at": s["expires_at"], "closed_at": s["closed_at"],
            "is_open": svc.is_open(s, datetime.now(timezone.utc)), "room_check": s["room_check"],
            "base_radius_m": s["base_radius_m"], "center": {"lat": center[0], "lng": center[1]},
            "recentered": s["orig_center_lat"] is not None,
            "recenter_suggested": geo.suggest_recenter(center, _passed_face_positions(conn, s["id"]),
                                                       s["base_radius_m"])}


@router.get("/sessions/{session_id}/records")
def records(session_id: int, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    s = svc.load_session_for_lecturer(conn, session_id, user["id"])
    rows = conn.execute(
        f"""SELECT r.student_id, u.student_code, u.full_name, r.status, r.decided_by, r.note,
                   (SELECT count(*) FROM checkin_attempts x WHERE x.session_id = r.session_id
                      AND x.student_id = r.student_id) AS attempt_count,
                   (SELECT row_to_json(t) FROM (SELECT {_ATTEMPT_COLS} FROM checkin_attempts a
                      WHERE a.session_id = r.session_id AND a.student_id = r.student_id
                      ORDER BY a.id DESC LIMIT 1) t) AS last_attempt
            FROM attendance_records r JOIN users u ON u.id = r.student_id
            WHERE r.session_id = %s ORDER BY u.student_code""", (session_id,)).fetchall()
    counts = dict.fromkeys(STATUSES, 0)
    for r in rows:
        counts[r["status"]] += 1
    return {"session": _session_info(conn, s), "counts": counts, "records": rows}


def _record(conn: psycopg.Connection, session_id: int, student_id: int) -> dict:
    r = conn.execute("SELECT r.*, u.student_code, u.full_name FROM attendance_records r "
                     "JOIN users u ON u.id = r.student_id WHERE r.session_id = %s AND r.student_id = %s",
                     (session_id, student_id)).fetchone()
    if not r:
        raise svc.not_found()
    return r


@router.get("/sessions/{session_id}/records/{student_id}")
def record_detail(session_id: int, student_id: int, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    s = svc.load_session_for_lecturer(conn, session_id, user["id"])
    r = _record(conn, session_id, student_id)
    attempts = conn.execute(f"SELECT {_ATTEMPT_COLS} FROM checkin_attempts a WHERE a.session_id = %s "
                            "AND a.student_id = %s ORDER BY a.id DESC", (session_id, student_id)).fetchall()
    return {"session": {"id": s["id"], "is_open": svc.is_open(s, datetime.now(timezone.utc))},
            "record": {k: r[k] for k in ("student_id", "student_code", "full_name", "status", "decided_by", "note",
                                         "updated_at")},
            "attempts": attempts}


class RecordPatch(BaseModel):
    status: Literal["manual_present", "absent", "excused", "rejected"]
    note: str | None = Field(None, max_length=500)


@router.patch("/sessions/{session_id}/records/{student_id}")
def patch_record(session_id: int, student_id: int, body: RecordPatch, request: Request, user=Lecturer,
                 conn: psycopg.Connection = Depends(get_conn)):
    svc.load_session_for_lecturer(conn, session_id, user["id"])  # đóng rồi vẫn sửa được (mục 4.5)
    before = _record(conn, session_id, student_id)
    after = conn.execute("UPDATE attendance_records SET status = %s, note = %s, decided_by = %s, updated_at = now() "
                         "WHERE session_id = %s AND student_id = %s RETURNING status, note, decided_by, updated_at",
                         (body.status, body.note, user["id"], session_id, student_id)).fetchone()
    audit.log(conn, user["id"], "record.update", f"attendance_records:{session_id}:{student_id}",
              {"status": before["status"], "note": before["note"]}, {"status": after["status"], "note": after["note"]},
              _ip(request))
    return {"student_id": student_id, **after}


def recenter_session(conn: psycopg.Connection, s: dict) -> dict:
    """Tâm mới = trung vị của tâm cũ và vị trí đã qua khuôn mặt; chấm lại lượt LOCATION_DRIFT, chỉ nâng hạng."""
    center = (s["center_lat"], s["center_lng"])
    new = geo.recenter(center, _passed_face_positions(conn, s["id"]) + [center])
    conn.execute("UPDATE attendance_sessions SET orig_center_lat = COALESCE(orig_center_lat, center_lat), "
                 "orig_center_lng = COALESCE(orig_center_lng, center_lng), center_lat = %s, center_lng = %s "
                 "WHERE id = %s", (new[0], new[1], s["id"]))
    drift = conn.execute("SELECT id, student_id, lat, lng, radius_m, flags FROM checkin_attempts WHERE session_id = %s "
                         "AND flags ? 'LOCATION_DRIFT'", (s["id"],)).fetchall()
    for a in drift:
        d = geo.haversine_m(*new, a["lat"], a["lng"])
        flags = a["flags"] if geo.classify(d, a["radius_m"]) != "ok" else \
            [f for f in a["flags"] if f != "LOCATION_DRIFT"]
        result = "suspicious" if flags else "pass"
        conn.execute("UPDATE checkin_attempts SET distance_m = %s, flags = %s::jsonb, result = %s WHERE id = %s",
                     (d, Jsonb(flags), result, a["id"]))
        if result == "pass":
            conn.execute("UPDATE attendance_records SET status = 'present', best_attempt_id = %s, updated_at = now() "
                         "WHERE session_id = %s AND student_id = %s AND decided_by IS NULL "
                         "AND status IN ('absent', 'suspicious')", (a["id"], s["id"], a["student_id"]))
    return {"center": {"lat": new[0], "lng": new[1]}, "re_evaluated": len(drift)}


@router.post("/sessions/{session_id}/recenter")
def recenter(session_id: int, request: Request, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    s = svc.load_session_for_lecturer(conn, session_id, user["id"])
    with conn.transaction():
        out = recenter_session(conn, s)
        audit.log(conn, user["id"], "session.recenter", f"attendance_sessions:{session_id}",
                  {"lat": s["center_lat"], "lng": s["center_lng"]}, out["center"], _ip(request))
    return out


@router.get("/attempts/{attempt_id}/evidence")
def evidence(attempt_id: int, request: Request, user=Lecturer, conn: psycopg.Connection = Depends(get_conn)):
    a = conn.execute("SELECT a.evidence_path FROM checkin_attempts a JOIN attendance_sessions s ON s.id = a.session_id "
                     "JOIN classes c ON c.id = s.class_id WHERE a.id = %s AND c.lecturer_id = %s "
                     "AND a.evidence_path IS NOT NULL AND a.evidence_expires_at > now()",
                     (attempt_id, user["id"])).fetchone()
    if not a:
        raise ApiError(404, "NOT_FOUND", "Không tìm thấy")
    data = crypto.load_blob(a["evidence_path"])
    audit.log(conn, user["id"], "evidence.view", f"checkin_attempts:{attempt_id}", ip=_ip(request))
    return Response(data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})
