"""Engine khuôn mặt dùng chung cho cả server: nạp mô hình một lần, giới hạn số lượt suy luận chạy cùng lúc."""
import os
import threading
from collections.abc import Callable
from functools import lru_cache
from typing import TypeVar

from app.config import BASE_DIR, get_settings
from app.services.face.types import FaceEngine

T = TypeVar("T")

# ponytail: một semaphore cho cả tiến trình (deploy 1 worker); nhiều worker thì mỗi worker giữ mô hình riêng trong RAM.
_slots = threading.BoundedSemaphore(os.cpu_count() or 2)


@lru_cache
def get_engine() -> FaceEngine:
    """FastAPI dependency; test thay bằng FakeEngine qua app.dependency_overrides."""
    from app.services.face.onnx_engine import OnnxFaceEngine  # nạp onnxruntime/opencv chỉ khi thật sự cần

    cfg = get_settings().face
    return OnnxFaceEngine(BASE_DIR / "models", embed_model=cfg.embed_file, threads=cfg.threads)


def infer(fn: Callable[..., T], *args, **kwargs) -> T:
    """Chạy một lượt suy luận khi còn chỗ; nhiều sinh viên điểm danh cùng lúc thì xếp hàng thay vì làm nghẽn CPU."""
    with _slots:
        return fn(*args, **kwargs)
