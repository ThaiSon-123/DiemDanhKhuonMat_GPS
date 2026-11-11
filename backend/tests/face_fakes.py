"""Engine khuôn mặt giả cho test: trả FrameAnalysis soạn sẵn theo nội dung ảnh (dùng lại ở Task 9, 15)."""
import math

import numpy as np

from app.config import FaceCfg
from app.services.face.types import FrameAnalysis

DIM = 8
CFG = FaceCfg(model_name="test_model", accept_threshold=0.5, suspect_threshold=0.4, antispoof_threshold=0.5,
              yaw_sign=1, yaw_threshold=0.25, min_brightness=60, min_sharpness=50, min_face_px=100)


def vec(cos_to_e0: float, axis: int = 1) -> np.ndarray:
    """Vector đơn vị có cosine với e0 đúng bằng cos_to_e0 (phần còn lại nằm trên trục `axis`)."""
    v = np.zeros(DIM, dtype=np.float32)
    v[0] = cos_to_e0
    v[axis] = math.sqrt(max(0.0, 1 - cos_to_e0 ** 2))
    return v


E0 = vec(1.0)  # "mẫu" của sinh viên trong test


def fa(**kw) -> FrameAnalysis:
    """Một khung hình đạt mọi kiểm tra, ghi đè trường cần thử."""
    base = dict(face_count=1, face_width_px=150.0, brightness=120.0, sharpness=100.0, yaw_proxy=0.0,
                embedding=E0, spoof_score=0.9)
    return FrameAnalysis(**{**base, **kw})


NO_FACE = FrameAnalysis(face_count=0, face_width_px=0.0, brightness=0.0, sharpness=0.0, yaw_proxy=None,
                        embedding=None, spoof_score=None)


class FakeEngine:
    def __init__(self, results: dict[bytes, FrameAnalysis]):
        self.results = results
        self.calls: list[tuple[bytes, bool, bool]] = []

    def analyze(self, jpeg: bytes, *, embed: bool, spoof: bool) -> FrameAnalysis:
        self.calls.append((jpeg, embed, spoof))
        return self.results.get(jpeg, NO_FACE)  # ảnh lạ / hỏng: không thấy mặt, như engine thật


def frames(*analyses: FrameAnalysis) -> tuple[list[bytes], FakeEngine]:
    """Tạo danh sách "ảnh" b"f0", b"f1"... kèm engine trả lần lượt các phân tích."""
    keys = [f"f{i}".encode() for i in range(len(analyses))]
    return keys, FakeEngine(dict(zip(keys, analyses)))
