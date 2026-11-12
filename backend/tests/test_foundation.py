from pydantic import BaseModel

from app.config import get_settings
from app.errors import ApiError
from app.main import app

TEN_TABLES = {"users", "classes", "enrollments", "consents", "face_templates", "attendance_sessions",
              "challenges", "checkin_attempts", "attendance_records", "audit_log"}


class _Body(BaseModel):
    email: str


@app.get("/__test/error")
def _raise():
    raise ApiError(409, "SESSION_CLOSED", "Phiên điểm danh đã đóng")


@app.post("/__test/body")
def _body(body: _Body):
    return {"ok": True}


def test_migration_creates_all_tables(conn):
    names = {r["table_name"] for r in conn.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_name <> 'alembic_version'")}
    assert names == TEN_TABLES | {"requests"}  # 0003: đơn xin nghỉ / khiếu nại


def test_fixtures_insert_rows(make_user, make_class, enroll, conn):
    gv = make_user("lecturer")
    sv = make_user()
    cls = make_class(gv["id"])
    enroll(cls["id"], sv["id"])
    assert sv["student_code"] and gv["student_code"] is None
    assert conn.execute("SELECT count(*) AS n FROM enrollments").fetchone()["n"] == 1


def test_api_error_envelope(client):
    r = client.get("/__test/error")
    assert r.status_code == 409
    assert r.json() == {"error": {"code": "SESSION_CLOSED", "message": "Phiên điểm danh đã đóng", "details": {}}}


def test_validation_error_envelope(client):
    r = client.post("/__test/body", json={"email": 1})
    assert r.status_code == 422
    err = r.json()["error"]
    assert err["code"] == "VALIDATION_ERROR" and err["details"][0]["field"] == "email"


def test_unknown_route_is_404_envelope(client):
    r = client.get("/khong-ton-tai")
    assert r.status_code == 404 and r.json()["error"]["code"] == "NOT_FOUND"


def test_payload_too_large(client):
    r = client.post("/__test/body", content=b"x" * (3 * 1024 * 1024 + 1), headers={"content-type": "application/json"})
    assert r.status_code == 413 and r.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_cors_allows_only_configured_origin(client):
    pre = {"Access-Control-Request-Method": "POST"}
    ok = client.options("/__test/body", headers={"Origin": "http://localhost:5173", **pre})
    assert ok.headers["access-control-allow-origin"] == "http://localhost:5173"
    bad = client.options("/__test/body", headers={"Origin": "https://evil.example", **pre})
    assert "access-control-allow-origin" not in bad.headers


def test_settings_values():
    s = get_settings()
    assert s.session.max_attempts == 5 and s.session.challenge_ttl_s == 60
    assert s.gps.max_acc_student_m == 30 and s.gps.default_r0_m == 20
    assert s.gps.r0_range_m == (10, 50) and s.retention.evidence_days == 30
