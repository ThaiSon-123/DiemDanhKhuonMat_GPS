import json
import math
import threading
import time
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app import crypto
from app.config import get_settings
from app.services.checkin import collect_flags
from app.services.face.runtime import get_engine
from app.services.face.types import FaceResult
from app.services.geo import Sample
from face_fakes import E0, FakeEngine, fa, vec

CLAT, CLNG = 21.005, 105.844  # tâm phiên, trong khuôn viên tạm
M_PER_DEG_LAT = 111_195


def north(m: float) -> float:
    return CLAT + m / M_PER_DEG_LAT


def gps(d_m=10.0, acc=10.0, n=4, mock=False, lat=None):
    lat = north(d_m) if lat is None else lat
    return [{"lat": lat, "lng": CLNG, "acc": acc, "ts": 1_794_000_000_000 + i * 1000, "mock": mock} for i in range(n)]


TURN = {"turn_left": [0.0, -0.1, -0.3, -0.3, -0.3], "turn_right": [0.0, 0.1, 0.3, 0.3, 0.3]}


def code(r):
    return r.json()["error"]["code"]


@pytest.fixture(autouse=True)
def thresholds(monkeypatch):
    """Ngưỡng cố định cho test, không phụ thuộc config.yaml (chốt ở Task 11)."""
    f = get_settings().face
    for k, v in dict(accept_threshold=0.5, suspect_threshold=0.4, antispoof_threshold=0.5, yaw_sign=1,
                     yaw_threshold=0.25, min_brightness=60, min_sharpness=50, min_face_px=100).items():
        monkeypatch.setattr(f, k, v)


@pytest.fixture
def engine(client):
    from app.main import app
    eng = FakeEngine({})
    app.dependency_overrides[get_engine] = lambda: eng
    yield eng
    app.dependency_overrides.pop(get_engine, None)


def set_frames(engine, action, emb=E0, **kw):
    """5 khung làm đúng hành động; trả danh sách bytes để gửi."""
    keys = [f"f{i}".encode() for i in range(5)]
    for k, y in zip(keys, TURN[action]):
        engine.results[k] = fa(yaw_proxy=y, embedding=emb, **kw)
    return keys


@pytest.fixture
def world(conn, make_user, make_class, enroll):
    """Lớp có 1 giảng viên, 2 sinh viên đã có mẫu duyệt; phiên mở ở tâm (CLAT, CLNG), σ_gv = 8, r0 = 20."""
    gv = make_user("lecturer")
    c = make_class(gv["id"])
    students = []
    for _ in range(2):
        s = make_user("student")
        enroll(c["id"], s["id"])
        conn.execute("INSERT INTO face_templates (student_id, model_name, status, embedding_enc) VALUES (%s, %s, "
                     "'approved', %s)", (s["id"], get_settings().face.model_name,
                                         crypto.encrypt(crypto.embedding_to_bytes(E0))))
        students.append(s)
    sess = conn.execute(
        "INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, base_radius_m, "
        "room_check, room_secret, expires_at) VALUES (%s, %s, %s, %s, 8, 20, false, %s, now() + interval '10 minutes') "
        "RETURNING *", (c["id"], gv["id"], CLAT, CLNG, b"k" * 32)).fetchone()
    conn.execute("INSERT INTO attendance_records (session_id, student_id, status) "
                 "SELECT %s, student_id, 'absent' FROM enrollments WHERE class_id = %s", (sess["id"], c["id"]))
    return {"gv": gv, "class": c, "students": students, "sid": sess["id"]}


def challenge(client, auth, world, who=0):
    return client.post(f"/sessions/{world['sid']}/challenge", headers=auth(world["students"][who]))


def checkin(client, auth, world, ch, frames, who=0, d_m=10.0, device="dev-1", c=None, **meta):
    m = {"nonce": ch["nonce"], "device_id": device, "gps_samples": gps(d_m), **meta}
    files = [("frames", (f"{i}.jpg", f, "image/jpeg")) for i, f in enumerate(frames)]
    return (c or client).post(f"/sessions/{world['sid']}/checkin", headers=auth(world["students"][who]),
                              data={"meta": json.dumps(m)}, files=files)


def run(client, auth, world, engine, who=0, d_m=10.0, emb=E0, device="dev-1", **kw):
    ch = challenge(client, auth, world, who).json()
    frames = set_frames(engine, ch["action"], emb=emb, **kw)
    return checkin(client, auth, world, ch, frames, who=who, d_m=d_m, device=device)


def record(conn, world, who=0):
    return conn.execute("SELECT * FROM attendance_records WHERE session_id = %s AND student_id = %s",
                        (world["sid"], world["students"][who]["id"])).fetchone()


def attempts(conn):
    return conn.execute("SELECT * FROM checkin_attempts ORDER BY id").fetchall()


# ---- Kết quả ----

def test_happy_path_present(client, auth, world, engine, conn):
    r = run(client, auth, world, engine)
    assert r.status_code == 200
    assert r.json() == {"result": "pass", "record_status": "present", "reason": None, "attempts_left": 4}
    a = attempts(conn)[0]
    assert a["result"] == "pass" and a["fail_step"] is None and a["flags"] == []
    assert a["distance_m"] == pytest.approx(10, abs=0.5) and a["radius_m"] == pytest.approx(38)
    assert a["device_id"] == "dev-1" and len(a["gps_samples"]) == 4 and a["evidence_path"] is None
    assert record(conn, world)["best_attempt_id"] == a["id"]


def test_drift_is_suspicious(client, auth, world, engine, conn):
    r = run(client, auth, world, engine, d_m=50)  # r = 20 + 8 + 10 = 38 < 50 ≤ 76
    assert r.json()["result"] == "suspicious" and r.json()["record_status"] == "suspicious"
    assert attempts(conn)[0]["flags"] == ["LOCATION_DRIFT"]


def test_far_fails_without_running_face(client, auth, world, engine, conn):
    r = run(client, auth, world, engine, d_m=500)
    assert r.json()["result"] == "fail" and r.json()["reason"]["code"] == "GPS_TOO_FAR"
    assert engine.calls == []
    a = attempts(conn)[0]
    assert a["fail_step"] == 4 and a["distance_m"] > 400 and record(conn, world)["status"] == "absent"


def test_low_accuracy(client, auth, world, engine, conn):
    ch = challenge(client, auth, world).json()
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), gps_samples=gps(acc=40))
    assert r.json()["reason"]["code"] == "GPS_ACCURACY_LOW" and attempts(conn)[0]["fail_step"] == 4


def test_mock_location_flag(client, auth, world, engine, conn):
    ch = challenge(client, auth, world).json()
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), gps_samples=gps(mock=True))
    assert r.json()["result"] == "suspicious" and attempts(conn)[0]["flags"] == ["MOCK_LOCATION"]


def test_shared_device_flag(client, auth, world, engine, conn):
    assert run(client, auth, world, engine, who=0, device="chung").json()["result"] == "pass"
    r = run(client, auth, world, engine, who=1, device="chung")
    assert r.json()["result"] == "suspicious" and attempts(conn)[1]["flags"] == ["SHARED_DEVICE"]


def test_location_jump_from_previous_attempt(client, auth, world, engine, conn):
    run(client, auth, world, engine, emb=vec(0.1))           # lượt 1 không khớp mặt nhưng có vị trí
    ch = challenge(client, auth, world).json()                # lượt 2 vài giây sau, cách 300 m về phía Nam
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), gps_samples=gps(lat=north(10) - 300 / M_PER_DEG_LAT))
    assert r.json()["result"] == "fail"  # 300 m vẫn > 2r: không đạt vì xa
    ch = challenge(client, auth, world).json()
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), gps_samples=gps(d_m=10))
    assert "LOCATION_JUMP" in attempts(conn)[-1]["flags"] and r.json()["result"] == "suspicious"


def test_borderline_face(client, auth, world, engine, conn):
    r = run(client, auth, world, engine, emb=vec(0.45))
    assert r.json()["result"] == "suspicious" and attempts(conn)[0]["flags"] == ["FACE_BORDERLINE"]


def test_spoof_reason(client, auth, world, engine, conn):
    r = run(client, auth, world, engine, spoof_score=0.1)
    assert r.json()["reason"]["code"] == "SPOOF_DETECTED" and r.json()["record_status"] == "absent"
    assert attempts(conn)[0]["fail_step"] == 5


def test_action_and_mismatch_reasons(client, auth, world, engine, conn):
    ch = challenge(client, auth, world).json()
    wrong = "turn_right" if ch["action"] == "turn_left" else "turn_left"
    r = checkin(client, auth, world, ch, set_frames(engine, wrong))
    assert r.json()["reason"]["code"] == "ACTION_NOT_DETECTED" and "quay" in r.json()["reason"]["message"]
    r = run(client, auth, world, engine, emb=vec(0.2))
    assert r.json()["reason"]["code"] == "FACE_MISMATCH" and attempts(conn)[-1]["fail_step"] == 6


def test_room_token_required_when_enabled(client, auth, world, engine, conn):
    conn.execute("UPDATE attendance_sessions SET room_check = true")
    ch = challenge(client, auth, world).json()
    assert ch["room_check"] is True
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), room_token="SAIMA000")
    assert r.json()["reason"]["code"] == "ROOM_TOKEN_INVALID"
    a = attempts(conn)[0]
    assert a["fail_step"] == 3 and a["room_token_ok"] is False and engine.calls == []


def test_room_token_ok(client, auth, world, engine, conn):
    from app.services.room_token import room_code
    conn.execute("UPDATE attendance_sessions SET room_check = true")
    ch = challenge(client, auth, world).json()
    tok = room_code(b"k" * 32, world["sid"], time.time()).lower()
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), room_token=tok)
    assert r.json()["result"] == "pass" and attempts(conn)[0]["room_token_ok"] is True


def test_room_token_burst(client, auth, world, engine, conn, make_user, enroll):
    from app.services.room_token import room_code
    conn.execute("UPDATE attendance_sessions SET room_check = true")
    for _ in range(1):  # thêm SV thứ 3 có mẫu
        s = make_user("student")
        enroll(world["class"]["id"], s["id"])
        conn.execute("INSERT INTO face_templates (student_id, model_name, status, embedding_enc) VALUES "
                     "(%s, %s, 'approved', %s)", (s["id"], get_settings().face.model_name,
                                                  crypto.encrypt(crypto.embedding_to_bytes(E0))))
        world["students"].append(s)
    from app.main import app
    tok = room_code(b"k" * 32, world["sid"], time.time())
    results = []
    with TestClient(app, client=("10.0.0.5", 50000)) as same_ip:  # 3 máy cùng một IP (vd chuyển tiếp mã)
        for who in range(3):
            ch = challenge(client, auth, world, who).json()
            results.append(checkin(client, auth, world, ch, set_frames(engine, ch["action"]), who=who,
                                   device=f"d{who}", room_token=tok, c=same_ip).json()["result"])
    assert results == ["pass", "pass", "suspicious"]
    assert attempts(conn)[-1]["flags"] == ["ROOM_TOKEN_BURST"]


# ---- Cập nhật kết quả ----

def test_fail_never_downgrades_present(client, auth, world, engine, conn):
    assert run(client, auth, world, engine).json()["result"] == "pass"
    r = client.post(f"/sessions/{world['sid']}/challenge", headers=auth(world["students"][0]))
    assert code(r) == "ALREADY_PRESENT"
    # một lượt "đáng ngờ" của người đã có mặt (nonce cấp trước khi có mặt) cũng không hạ kết quả
    conn.execute("UPDATE attendance_records SET status = 'present'")
    assert record(conn, world)["status"] == "present"


def test_suspicious_then_pass_upgrades(client, auth, world, engine, conn):
    assert run(client, auth, world, engine, emb=vec(0.45)).json()["record_status"] == "suspicious"
    assert run(client, auth, world, engine).json()["record_status"] == "present"


def test_lecturer_decision_locked(client, auth, world, engine, conn):
    conn.execute("UPDATE attendance_records SET status = 'excused', decided_by = %s WHERE student_id = %s",
                 (world["gv"]["id"], world["students"][0]["id"]))
    r = run(client, auth, world, engine)
    assert r.json()["result"] == "pass" and r.json()["record_status"] == "excused"
    assert record(conn, world)["status"] == "excused"


def test_late_enrolled_student(client, auth, world, engine, conn, make_user, enroll):
    s = make_user("student")
    enroll(world["class"]["id"], s["id"])  # vào lớp sau khi mở phiên: chưa có dòng absent
    conn.execute("INSERT INTO face_templates (student_id, model_name, status, embedding_enc) VALUES (%s, %s, "
                 "'approved', %s)", (s["id"], get_settings().face.model_name,
                                     crypto.encrypt(crypto.embedding_to_bytes(E0))))
    world["students"].append(s)
    assert run(client, auth, world, engine, who=2).json()["record_status"] == "present"


# ---- Thử thách ----

def test_challenge_shape(client, auth, world):
    r = challenge(client, auth, world)
    body = r.json()
    assert r.status_code == 200 and body["action"] in ("turn_left", "turn_right") and len(body["nonce"]) >= 32
    exp = datetime.fromisoformat(body["expires_at"]) - datetime.now(timezone.utc)
    assert timedelta(seconds=50) < exp <= timedelta(seconds=60) and body["attempts_left"] == 4


def test_attempts_exhausted(client, auth, world):
    for i in range(5):
        assert challenge(client, auth, world).json()["attempts_left"] == 4 - i
    r = challenge(client, auth, world)
    assert r.status_code == 429 and code(r) == "ATTEMPTS_EXHAUSTED"


def test_challenge_requires_face(client, auth, world, conn):
    conn.execute("UPDATE face_templates SET model_name = 'cu' WHERE student_id = %s", (world["students"][0]["id"],))
    r = challenge(client, auth, world)
    assert r.status_code == 409 and code(r) == "FACE_NOT_ENROLLED" and r.json()["error"]["details"]["reason"] == "model_outdated"
    conn.execute("DELETE FROM face_templates WHERE student_id = %s", (world["students"][0]["id"],))
    assert code(challenge(client, auth, world)) == "FACE_NOT_ENROLLED"


def test_challenge_scope(client, auth, world, make_user, conn):
    outsider = make_user("student")
    r = client.post(f"/sessions/{world['sid']}/challenge", headers=auth(outsider))
    assert r.status_code == 404
    conn.execute("UPDATE attendance_sessions SET closed_at = now()")
    assert code(challenge(client, auth, world)) == "SESSION_CLOSED"


def test_nonce_reuse(client, auth, world, engine, conn):
    ch = challenge(client, auth, world).json()
    frames = set_frames(engine, ch["action"], emb=vec(0.1))
    assert checkin(client, auth, world, ch, frames).status_code == 200
    r = checkin(client, auth, world, ch, frames)
    assert r.status_code == 409 and code(r) == "CHALLENGE_INVALID" and len(attempts(conn)) == 1


def test_nonce_other_student(client, auth, world, engine, conn):
    ch = challenge(client, auth, world, 0).json()
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), who=1)
    assert code(r) == "CHALLENGE_INVALID" and attempts(conn) == []


def test_nonce_expired(client, auth, world, engine, conn):
    ch = challenge(client, auth, world).json()
    conn.execute("UPDATE challenges SET expires_at = now() - interval '1 second'")
    assert code(checkin(client, auth, world, ch, set_frames(engine, ch["action"]))) == "CHALLENGE_INVALID"


def test_concurrent_same_nonce(client, auth, world, engine, conn):
    """Review Focus 1: hai request cùng nonce chạy song song → đúng một lượt được xử lý."""
    from app.main import app
    ch = challenge(client, auth, world).json()
    frames = set_frames(engine, ch["action"])
    slow = engine.analyze

    def analyze(*a, **k):
        time.sleep(0.3)  # giữ transaction đầu đủ lâu để request sau chen vào
        return slow(*a, **k)

    engine.analyze = analyze
    statuses = []
    barrier = threading.Barrier(2)

    def go():
        with TestClient(app) as c:
            barrier.wait()
            statuses.append(checkin(client, auth, world, ch, frames, c=c).status_code)

    threads = [threading.Thread(target=go) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(statuses) == [200, 409]
    assert len(attempts(conn)) == 1


def test_session_expired_between(client, auth, world, engine, conn):
    """Review Focus 2: xin thử thách lúc còn hạn, gửi sau khi hết hạn → 409, không ghi lượt."""
    ch = challenge(client, auth, world).json()
    conn.execute("UPDATE attendance_sessions SET expires_at = now() - interval '5 seconds'")
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]))
    assert r.status_code == 409 and code(r) == "SESSION_CLOSED" and attempts(conn) == []
    assert record(conn, world)["status"] == "absent"


# ---- Dữ liệu vào ----

@pytest.mark.parametrize("bad", [[], [{"lat": 200, "lng": 105, "acc": 5, "ts": 0}],
                                 [{"lat": 21, "lng": 105, "acc": 0, "ts": 0}],
                                 [{"lat": "NaN", "lng": 105, "acc": 5, "ts": 0}]])
def test_gps_garbage_422(client, auth, world, engine, conn, bad):
    """Review Focus 3."""
    ch = challenge(client, auth, world).json()
    r = checkin(client, auth, world, ch, set_frames(engine, ch["action"]), gps_samples=bad)
    assert r.status_code == 422 and code(r) == "VALIDATION_ERROR" and attempts(conn) == []


def test_meta_not_json(client, auth, world):
    files = [("frames", (f"{i}.jpg", b"x", "image/jpeg")) for i in range(5)]
    r = client.post(f"/sessions/{world['sid']}/checkin", headers=auth(world["students"][0]),
                    data={"meta": "khong phai json"}, files=files)
    assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"


def test_payload_too_large(client, auth, world):
    """Review Focus 4."""
    files = [("frames", ("big.jpg", b"x" * (3_200_000), "image/jpeg"))]
    r = client.post(f"/sessions/{world['sid']}/checkin", headers=auth(world["students"][0]),
                    data={"meta": "{}"}, files=files)
    assert r.status_code == 413 and code(r) == "PAYLOAD_TOO_LARGE"


@pytest.mark.parametrize("n", [4, 9])
def test_frame_count(client, auth, world, engine, conn, n):
    ch = challenge(client, auth, world).json()
    r = checkin(client, auth, world, ch, [b"f0"] * n)
    assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"


def test_broken_frames_no_500(client, auth, world, engine, conn):
    """Review Focus 4: khung hình hỏng → FACE_NOT_FOUND, không lỗi 500."""
    ch = challenge(client, auth, world).json()
    r = checkin(client, auth, world, ch, [b"", b"notjpeg", b"\xff\xd8", b"x", b"y"])
    assert r.status_code == 200 and r.json()["reason"]["code"] == "FACE_NOT_FOUND"


# ---- Bằng chứng và quyền riêng tư ----

def test_suspicious_saves_evidence(client, auth, world, engine, conn):
    run(client, auth, world, engine, d_m=50)
    a = attempts(conn)[0]
    assert a["evidence_path"] == f"evidence/{a['id']}.jpg"
    assert crypto.load_blob(a["evidence_path"]).startswith(b"f")  # khung nét nhất, đã mã hóa trên đĩa
    left = a["evidence_expires_at"] - a["received_at"]
    assert timedelta(days=29, hours=23) < left <= timedelta(days=30)
    run(client, auth, world, engine, who=1, device="dev-2")  # lượt đạt không lưu ảnh
    assert attempts(conn)[1]["evidence_path"] is None


def test_student_response_hides_scores(client, auth, world, engine):
    for kw in ({}, {"d_m": 50}, {"emb": vec(0.2)}):
        body = run(client, auth, world, engine, who=0 if not kw else 1, device="dev-0" if not kw else "dev-1", **kw).json()
        assert set(body) == {"result", "record_status", "reason", "attempts_left"}
        assert not body["reason"] or set(body["reason"]) == {"code", "message"}


# ---- Hàm thuần ----

def face(status="pass"):
    return FaceResult(status, None, 0.9, 0.9, True, 0)


def test_collect_flags():
    s = [Sample(21, 105, 10, 0), Sample(21, 105, 10, 1000)]
    assert collect_flags(face(), "ok", s, False, False, False) == []
    assert collect_flags(face("borderline"), "drift", s, True, True, True) == [
        "LOCATION_DRIFT", "FACE_BORDERLINE", "LOCATION_JUMP", "SHARED_DEVICE", "ROOM_TOKEN_BURST"]
    mock = [Sample(21, 105, 10, 0, True)]
    assert collect_flags(face(), "ok", mock, False, False, False) == ["MOCK_LOCATION"]
    jump = [Sample(21, 105, 10, 0), Sample(21 + 100 / M_PER_DEG_LAT, 105, 10, 1000)]
    assert collect_flags(face(), "ok", jump, False, False, False) == ["LOCATION_JUMP"]
    assert not math.isnan(0)
