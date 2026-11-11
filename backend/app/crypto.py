"""Mã hóa AES-GCM cho embedding và ảnh; file luôn mã hóa, nằm dưới STORAGE_DIR (đặc tả mục 8)."""
import base64
import os
import shutil
from functools import lru_cache
from pathlib import Path

import numpy as np
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

NONCE_BYTES = 12


@lru_cache
def _aead() -> AESGCM:
    key = base64.b64decode(os.environ["DATA_KEY"])
    if len(key) != 32:
        raise RuntimeError("DATA_KEY phải là 32 byte mã hóa base64")
    return AESGCM(key)


def encrypt(data: bytes) -> bytes:
    """nonce 12 byte ‖ ciphertext+tag."""
    nonce = os.urandom(NONCE_BYTES)
    return nonce + _aead().encrypt(nonce, data, None)


def decrypt(blob: bytes) -> bytes:
    return _aead().decrypt(blob[:NONCE_BYTES], blob[NONCE_BYTES:], None)


def storage_path(rel_path: str) -> Path:
    """Đường dẫn thật của rel_path; chặn mọi đường dẫn thoát khỏi STORAGE_DIR."""
    root = Path(os.environ["STORAGE_DIR"]).resolve()
    p = Path(rel_path)
    # ":" và "\" bị chặn để kết quả giống nhau trên Windows (máy dev) và Linux (VPS).
    if not rel_path or ":" in rel_path or "\\" in rel_path or p.is_absolute() or ".." in p.parts:
        raise ValueError(f"Đường dẫn lưu trữ không hợp lệ: {rel_path!r}")
    full = (root / p).resolve()
    if full == root or root not in full.parents:
        raise ValueError(f"Đường dẫn lưu trữ không hợp lệ: {rel_path!r}")
    return full


def save_blob(rel_path: str, data: bytes) -> str:
    full = storage_path(rel_path)
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_bytes(encrypt(data))
    return rel_path


def load_blob(rel_path: str) -> bytes:
    return decrypt(storage_path(rel_path).read_bytes())


def delete_blob(rel_path: str) -> None:
    storage_path(rel_path).unlink(missing_ok=True)


def delete_tree(rel_path: str) -> None:
    """Xóa cả thư mục (vd ảnh đăng ký của một mẫu); không lỗi nếu đã mất."""
    shutil.rmtree(storage_path(rel_path), ignore_errors=True)


def embedding_to_bytes(v: np.ndarray) -> bytes:
    return np.asarray(v, dtype=np.float32).tobytes()


def embedding_from_bytes(b: bytes) -> np.ndarray:
    return np.frombuffer(b, dtype=np.float32).copy()
