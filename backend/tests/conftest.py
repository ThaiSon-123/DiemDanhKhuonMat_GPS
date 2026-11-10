import base64
import itertools
import os
import tempfile
from pathlib import Path

# Bí mật cho test, đặt trước khi import app.
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("DATA_KEY", base64.b64encode(b"\0" * 32).decode())
os.environ.setdefault("STORAGE_DIR", tempfile.mkdtemp())
os.environ["CORS_ORIGIN_REGEX"] = r"^http://localhost(:\d+)?$"

import psycopg
import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from psycopg.rows import dict_row

BACKEND = Path(__file__).resolve().parent.parent
TABLES = ("users, classes, enrollments, consents, face_templates, attendance_sessions, "
          "challenges, checkin_attempts, attendance_records, audit_log")


@pytest.fixture(scope="session")
def database_url():
    # Cố ý KHÔNG dùng DATABASE_URL: mỗi test TRUNCATE mọi bảng, trỏ nhầm vào DB dev là mất dữ liệu.
    url = os.environ.get("TEST_DATABASE_URL")
    server = None
    if not url:
        import pgserver
        server = pgserver.get_server(tempfile.mkdtemp(), cleanup_mode="stop")
        url = server.get_uri()
    os.environ["DATABASE_URL"] = url  # cho pool của app và Alembic
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "migrations"))
    command.upgrade(cfg, "head")
    yield url


@pytest.fixture
def conn(database_url):
    with psycopg.connect(database_url, autocommit=True, row_factory=dict_row) as c:
        c.execute(f"TRUNCATE {TABLES} RESTART IDENTITY CASCADE")
        yield c


@pytest.fixture
def client(conn):
    from app.main import app
    with TestClient(app) as c:
        yield c


_seq = itertools.count(1)


@pytest.fixture
def make_user(conn):
    def make(role="student", **kw):
        n = next(_seq)
        row = {"role": role, "email": f"u{n}@test.vn", "password_hash": "x", "full_name": f"User {n}",
               "must_change_password": False, **kw}
        if role == "student":
            row.setdefault("student_code", f"SV{n:04d}")
        cols = ", ".join(row)
        vals = ", ".join(f"%({k})s" for k in row)
        return conn.execute(f"INSERT INTO users ({cols}) VALUES ({vals}) RETURNING *", row).fetchone()
    return make


@pytest.fixture
def make_class(conn):
    def make(lecturer_id, **kw):
        n = next(_seq)
        row = {"code": f"IT{n:04d}", "name": f"Lớp {n}", "semester": "2026-1", "lecturer_id": lecturer_id, **kw}
        return conn.execute("INSERT INTO classes (code, name, semester, lecturer_id) "
                            "VALUES (%(code)s, %(name)s, %(semester)s, %(lecturer_id)s) RETURNING *", row).fetchone()
    return make


@pytest.fixture
def enroll(conn):
    def do(class_id, student_id):
        conn.execute("INSERT INTO enrollments VALUES (%s, %s)", (class_id, student_id))
    return do
