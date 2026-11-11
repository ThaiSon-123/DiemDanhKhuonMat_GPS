"""Báo cáo chuyên cần theo lớp (đặc tả mục 9.2, 9.5)."""
import csv
import io

import psycopg
from fastapi import APIRouter, Depends
from fastapi.responses import Response

from app.db import get_conn
from app.errors import ApiError
from app.security import require_role

router = APIRouter(tags=["reports"])

COLS = ("student_code", "full_name", "co_mat", "vang_co_phep", "vang", "chua_duyet", "so_buoi")
HEADERS = ("MSSV", "Họ tên", "Có mặt", "Vắng có phép", "Vắng", "Chưa duyệt", "Số buổi")


@router.get("/reports/classes/{class_id}")
def class_report(class_id: int, format: str = "json", user=Depends(require_role("lecturer", "admin")),
                 conn: psycopg.Connection = Depends(get_conn)):
    c = conn.execute("SELECT id, code, name, semester, lecturer_id FROM classes WHERE id = %s", (class_id,)).fetchone()
    if not c or (user["role"] == "lecturer" and c["lecturer_id"] != user["id"]):
        raise ApiError(404, "NOT_FOUND", "Không tìm thấy")
    rows = conn.execute(
        """SELECT u.id AS student_id, u.student_code, u.full_name,
                  count(*) FILTER (WHERE r.status IN ('present','manual_present')) AS co_mat,
                  count(*) FILTER (WHERE r.status = 'excused')                     AS vang_co_phep,
                  count(*) FILTER (WHERE r.status IN ('absent','rejected'))        AS vang,
                  count(*) FILTER (WHERE r.status = 'suspicious')                  AS chua_duyet,
                  count(*)                                                         AS so_buoi
           FROM attendance_records r
           JOIN attendance_sessions s ON s.id = r.session_id
           JOIN users u ON u.id = r.student_id
           WHERE s.class_id = %s
           GROUP BY u.id ORDER BY u.student_code""", (class_id,)).fetchall()
    if format == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(HEADERS)
        w.writerows([r[k] for k in COLS] for r in rows)
        return Response("﻿" + buf.getvalue(), media_type="text/csv; charset=utf-8",
                        headers={"Content-Disposition": f'attachment; filename="bao-cao-{c["code"]}.csv"'})
    sessions = conn.execute(
        """SELECT s.id, s.opened_at,
                  count(*) FILTER (WHERE r.status IN ('present','manual_present')) AS present,
                  count(*) FILTER (WHERE r.status = 'suspicious') AS suspicious, count(r.student_id) AS total
           FROM attendance_sessions s LEFT JOIN attendance_records r ON r.session_id = s.id
           WHERE s.class_id = %s GROUP BY s.id ORDER BY s.opened_at""", (class_id,)).fetchall()
    # Thành công ngay lần đầu: trong các (buổi, sinh viên) có ít nhất một lượt, lượt đầu tiên đạt luôn.
    first = conn.execute(
        """SELECT count(*) AS n, count(*) FILTER (WHERE result = 'pass') AS ok FROM (
             SELECT DISTINCT ON (a.session_id, a.student_id) a.result FROM checkin_attempts a
             JOIN attendance_sessions s ON s.id = a.session_id WHERE s.class_id = %s
             ORDER BY a.session_id, a.student_id, a.id) t""", (class_id,)).fetchone()
    return {"class": {k: c[k] for k in ("id", "code", "name", "semester")}, "session_count": len(sessions),
            "sessions": sessions, "first_try_pct": round(100 * first["ok"] / first["n"]) if first["n"] else None,
            "rows": rows}
