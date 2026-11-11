"""Kiểu dữ liệu chung giữa engine khuôn mặt (Task 8, ONNX) và logic quyết định (Task 7)."""
from dataclasses import dataclass
from typing import Literal, Protocol

import numpy as np


@dataclass(frozen=True)
class FrameAnalysis:
    face_count: int                 # 0 khi giải mã ảnh lỗi
    face_width_px: float
    brightness: float               # trung bình xám vùng mặt, 0-255
    sharpness: float                # phương sai Laplacian vùng mặt
    yaw_proxy: float | None         # âm/dương theo hướng quay; |giá trị| lớn = quay nhiều
    embedding: np.ndarray | None    # đã chuẩn hóa L2; None khi không yêu cầu hoặc không có mặt
    spoof_score: float | None       # xác suất người thật 0-1; None khi không yêu cầu


class FaceEngine(Protocol):
    def analyze(self, jpeg: bytes, *, embed: bool, spoof: bool) -> FrameAnalysis:
        """Không bao giờ ném lỗi vì ảnh hỏng: trả face_count=0."""
        ...


@dataclass(frozen=True)
class FaceResult:
    status: Literal["pass", "borderline", "fail"]
    reason: str | None              # mã lý do mục 9.5 khi fail
    face_score: float | None        # trung vị cosine trên các khung đạt chất lượng
    liveness_score: float | None    # điểm anti-spoofing thấp nhất của 3 khung nét nhất
    action_ok: bool | None
    best_frame: int | None          # chỉ số khung nét nhất có mặt (để lưu ảnh bằng chứng)
