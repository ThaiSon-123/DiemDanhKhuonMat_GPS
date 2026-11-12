"""Dọn dữ liệu hằng ngày (đặc tả mục 8; chạy bằng cron trên VPS):
ảnh bằng chứng quá hạn, ảnh đăng ký còn sót của mẫu đã duyệt / từ chối / thu hồi, thử thách cũ không có lượt thử.

    python -m app.jobs.cleanup
"""
import sys
from datetime import datetime, timedelta, timezone

import psycopg

from app import crypto

CHALLENGE_KEEP = timedelta(days=1)


def run(conn: psycopg.Connection, now: datetime) -> dict:
    evidence = conn.execute("SELECT id, evidence_path FROM checkin_attempts "
                            "WHERE evidence_path IS NOT NULL AND evidence_expires_at <= %s", (now,)).fetchall()
    for r in evidence:
        crypto.delete_blob(r["evidence_path"])  # file đã mất cũng không lỗi
        conn.execute("UPDATE checkin_attempts SET evidence_path = NULL WHERE id = %s", (r["id"],))

    photos = conn.execute("SELECT id, photos_path FROM face_templates "
                          "WHERE photos_path IS NOT NULL AND status <> 'pending'").fetchall()
    for r in photos:
        crypto.delete_tree(r["photos_path"])
        conn.execute("UPDATE face_templates SET photos_path = NULL WHERE id = %s", (r["id"],))

    challenges = conn.execute(
        "DELETE FROM challenges c WHERE c.created_at < %s "
        "AND NOT EXISTS (SELECT 1 FROM checkin_attempts a WHERE a.challenge_id = c.id)", (now - CHALLENGE_KEEP,)).rowcount
    return {"evidence": len(evidence), "photos": len(photos), "challenges": challenges}


def main() -> int:
    from dotenv import load_dotenv

    from app.config import BASE_DIR
    from app.db import get_pool

    load_dotenv(BASE_DIR / ".env")
    with get_pool().connection() as conn:
        print(run(conn, datetime.now(timezone.utc)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
