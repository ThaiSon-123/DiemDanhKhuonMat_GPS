"""Báo cáo chuyên cần theo lớp (đặc tả mục 9.2, 9.5)."""
import csv
import io

import psycopg
from fastapi import APIRouter, Depends
from fastapi.responses import Response

from app.config import get_settings
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
    limit = get_settings().attendance.warn_absent
    rows = [{**r, "warn": r["vang"] >= limit} for r in rows]
    return {"class": {k: c[k] for k in ("id", "code", "name", "semester")}, "session_count": len(sessions),
            "warn_absent": limit,
            "sessions": sessions, "first_try_pct": round(100 * first["ok"] / first["n"]) if first["n"] else None,
            "rows": rows}


@router.get("/admin/overview")
def overview(semester: str | None = None, user=Depends(require_role("admin")),
             conn: psycopg.Connection = Depends(get_conn)):
    """Bảng tổng quan cho quản trị: theo học kỳ (mặc định học kỳ mới nhất)."""
    semesters = [r["semester"] for r in conn.execute(
        "SELECT DISTINCT semester FROM classes ORDER BY semester DESC").fetchall()]
    sem = semester or (semesters[0] if semesters else None)
    limit = get_settings().attendance.warn_absent
    classes = conn.execute(
        """SELECT c.id, c.code, c.name, l.full_name AS lecturer_name,
                  (SELECT count(*) FROM enrollments e WHERE e.class_id = c.id) AS students,
                  (SELECT count(*) FROM attendance_sessions s WHERE s.class_id = c.id) AS sessions,
                  count(r.student_id) AS records,
                  count(r.student_id) FILTER (WHERE r.status IN ('present', 'manual_present')) AS present,
                  count(r.student_id) FILTER (WHERE r.status = 'suspicious') AS suspicious,
                  count(r.student_id) FILTER (WHERE r.status = 'excused') AS excused
           FROM classes c JOIN users l ON l.id = c.lecturer_id
           LEFT JOIN attendance_sessions s ON s.class_id = c.id
           LEFT JOIN attendance_records r ON r.session_id = s.id
           WHERE c.semester = %s GROUP BY c.id, l.full_name ORDER BY c.code""", (sem,)).fetchall()
    # Sinh viên vắng nhiều (kể cả bị từ chối, chỉ buổi đã đóng) theo từng lớp.
    warn = {r["class_id"]: r["n"] for r in conn.execute(
        """SELECT class_id, count(*) AS n FROM (
             SELECT s.class_id, r.student_id FROM attendance_records r JOIN attendance_sessions s ON s.id = r.session_id
             JOIN classes c ON c.id = s.class_id
             WHERE c.semester = %s AND r.status IN ('absent', 'rejected')
               AND (s.closed_at IS NOT NULL OR s.expires_at <= now())
             GROUP BY s.class_id, r.student_id HAVING count(*) >= %s) t GROUP BY class_id""", (sem, limit)).fetchall()}
    for c in classes:
        c["warn_students"] = warn.get(c["id"], 0)
        c["present_pct"] = round(100 * c["present"] / c["records"]) if c["records"] else None
    flags = conn.execute(
        """SELECT f AS flag, count(*) AS n FROM checkin_attempts a JOIN attendance_sessions s ON s.id = a.session_id
           JOIN classes c ON c.id = s.class_id, jsonb_array_elements_text(a.flags) f
           WHERE c.semester = %s GROUP BY f ORDER BY n DESC""", (sem,)).fetchall()
    fails = conn.execute(
        """SELECT a.fail_reason AS reason, count(*) AS n FROM checkin_attempts a
           JOIN attendance_sessions s ON s.id = a.session_id JOIN classes c ON c.id = s.class_id
           WHERE c.semester = %s AND a.result = 'fail' AND a.fail_reason IS NOT NULL
           GROUP BY a.fail_reason ORDER BY n DESC""", (sem,)).fetchall()
    attempts = conn.execute(
        """SELECT count(*) AS n, count(*) FILTER (WHERE a.result = 'pass') AS pass,
                  count(*) FILTER (WHERE a.result = 'suspicious') AS suspicious
           FROM checkin_attempts a JOIN attendance_sessions s ON s.id = a.session_id JOIN classes c ON c.id = s.class_id
           WHERE c.semester = %s""", (sem,)).fetchone()
    records = sum(c["records"] for c in classes)
    return {
        "semesters": semesters, "semester": sem, "warn_absent": limit,
        "totals": {"classes": len(classes), "sessions": sum(c["sessions"] for c in classes),
                   "present_pct": round(100 * sum(c["present"] for c in classes) / records) if records else None,
                   "warn_students": sum(warn.values()), "attempts": attempts["n"], "pass": attempts["pass"],
                   "suspicious": attempts["suspicious"],
                   "pending_requests": conn.execute(
                       "SELECT count(*) AS n FROM requests r JOIN attendance_sessions s ON s.id = r.session_id "
                       "JOIN classes c ON c.id = s.class_id WHERE c.semester = %s AND r.status = 'pending'",
                       (sem,)).fetchone()["n"]},
        "classes": classes, "flags": flags, "fail_reasons": fails,
    }
