from app.security import verify_password
from app.services import importer

BOM = "﻿"
USERS_HEADER = "role,username,email,full_name,student_code\n"


def count(conn, table):
    return conn.execute(f"SELECT count(*) c FROM {table}").fetchone()["c"]


def test_import_users_all_or_nothing(conn):
    csv = USERS_HEADER + "student,sv1,a@x.vn,A,SV1\nstudent,SV1,,B,SV2\n"
    res = importer.run(conn, "users", csv, dry_run=False)
    assert res["ok"] is False and res["errors"] == [{"line": 3, "msg": "Tên đăng nhập trùng với dòng 2: sv1"}]
    assert count(conn, "users") == 0


def test_import_users_creates_temp_passwords(conn):
    csv = (BOM + "role,username,email,full_name,student_code\r\n"   # BOM + CRLF như file Excel xuất ra
           "student, SV001 , SV1@X.vn ,Nguyễn Văn An,SV001\r\nlecturer,duc.tm,,Trần Minh Đức,\r\n")
    res = importer.run(conn, "users", csv, dry_run=False)
    assert res["ok"] is True and res["created"] == 2 and res["errors"] == []
    assert [p["username"] for p in res["passwords"]] == ["sv001", "duc.tm"]
    rows = conn.execute("SELECT * FROM users ORDER BY id").fetchall()
    assert [(r["role"], r["username"], r["email"], r["student_code"], r["must_change_password"]) for r in rows] == [
        ("student", "sv001", "sv1@x.vn", "SV001", True), ("lecturer", "duc.tm", None, None, True)]
    assert verify_password(res["passwords"][0]["temp_password"], rows[0]["password_hash"])


def test_import_users_validates_each_line(conn, make_user):
    make_user("student", username="coroi", email="co-roi@x.vn", student_code="SV9")
    csv = (USERS_HEADER +
           "teacher,aaa,,A,\n"                 # vai trò sai
           "student,bbb,,B,\n"                 # thiếu mã SV
           "student,coroi,,C,SV3\n"            # tên đăng nhập đã có trong hệ thống
           "student,ddd,,D,SV9\n"              # mã SV đã có
           "student,eee,khong-email,E,SV5\n"   # email sai
           "student,fff,,,SV6\n"               # thiếu họ tên
           "student,g g,,G,SV7\n"              # tên đăng nhập sai định dạng
           "student,hhh,co-roi@x.vn,H,SV8\n")  # email đã có
    res = importer.run(conn, "users", csv, dry_run=False)
    assert [e["line"] for e in res["errors"]] == [2, 3, 4, 5, 6, 7, 8, 9]
    assert res["errors"][2]["msg"] == "Tên đăng nhập đã tồn tại: coroi"
    assert res["errors"][7]["msg"] == "Email đã tồn tại: co-roi@x.vn"
    assert count(conn, "users") == 1


def test_import_missing_columns(conn):
    res = importer.run(conn, "users", "email,full_name\na@x.vn,A\n", dry_run=False)
    assert res["ok"] is False and res["errors"] == [{"line": 1, "msg": "Thiếu cột: role, username, student_code"}]
    ok = importer.run(conn, "users", "role,username,full_name,student_code\nstudent,sv1,A,SV1\n", dry_run=True)
    assert ok["ok"] is True  # cột email không bắt buộc


def test_import_dry_run_writes_nothing(conn):
    res = importer.run(conn, "users", USERS_HEADER + "student,sv1,,A,SV1\n", dry_run=True)
    assert res["ok"] is True and res["created"] == 1 and res["passwords"] == []
    assert count(conn, "users") == 0


def test_import_classes_unknown_lecturer(conn, make_user):
    make_user("lecturer", email="gv@x.vn")
    make_user("student", email="sv@x.vn")
    csv = ("code,name,semester,lecturer_email\n"
           "IT4060,Học máy,2026-1,gv@x.vn\n"
           "IT4343,Thị giác máy tính,2026-1,khong-co@x.vn\n"
           "IT4310,Xử lý ảnh,2026-1,sv@x.vn\n")
    res = importer.run(conn, "classes", csv, dry_run=False)
    assert res["errors"] == [{"line": 3, "msg": "Không có giảng viên với email: khong-co@x.vn"},
                             {"line": 4, "msg": "Không có giảng viên với email: sv@x.vn"}]
    assert count(conn, "classes") == 0


def test_import_classes_ok_and_duplicate(conn, make_user, make_class):
    gv = make_user("lecturer", email="gv@x.vn")
    make_class(gv["id"], code="IT1", semester="2026-1")
    csv = "code,name,semester,lecturer_email\nIT2,Lớp 2,2026-1,GV@x.vn\nIT1,Lớp 1,2026-1,gv@x.vn\n"
    assert importer.run(conn, "classes", csv, dry_run=False)["errors"] == [
        {"line": 3, "msg": "Lớp đã tồn tại: IT1 (2026-1)"}]
    res = importer.run(conn, "classes", "code,name,semester,lecturer_email\nIT2,Lớp 2,2026-1,gv@x.vn\n", False)
    assert res["ok"] and res["created"] == 1


def test_import_enrollments_skips_existing(conn, make_user, make_class, enroll):
    gv = make_user("lecturer")
    c = make_class(gv["id"], code="IT4060", semester="2026-1")
    a = make_user("student", student_code="SV001")
    make_user("student", student_code="SV002")
    enroll(c["id"], a["id"])
    csv = "class_code,semester,student_code\nIT4060,2026-1,SV001\nIT4060,2026-1,SV002\n"
    res = importer.run(conn, "enrollments", csv, dry_run=False)
    assert res["ok"] and res["created"] == 1
    assert count(conn, "enrollments") == 2


def test_import_enrollments_unknown_refs(conn, make_user, make_class):
    gv = make_user("lecturer")
    make_class(gv["id"], code="IT4060", semester="2026-1")
    csv = "class_code,semester,student_code\nIT9999,2026-1,SV001\nIT4060,2026-1,SV404\n"
    assert importer.run(conn, "enrollments", csv, dry_run=False)["errors"] == [
        {"line": 2, "msg": "Không có lớp: IT9999 (2026-1)"},
        {"line": 3, "msg": "Không có sinh viên với mã: SV404"}]
