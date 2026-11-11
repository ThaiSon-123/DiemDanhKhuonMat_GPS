import os
from pathlib import Path

import numpy as np
import pytest

from app import crypto
from app.config import get_settings
from app.services.face.runtime import get_engine
from face_fakes import E0, FakeEngine, fa, vec

GOOD = {b"p0": fa(embedding=vec(0.97, 1)), b"p1": fa(embedding=vec(0.97, 2)), b"p2": fa(embedding=vec(0.97, 3))}


def code(r):
    return r.json()["error"]["code"]


@pytest.fixture
def engine(client):
    from app.main import app
    eng = FakeEngine(dict(GOOD))
    app.dependency_overrides[get_engine] = lambda: eng
    yield eng
    app.dependency_overrides.pop(get_engine, None)


@pytest.fixture
def student(make_user, conn):
    s = make_user("student")
    conn.execute("INSERT INTO consents (user_id, version) VALUES (%s, %s)",
                 (s["id"], get_settings().consent.current_version))
    return s


def enroll(client, headers, photos=(b"p0", b"p1", b"p2")):
    files = [("photos", (f"{i}.jpg", p, "image/jpeg")) for i, p in enumerate(photos)]
    return client.post("/faces/enroll", headers=headers, files=files)


def storage(rel: str) -> Path:
    return Path(os.environ["STORAGE_DIR"]) / rel


def add_template(conn, student_id, status, photos=False):
    emb = crypto.encrypt(crypto.embedding_to_bytes(E0)) if status in ("approved", "pending") else None
    row = conn.execute(
        "INSERT INTO face_templates (student_id, model_name, status, embedding_enc) VALUES (%s, %s, %s, %s) RETURNING id",
        (student_id, get_settings().face.model_name, status, emb)).fetchone()
    if photos:
        rel = f"faces/{row['id']}"
        crypto.save_blob(f"{rel}/0.jpg", b"JPEGDATA")
        conn.execute("UPDATE face_templates SET photos_path = %s WHERE id = %s", (rel, row["id"]))
    return row["id"]


# ---- Đăng ký ----

def test_enroll_requires_consent(client, engine, make_user, auth):
    r = enroll(client, auth(make_user("student")))
    assert r.status_code == 409 and code(r) == "CONSENT_REQUIRED"


def test_enroll_only_students(client, engine, make_user, auth):
    assert code(enroll(client, auth(make_user("lecturer")))) == "FORBIDDEN"


@pytest.mark.parametrize("n", [2, 6])
def test_enroll_photo_count(client, engine, student, auth, n):
    r = enroll(client, auth(student), photos=[b"p0"] * n)
    assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"


def test_enroll_rejected_photos(client, engine, student, auth, conn):
    engine.results[b"blur"] = fa(sharpness=1)
    r = enroll(client, auth(student), photos=[b"p0", b"blur", b"rac"])
    assert r.status_code == 422 and code(r) == "ENROLL_REJECTED"
    assert r.json()["error"]["details"]["photos"] == [{"index": 1, "reason": "BLURRY"},
                                                      {"index": 2, "reason": "FACE_NOT_FOUND"}]
    assert conn.execute("SELECT count(*) c FROM face_templates").fetchone()["c"] == 0


def test_enroll_creates_pending_with_encrypted_photos(client, engine, student, auth, conn):
    r = enroll(client, auth(student))
    assert r.status_code == 201 and r.json()["status"] == "pending"
    row = conn.execute("SELECT * FROM face_templates WHERE id = %s", (r.json()["template_id"],)).fetchone()
    assert row["status"] == "pending" and row["model_name"] == get_settings().face.model_name
    emb = crypto.embedding_from_bytes(crypto.decrypt(row["embedding_enc"]))
    assert abs(float(np.linalg.norm(emb)) - 1) < 1e-5
    files = sorted(storage(row["photos_path"]).iterdir())
    assert len(files) == 3 and files[0].read_bytes() != b"p0"           # trên đĩa là bản mã hóa
    assert crypto.load_blob(f"{row['photos_path']}/0.jpg") == b"p0"
    assert client.get("/me", headers=auth(student)).json()["face"]["status"] == "pending"


def test_second_pending_conflict(client, engine, student, auth):
    assert enroll(client, auth(student)).status_code == 201
    r = enroll(client, auth(student))
    assert r.status_code == 409 and code(r) == "FACE_PENDING_EXISTS"


# ---- Duyệt ----

def _lecturer_with_student(make_user, make_class, enroll_fn, student):
    gv = make_user("lecturer")
    enroll_fn(make_class(gv["id"])["id"], student["id"])
    return gv


def test_lecturer_sees_only_own_class_pending(client, engine, student, make_user, make_class, enroll, auth, conn):
    gv = _lecturer_with_student(make_user, make_class, enroll, student)
    other = make_user("lecturer")
    tid = add_template(conn, student["id"], "pending", photos=True)
    items = client.get("/faces/pending", headers=auth(gv)).json()
    assert [i["id"] for i in items] == [tid] and items[0]["full_name"] == student["full_name"]
    assert items[0]["is_update"] is False and items[0]["photo_count"] == 1
    assert client.get("/faces/pending", headers=auth(other)).json() == []
    assert len(client.get("/faces/pending", headers=auth(make_user("admin"))).json()) == 1
    assert code(client.get("/faces/pending", headers=auth(student))) == "FORBIDDEN"


def test_lecturer_review_other_class_404(client, student, make_user, auth, conn):
    tid = add_template(conn, student["id"], "pending", photos=True)
    other = make_user("lecturer")
    r = client.post(f"/faces/{tid}/review", headers=auth(other), json={"decision": "approve"})
    assert r.status_code == 404 and code(r) == "NOT_FOUND"
    assert client.get(f"/faces/{tid}/photos", headers=auth(other)).status_code == 404


def test_view_photos_writes_audit(client, student, make_user, auth, conn):
    tid = add_template(conn, student["id"], "pending", photos=True)
    admin = make_user("admin")
    r = client.get(f"/faces/{tid}/photos", headers=auth(admin))
    assert r.status_code == 200 and r.json()["photos"] == ["data:image/jpeg;base64,SlBFR0RBVEE="]
    log = conn.execute("SELECT actor_id, action, target FROM audit_log").fetchone()
    assert log == {"actor_id": admin["id"], "action": "face.photos.view", "target": f"face_templates:{tid}"}


def test_approve_deletes_photos_and_revokes_old(client, student, make_user, auth, conn):
    old = add_template(conn, student["id"], "approved")
    new = add_template(conn, student["id"], "pending", photos=True)
    admin = make_user("admin")
    r = client.post(f"/faces/{new}/review", headers=auth(admin), json={"decision": "approve"})
    assert r.status_code == 200 and r.json()["status"] == "approved"
    rows = {x["id"]: x for x in conn.execute("SELECT * FROM face_templates").fetchall()}
    assert rows[old]["status"] == "revoked" and rows[old]["embedding_enc"] is None
    assert rows[new]["status"] == "approved" and rows[new]["photos_path"] is None
    assert rows[new]["reviewed_by"] == admin["id"] and rows[new]["reviewed_at"] is not None
    assert not storage(f"faces/{new}").exists()
    assert conn.execute("SELECT action FROM audit_log").fetchone()["action"] == "face.review"
    again = client.post(f"/faces/{new}/review", headers=auth(admin), json={"decision": "approve"})
    assert again.status_code == 404  # đã duyệt rồi thì không còn trong hàng chờ


def test_reject_requires_reason(client, student, make_user, auth, conn):
    tid = add_template(conn, student["id"], "pending", photos=True)
    h = auth(make_user("admin"))
    for body in ({"decision": "reject"}, {"decision": "reject", "reason": "  "}):
        r = client.post(f"/faces/{tid}/review", headers=h, json=body)
        assert r.status_code == 422 and code(r) == "VALIDATION_ERROR"
    r = client.post(f"/faces/{tid}/review", headers=h, json={"decision": "reject", "reason": "Ảnh 2 ngược sáng"})
    assert r.status_code == 200
    row = conn.execute("SELECT * FROM face_templates WHERE id = %s", (tid,)).fetchone()
    assert (row["status"], row["reject_reason"], row["embedding_enc"], row["photos_path"]) == \
           ("rejected", "Ảnh 2 ngược sáng", None, None)
    face = client.get("/me", headers=auth(student)).json()["face"]
    assert face["status"] == "rejected" and face["reject_reason"] == "Ảnh 2 ngược sáng"


# ---- Xóa ----

def test_delete_my_face(client, student, auth, conn):
    add_template(conn, student["id"], "approved")
    tid = add_template(conn, student["id"], "pending", photos=True)
    assert client.delete("/me/face", headers=auth(student)).status_code == 204
    rows = conn.execute("SELECT status, embedding_enc, photos_path FROM face_templates").fetchall()
    assert all(r == {"status": "revoked", "embedding_enc": None, "photos_path": None} for r in rows)
    assert not storage(f"faces/{tid}").exists()
    log = conn.execute("SELECT actor_id, action FROM audit_log").fetchone()
    assert log == {"actor_id": student["id"], "action": "face.delete"}


def test_admin_delete_face_and_deactivate(client, student, make_user, auth, conn):
    h = auth(make_user("admin"))
    tid = add_template(conn, student["id"], "pending", photos=True)
    assert client.delete(f"/admin/users/{student['id']}/face", headers=h).status_code == 204
    assert not storage(f"faces/{tid}").exists()
    add_template(conn, student["id"], "approved")
    client.post(f"/admin/users/{student['id']}/deactivate", headers=h)
    assert conn.execute("SELECT count(*) c FROM face_templates WHERE status <> 'revoked'").fetchone()["c"] == 0


# ---- Mẫu cho điểm danh ----

def test_approved_template(conn, student):
    from app.face_data import approved_template
    model = get_settings().face.model_name
    assert approved_template(conn, student["id"], model) is None
    add_template(conn, student["id"], "pending")
    assert approved_template(conn, student["id"], model) is None
    add_template(conn, student["id"], "approved")
    assert np.allclose(approved_template(conn, student["id"], model), E0)
    assert approved_template(conn, student["id"], "mo_hinh_khac") is None
