"""Trạng thái và thu hồi dữ liệu khuôn mặt, dùng chung cho quản trị, /me và đăng ký khuôn mặt."""
import shutil

import psycopg

# Biểu thức SQL cho cột face_status của một dòng users bí danh `u` (đặc tả mục 9.5: none/pending/approved/rejected).
FACE_STATUS_SQL = """COALESCE((
  SELECT CASE WHEN bool_or(f.status = 'approved') THEN 'approved'
              WHEN bool_or(f.status = 'pending') THEN 'pending'
              WHEN bool_or(f.status = 'rejected') THEN 'rejected' END
  FROM face_templates f WHERE f.student_id = u.id AND f.status <> 'revoked'), 'none')"""


def revoke_all(conn: psycopg.Connection, student_id: int) -> int:
    """Thu hồi mọi mẫu còn hiệu lực: xóa embedding và thư mục ảnh đăng ký ngay (mục 4.6). Trả số mẫu bị thu hồi."""
    live = "student_id = %s AND status IN ('pending', 'approved')"
    paths = [r["photos_path"] for r in conn.execute(f"SELECT photos_path FROM face_templates WHERE {live}",
                                                     (student_id,)).fetchall()]
    conn.execute(f"UPDATE face_templates SET status = 'revoked', embedding_enc = NULL, photos_path = NULL "
                 f"WHERE {live}", (student_id,))
    for p in filter(None, paths):
        shutil.rmtree(p, ignore_errors=True)
    return len(paths)


def face_state(conn: psycopg.Connection, student_id: int, model_name: str) -> dict:
    """Trạng thái khuôn mặt cho /me (đặc tả mục 9.5). model_ok chỉ có nghĩa khi đã có mẫu được duyệt."""
    rows = conn.execute("SELECT status, model_name, reject_reason FROM face_templates "
                        "WHERE student_id = %s AND status <> 'revoked' ORDER BY id DESC", (student_id,)).fetchall()
    by = {}
    for r in rows:
        by.setdefault(r["status"], r)  # mẫu mới nhất của mỗi trạng thái
    if "approved" in by:
        return {"status": "approved", "reject_reason": None,
                "model_ok": by["approved"]["model_name"] == model_name, "pending_update": "pending" in by}
    if "pending" in by:
        return {"status": "pending", "reject_reason": None, "model_ok": None, "pending_update": False}
    if "rejected" in by:
        return {"status": "rejected", "reject_reason": by["rejected"]["reject_reason"], "model_ok": None,
                "pending_update": False}
    return {"status": "none", "reject_reason": None, "model_ok": None, "pending_update": False}
