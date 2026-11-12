"""Đăng ký, duyệt và xóa dữ liệu khuôn mặt (đặc tả mục 4.2, 4.6, 8, 9.3)."""
import base64
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, File, Request, Response, UploadFile
from pydantic import BaseModel

from app import audit, crypto, face_data
from app.config import get_settings
from app.db import get_conn
from app.errors import ApiError
from app.routers.me import consent_state
from app.security import require_role
from app.services.face.checks import quality_reason
from app.services.face.runtime import get_engine, infer
from app.services.face.types import FaceEngine
from app.services.face.verify import build_template

router = APIRouter(tags=["faces"])
Reviewer = Depends(require_role("admin", "lecturer"))
MIN_PHOTOS, MAX_PHOTOS = 3, 5


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _not_found() -> ApiError:
    return ApiError(404, "NOT_FOUND", "Không tìm thấy")


@router.post("/faces/enroll", status_code=201)
def enroll(request: Request, photos: list[UploadFile] = File(...), user=Depends(require_role("student")),
           engine: FaceEngine = Depends(get_engine), conn: psycopg.Connection = Depends(get_conn)):
    if not consent_state(conn, user["id"])["accepted"]:
        raise ApiError(409, "CONSENT_REQUIRED", "Bạn cần đồng ý văn bản xử lý dữ liệu khuôn mặt trước khi đăng ký")
    if not MIN_PHOTOS <= len(photos) <= MAX_PHOTOS:
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ",
                       [{"field": "photos", "msg": f"Cần từ {MIN_PHOTOS} đến {MAX_PHOTOS} ảnh"}])
    if conn.execute("SELECT 1 FROM face_templates WHERE student_id = %s AND status = 'pending'",
                    (user["id"],)).fetchone():
        raise ApiError(409, "FACE_PENDING_EXISTS", "Bạn đã có một mẫu khuôn mặt đang chờ duyệt")

    data = [p.file.read() for p in photos]
    cfg = get_settings().face
    template, issues = infer(build_template, data, engine, cfg)
    if template is None:
        raise ApiError(422, "ENROLL_REJECTED", "Một số ảnh chưa đạt, hãy chụp lại", {"photos": issues})

    try:
        with conn.transaction():
            tid = conn.execute(
                "INSERT INTO face_templates (student_id, model_name, embedding_enc, status) "
                "VALUES (%s, %s, %s, 'pending') RETURNING id",
                (user["id"], cfg.model_name, crypto.encrypt(crypto.embedding_to_bytes(template)))).fetchone()["id"]
    except psycopg.errors.UniqueViolation:  # hai request đăng ký chạy song song
        raise ApiError(409, "FACE_PENDING_EXISTS", "Bạn đã có một mẫu khuôn mặt đang chờ duyệt")
    rel = f"faces/{tid}"
    try:
        for i, d in enumerate(data):
            crypto.save_blob(f"{rel}/{i}.jpg", d)
    except Exception:
        crypto.delete_tree(rel)
        raise
    conn.execute("UPDATE face_templates SET photos_path = %s WHERE id = %s", (rel, tid))
    audit.log(conn, user["id"], "face.enroll", f"face_templates:{tid}", after={"photos": len(data)}, ip=_ip(request))
    return {"template_id": tid, "status": "pending"}


@router.post("/faces/precheck")
def precheck(photo: UploadFile = File(...), user=Depends(require_role("student")),
             engine: FaceEngine = Depends(get_engine)):
    """Kiểm tra nhanh một khung (không lưu, không trích đặc trưng) để app tự chụp khi đăng ký:
    trả lý do chất lượng nếu chưa đạt và hướng mặt (front / left / right / turning)."""
    cfg = get_settings().face
    a = infer(engine.analyze, photo.file.read(), embed=False, spoof=False)
    reason = quality_reason(a, cfg)
    pose = None
    if reason is None and a.yaw_proxy is not None:
        y = a.yaw_proxy * cfg.yaw_sign  # < 0: sinh viên quay sang trái (quy ước như checks.action_done)
        t = cfg.yaw_threshold
        pose = "front" if abs(y) <= t / 2 else "left" if y <= -t else "right" if y >= t else "turning"
    return {"ok": reason is None, "reason": reason, "pose": pose}


# ---- Duyệt (quản trị viên: mọi sinh viên; giảng viên: sinh viên các lớp mình dạy) ----

def _scope(user: dict) -> tuple[str, list]:
    if user["role"] == "admin":
        return "TRUE", []
    return ("EXISTS (SELECT 1 FROM enrollments e JOIN classes c ON c.id = e.class_id "
            "WHERE e.student_id = f.student_id AND c.lecturer_id = %s)", [user["id"]])


def _pending(conn, template_id: int, user: dict) -> dict:
    where, params = _scope(user)
    row = conn.execute(f"SELECT f.* FROM face_templates f WHERE f.id = %s AND f.status = 'pending' AND {where}",
                       [template_id, *params]).fetchone()
    if not row:
        raise _not_found()  # ngoài phạm vi cũng trả 404 để không lộ sự tồn tại
    return row


@router.get("/faces/pending")
def pending(user=Reviewer, conn: psycopg.Connection = Depends(get_conn)):
    where, params = _scope(user)
    rows = conn.execute(
        f"""SELECT f.id, f.student_id, f.created_at, f.photos_path, u.full_name, u.username, u.student_code,
              EXISTS (SELECT 1 FROM face_templates o WHERE o.student_id = f.student_id AND o.status = 'approved')
                AS is_update,
              ARRAY(SELECT c.code FROM enrollments e JOIN classes c ON c.id = e.class_id
                    WHERE e.student_id = f.student_id ORDER BY c.code) AS classes
            FROM face_templates f JOIN users u ON u.id = f.student_id
            WHERE f.status = 'pending' AND {where} ORDER BY f.created_at""", params).fetchall()
    for r in rows:
        path = r.pop("photos_path")
        r["photo_count"] = len(list(crypto.storage_path(path).glob("*.jpg"))) if path else 0
    return rows


@router.get("/faces/{template_id}/photos")
def photos(template_id: int, request: Request, user=Reviewer, conn: psycopg.Connection = Depends(get_conn)):
    row = _pending(conn, template_id, user)
    if not row["photos_path"]:
        raise _not_found()
    files = sorted(crypto.storage_path(row["photos_path"]).glob("*.jpg"), key=lambda p: int(p.stem))
    imgs = [crypto.load_blob(f"{row['photos_path']}/{p.name}") for p in files]
    audit.log(conn, user["id"], "face.photos.view", f"face_templates:{template_id}", ip=_ip(request))
    return {"photos": ["data:image/jpeg;base64," + base64.b64encode(b).decode() for b in imgs]}


class ReviewIn(BaseModel):
    decision: Literal["approve", "reject"]
    reason: str | None = None


@router.post("/faces/{template_id}/review")
def review(template_id: int, body: ReviewIn, request: Request, user=Reviewer,
           conn: psycopg.Connection = Depends(get_conn)):
    reason = (body.reason or "").strip() or None
    if body.decision == "reject" and not reason:
        raise ApiError(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ",
                       [{"field": "reason", "msg": "Từ chối phải ghi lý do để sinh viên chụp lại"}])
    row = _pending(conn, template_id, user)
    if body.decision == "approve":
        # Mẫu mới được duyệt thì mẫu cũ chuyển "thu hồi" và xóa embedding (mục 4.2).
        conn.execute("UPDATE face_templates SET status = 'revoked', embedding_enc = NULL "
                     "WHERE student_id = %s AND status = 'approved'", (row["student_id"],))
        updated = conn.execute(
            "UPDATE face_templates SET status = 'approved', photos_path = NULL, reviewed_by = %s, reviewed_at = now() "
            "WHERE id = %s AND status = 'pending' RETURNING id", (user["id"], template_id)).fetchone()
    else:
        updated = conn.execute(
            "UPDATE face_templates SET status = 'rejected', embedding_enc = NULL, photos_path = NULL, "
            "reject_reason = %s, reviewed_by = %s, reviewed_at = now() WHERE id = %s AND status = 'pending' "
            "RETURNING id", (reason, user["id"], template_id)).fetchone()
    if not updated:  # người khác vừa duyệt xong
        raise _not_found()
    if row["photos_path"]:
        crypto.delete_tree(row["photos_path"])  # mục 8: duyệt hay từ chối xong là xóa ảnh
    status = "approved" if body.decision == "approve" else "rejected"
    audit.log(conn, user["id"], "face.review", f"face_templates:{template_id}",
              after={"decision": status, "reason": reason, "student_id": row["student_id"]}, ip=_ip(request))
    return {"id": template_id, "status": status}


@router.delete("/me/face", status_code=204)
def delete_my_face(request: Request, user=Depends(require_role("student")),
                   conn: psycopg.Connection = Depends(get_conn)):
    face_data.delete_face_data(conn, user["id"], user["id"], _ip(request))
    return Response(status_code=204)
