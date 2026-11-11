"""Các kiểm tra thuần trên kết quả phân tích khung hình (đặc tả mục 5.1, 5.4)."""
from statistics import median
from typing import Literal

import numpy as np

from app.config import FaceCfg
from app.services.face.types import FrameAnalysis

_DIRECTION = {"turn_left": -1, "turn_right": 1}


def quality_reason(a: FrameAnalysis, cfg: FaceCfg) -> str | None:
    """Mã lý do chất lượng đầu tiên không đạt, hoặc None nếu khung dùng được."""
    if a.face_count == 0 or (a.face_count == 1 and a.face_width_px < cfg.min_face_px):
        return "FACE_NOT_FOUND"
    if a.face_count > 1:
        return "MULTIPLE_FACES"
    if a.brightness < cfg.min_brightness:
        return "LOW_LIGHT"
    if a.sharpness < cfg.min_sharpness:
        return "BLURRY"
    return None


def action_done(yaws: list[float | None], action: str, cfg: FaceCfg) -> bool:
    """Đạt khi có một khung nhìn thẳng (|yaw| ≤ T/2) rồi sau đó một khung quay đúng hướng ≥ T.

    Quy ước: yaw * yaw_sign < 0 là quay sang trái của sinh viên; yaw_sign chốt ở Task 0 trên ảnh điện thoại thật.
    """
    if action not in _DIRECTION:
        raise ValueError(f"Hành động không hỗ trợ: {action}")
    t, d = cfg.yaw_threshold, _DIRECTION[action] * cfg.yaw_sign
    frontal_seen = False
    for y in yaws:
        if y is None:
            continue
        if frontal_seen and y * d >= t:
            return True
        if abs(y) <= t / 2:
            frontal_seen = True
    return False


def unit(v: np.ndarray) -> np.ndarray:
    """Chuẩn hóa L2 (vector 0 giữ nguyên)."""
    v = np.asarray(v, dtype=np.float32)
    n = float(np.linalg.norm(v))
    return v / n if n > 0 else v


def match_scores(embs: list[np.ndarray], template: np.ndarray) -> tuple[float, float]:
    """(trung vị, nhỏ nhất) cosine giữa từng khung và mẫu. So mọi khung để chặn ghép khung người khác."""
    t = unit(template)
    scores = [float(unit(e) @ t) for e in embs]
    return median(scores), min(scores)


def face_status(med: float, minimum: float, cfg: FaceCfg) -> Literal["pass", "borderline", "fail"]:
    """Hai ngưỡng (mục 5.4): một khung dưới ngưỡng nghi ngờ là không đạt; trung vị giữa hai ngưỡng là sát ngưỡng."""
    if minimum < cfg.suspect_threshold or med < cfg.suspect_threshold:
        return "fail"
    return "pass" if med >= cfg.accept_threshold else "borderline"
