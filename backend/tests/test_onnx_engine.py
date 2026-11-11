"""Engine ONNX với mô hình thật. Tự bỏ qua khi thiếu file mô hình hoặc ảnh mẫu (cả hai không có trong git).

Ảnh mẫu trong tests/fixtures/faces/ (xem models/README.md để tải lại):
  a1.jpg  ảnh chân dung người A      a2.jpg  cùng người A, xoay nghiêng và đổi sáng
  b1.jpg  người B                    blank.jpg  ảnh trơn không có mặt
"""
import time
from pathlib import Path

import cv2
import numpy as np
import pytest

from app.config import BASE_DIR

pytestmark = pytest.mark.models
FIX = Path(__file__).parent / "fixtures" / "faces"
MODELS = BASE_DIR / "models"


def load(name: str) -> bytes:
    p = FIX / f"{name}.jpg"
    if not p.exists():
        pytest.skip(f"thiếu ảnh mẫu {p.name}")
    return p.read_bytes()


@pytest.fixture(scope="module")
def engine():
    needed = ["face_detection_yunet_2023mar.onnx", "w600k_r50.onnx", "MiniFASNetV2.onnx"]
    if not all((MODELS / f).exists() for f in needed):
        pytest.skip("thiếu file mô hình .onnx")
    from app.services.face.onnx_engine import OnnxFaceEngine
    return OnnxFaceEngine(MODELS)


def test_same_person_scores_higher(engine):
    a1, a2, b1 = (engine.analyze(load(n), embed=True, spoof=False) for n in ("a1", "a2", "b1"))
    assert a1.face_count == 1 and a1.face_width_px > 100
    assert abs(float(np.linalg.norm(a1.embedding)) - 1) < 1e-5
    assert float(a1.embedding @ a2.embedding) > float(a1.embedding @ b1.embedding) + 0.2


def test_flags_control_heavy_models(engine):
    a = engine.analyze(load("a1"), embed=False, spoof=False)
    assert a.face_count == 1 and a.embedding is None and a.spoof_score is None
    assert a.yaw_proxy is not None and a.brightness > 0 and a.sharpness > 0


def test_mirror_flips_yaw_sign(engine):
    img = cv2.imdecode(np.frombuffer(load("a1"), np.uint8), cv2.IMREAD_COLOR)
    a = engine.analyze(load("a1"), embed=False, spoof=False)
    m = engine.analyze(cv2.imencode(".jpg", cv2.flip(img, 1))[1].tobytes(), embed=False, spoof=False)
    assert a.yaw_proxy * m.yaw_proxy < 0


def test_blank_and_garbage(engine):
    assert engine.analyze(load("blank"), embed=True, spoof=True).face_count == 0
    for bad in (b"", b"not a jpeg", b"\xff\xd8\xff\xe0truncated"):
        r = engine.analyze(bad, embed=True, spoof=True)
        assert (r.face_count, r.embedding, r.spoof_score) == (0, None, None)


def test_huge_image_is_downscaled(engine):
    img = cv2.imdecode(np.frombuffer(load("a1"), np.uint8), cv2.IMREAD_COLOR)
    big = cv2.resize(img, (4000, 4000))  # mặt vẫn rõ sau khi thu nhỏ về 1280
    t = time.perf_counter()
    r = engine.analyze(cv2.imencode(".jpg", big)[1].tobytes(), embed=True, spoof=True)
    assert r.face_count == 1 and time.perf_counter() - t < 2


def test_spoof_score_range(engine):
    a = engine.analyze(load("a1"), embed=False, spoof=True)
    assert 0 <= a.spoof_score <= 1
