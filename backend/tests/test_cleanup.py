import secrets
from datetime import datetime, timedelta, timezone

import pytest

from app import crypto
from app.jobs.cleanup import run

NOW = datetime(2026, 11, 12, 3, 0, tzinfo=timezone.utc)


@pytest.fixture
def sess(conn, make_user, make_class):
    gv = make_user("lecturer")
    st = make_user("student")
    c = make_class(gv["id"])
    s = conn.execute("INSERT INTO attendance_sessions (class_id, opened_by, center_lat, center_lng, center_accuracy_m, "
                     "base_radius_m, room_secret, expires_at) VALUES (%s, %s, 21, 105, 8, 20, %s, now()) RETURNING id",
                     (c["id"], gv["id"], b"k" * 32)).fetchone()["id"]
    return {"sid": s, "uid": st["id"]}


def challenge(conn, sess, created):
    return conn.execute("INSERT INTO challenges (session_id, student_id, nonce, action, created_at, expires_at) "
                        "VALUES (%s, %s, %s, 'turn_left', %s, %s) RETURNING id",
                        (sess["sid"], sess["uid"], secrets.token_hex(8), created, created)).fetchone()["id"]


def attempt(conn, sess, expires, with_file=True):
    ch = challenge(conn, sess, NOW)
    a = conn.execute("INSERT INTO checkin_attempts (session_id, student_id, challenge_id, gps_samples, result) "
                     "VALUES (%s, %s, %s, '[]', 'suspicious') RETURNING id", (sess["sid"], sess["uid"], ch)).fetchone()["id"]
    rel = f"evidence/{a}.jpg"
    if with_file:
        crypto.save_blob(rel, b"jpeg")
    conn.execute("UPDATE checkin_attempts SET evidence_path = %s, evidence_expires_at = %s WHERE id = %s", (rel, expires, a))
    return a, rel


def test_deletes_expired_evidence(conn, sess):
    old, old_rel = attempt(conn, sess, NOW - timedelta(seconds=1))
    new, new_rel = attempt(conn, sess, NOW + timedelta(days=3))
    assert run(conn, NOW)["evidence"] == 1
    assert not crypto.storage_path(old_rel).exists() and crypto.storage_path(new_rel).exists()
    paths = {r["id"]: r["evidence_path"] for r in conn.execute("SELECT id, evidence_path FROM checkin_attempts")}
    assert paths == {old: None, new: new_rel}


def test_deletes_photos_of_reviewed(conn, sess):
    ids = {}
    for status in ("approved", "rejected", "pending"):
        rel = f"faces/t-{status}"
        crypto.save_blob(f"{rel}/0.jpg", b"x")
        uid = sess["uid"] if status != "approved" else conn.execute(
            "INSERT INTO users (role, username, full_name, password_hash, student_code) VALUES "
            "('student', 'sv.x', 'X', 'h', 'SVX') RETURNING id").fetchone()["id"]
        ids[status] = conn.execute("INSERT INTO face_templates (student_id, model_name, status, photos_path) "
                                   "VALUES (%s, 'm', %s, %s) RETURNING id", (uid, status, rel)).fetchone()["id"]
    assert run(conn, NOW)["photos"] == 2
    left = {r["status"]: r["photos_path"] for r in conn.execute("SELECT status, photos_path FROM face_templates")}
    assert left == {"approved": None, "rejected": None, "pending": "faces/t-pending"}
    assert not crypto.storage_path("faces/t-approved").exists() and crypto.storage_path("faces/t-pending").exists()


def test_deletes_old_challenges_without_attempt(conn, sess):
    old = challenge(conn, sess, NOW - timedelta(days=2))
    fresh = challenge(conn, sess, NOW - timedelta(hours=2))
    attempt(conn, sess, NOW + timedelta(days=1))  # thử thách có lượt thử: giữ
    conn.execute("UPDATE challenges SET created_at = %s WHERE id NOT IN (%s, %s)", (NOW - timedelta(days=5), old, fresh))
    assert run(conn, NOW)["challenges"] == 1
    ids = {r["id"] for r in conn.execute("SELECT id FROM challenges")}
    assert old not in ids and fresh in ids and len(ids) == 2


def test_missing_file_is_not_error(conn, sess):
    attempt(conn, sess, NOW - timedelta(days=1), with_file=False)
    assert run(conn, NOW)["evidence"] == 1
