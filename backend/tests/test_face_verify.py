import numpy as np
import pytest

from app.services.face.verify import build_template, verify_checkin
from face_fakes import CFG as cfg
from face_fakes import E0, FakeEngine, fa, frames, vec

TURN_LEFT = [0.0, -0.1, -0.3, -0.3]  # nhìn thẳng rồi quay trái


def run(*analyses, action="turn_left"):
    keys, engine = frames(*analyses)
    return verify_checkin(keys, action, E0, engine, cfg)


def test_verify_pass():
    r = run(*(fa(yaw_proxy=y, sharpness=100 + i) for i, y in enumerate(TURN_LEFT)))
    assert (r.status, r.reason, r.action_ok) == ("pass", None, True)
    assert r.face_score == pytest.approx(1.0) and r.liveness_score == pytest.approx(0.9)
    assert r.best_frame == 3  # khung nét nhất


def test_verify_borderline_is_not_fail():
    embs = [vec(0.45), vec(0.46), vec(0.44), vec(0.45)]
    r = run(*(fa(yaw_proxy=y, embedding=e) for y, e in zip(TURN_LEFT, embs)))
    assert (r.status, r.reason) == ("borderline", None)


def test_verify_spoof_detected_uses_three_sharpest():
    # khung mờ nhất có spoof thấp nhưng không thuộc 3 khung nét nhất → bỏ qua
    a = [fa(yaw_proxy=0.0, sharpness=60, spoof_score=0.1), fa(yaw_proxy=-0.1, sharpness=90),
         fa(yaw_proxy=-0.3, sharpness=95), fa(yaw_proxy=-0.3, sharpness=99)]
    assert run(*a).status == "pass"
    a[3] = fa(yaw_proxy=-0.3, sharpness=99, spoof_score=0.3)
    r = run(*a)
    assert (r.status, r.reason) == ("fail", "SPOOF_DETECTED") and r.liveness_score == pytest.approx(0.3)


def test_verify_action_not_detected():
    r = run(*(fa(yaw_proxy=y) for y in [0.0, 0.1, 0.3, 0.3]))  # quay phải trong khi yêu cầu quay trái
    assert (r.status, r.reason, r.action_ok) == ("fail", "ACTION_NOT_DETECTED", False)


def test_verify_mismatch():
    r = run(*(fa(yaw_proxy=y, embedding=vec(0.2)) for y in TURN_LEFT))
    assert (r.status, r.reason) == ("fail", "FACE_MISMATCH") and r.face_score == pytest.approx(0.2)


def test_verify_one_foreign_frame_fails():
    # ghép khung của người khác (làm hành động) với khung của chính chủ: nhỏ nhất < ngưỡng nghi ngờ
    embs = [E0, E0, vec(0.1), E0]
    r = run(*(fa(yaw_proxy=y, embedding=e) for y, e in zip(TURN_LEFT, embs)))
    assert (r.status, r.reason) == ("fail", "FACE_MISMATCH")


def test_verify_needs_3_quality_frames():
    r = run(fa(yaw_proxy=0.0), fa(yaw_proxy=-0.3), fa(brightness=10), fa(brightness=20), fa(sharpness=1))
    assert (r.status, r.reason) == ("fail", "LOW_LIGHT")  # lỗi chất lượng xuất hiện nhiều nhất
    assert r.face_score is None and r.best_frame == 0  # khung nét nhất trong các khung đạt (hòa thì lấy khung đầu)


def test_verify_garbage_frames_no_exception():
    engine = FakeEngine({})
    r = verify_checkin([b"", b"notjpeg", b"\xff\xd8garbage"], "turn_left", E0, engine, cfg)
    assert (r.status, r.reason, r.best_frame) == ("fail", "FACE_NOT_FOUND", None)


def test_verify_skips_spoof_and_embedding_when_quality_fails():
    keys, engine = frames(fa(face_count=0), fa(face_count=0), fa(face_count=0))
    verify_checkin(keys, "turn_left", E0, engine, cfg)
    assert all(not embed and not spoof for _, embed, spoof in engine.calls)


def test_build_template_returns_unit_vector():
    keys, engine = frames(fa(embedding=vec(0.95, 1)), fa(embedding=vec(0.95, 2)), fa(embedding=vec(0.95, 3)))
    t, issues = build_template(keys, engine, cfg)
    assert issues == []
    assert t.dtype == np.float32 and np.linalg.norm(t) == pytest.approx(1.0, abs=1e-6)
    assert float(t @ E0) > 0.95  # trung bình kéo về hướng chung


def test_build_template_inconsistent_photo():
    keys, engine = frames(fa(embedding=E0), fa(embedding=vec(0.98)), fa(embedding=vec(0.1)))
    t, issues = build_template(keys, engine, cfg)
    assert t is None and issues == [{"index": 2, "reason": "INCONSISTENT_FACE"}]


def test_build_template_quality_and_spoof_issues():
    keys, engine = frames(fa(), fa(sharpness=5), fa(spoof_score=0.2), fa())
    t, issues = build_template(keys, engine, cfg)
    assert t is None and issues == [{"index": 1, "reason": "BLURRY"}, {"index": 2, "reason": "SPOOF_DETECTED"}]


def test_build_template_garbage_photo():
    t, issues = build_template([b"x", b"y", b"z"], FakeEngine({}), cfg)
    assert t is None and [i["reason"] for i in issues] == ["FACE_NOT_FOUND"] * 3
