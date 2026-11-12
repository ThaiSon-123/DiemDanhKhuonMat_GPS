"""Cấu hình nghiệp vụ đọc từ config.yaml. Bí mật (DATABASE_URL, JWT_SECRET, DATA_KEY, ...) đọc thẳng từ biến môi trường ở nơi dùng."""
import os
from functools import lru_cache
from pathlib import Path

import yaml
from pydantic import BaseModel

BASE_DIR = Path(__file__).resolve().parent.parent


class FaceCfg(BaseModel):
    model_name: str            # tên ghi kèm mỗi mẫu; đổi thì mẫu cũ thành không hợp lệ
    embed_file: str = "w600k_r50.onnx"
    threads: int = 2           # luồng onnxruntime cho mỗi lượt suy luận
    accept_threshold: float
    suspect_threshold: float
    antispoof_threshold: float
    yaw_sign: int = 1
    yaw_threshold: float = 0.25
    min_brightness: float = 60
    min_sharpness: float = 50
    min_face_px: int = 100
    actions: list[str] = ["turn_left", "turn_right"]


class GpsCfg(BaseModel):
    default_r0_m: float = 20
    r0_range_m: tuple[float, float] = (10, 50)
    max_acc_lecturer_m: float = 20
    max_acc_student_m: float = 30
    min_samples_lecturer: int = 5
    min_samples_student: int = 3
    max_span_s: float = 20
    max_speed_mps: float = 30


class SessionCfg(BaseModel):
    default_duration_min: int = 10
    max_attempts: int = 5
    challenge_ttl_s: int = 60
    room_token_window_s: int = 30


class RetentionCfg(BaseModel):
    evidence_days: int = 30


class AuthCfg(BaseModel):
    access_minutes: int = 15
    refresh_days: int = 7
    max_failures: int = 10
    lock_minutes: int = 15


class ConsentCfg(BaseModel):
    current_version: str = "v1"


class Settings(BaseModel):
    auth: AuthCfg = AuthCfg()
    consent: ConsentCfg = ConsentCfg()
    face: FaceCfg
    gps: GpsCfg
    session: SessionCfg
    retention: RetentionCfg
    campus_polygon_file: str


@lru_cache
def get_settings() -> Settings:
    # CONFIG_FILE=config.dev.yaml để thử trên PC (GPS qua Wi-Fi kém, chưa có đa giác khuôn viên thật).
    path = BASE_DIR / os.environ.get("CONFIG_FILE", "config.yaml")
    return Settings(**yaml.safe_load(path.read_text(encoding="utf-8")))
