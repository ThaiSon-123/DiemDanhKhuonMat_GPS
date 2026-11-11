"""Engine khuôn mặt ONNX chạy CPU (đặc tả mục 5.1): YuNet → căn chỉnh 112×112 → ArcFace; MiniFASNetV2 chống giả mạo.

Không bao giờ ném lỗi vì ảnh hỏng: ảnh không giải mã được trả face_count = 0.
"""
import threading
import time
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

from app.services.face.types import FrameAnalysis

# Vị trí 5 điểm mốc chuẩn của ArcFace trên ảnh 112×112 (mắt trái ảnh, mắt phải ảnh, mũi, mép trái, mép phải).
ARCFACE_DST = np.array([[38.2946, 51.6963], [73.5318, 51.5014], [56.0252, 71.7366],
                        [41.5493, 92.3655], [70.7299, 92.2041]], dtype=np.float32)
MAX_SIDE = 1280          # ảnh lớn hơn được thu nhỏ trước khi phát hiện (đặc tả mục 5.2)
MAX_PIXELS = 40_000_000  # chặn ảnh "bom" kích thước khổng lồ
SPOOF_SCALE = 2.7        # MiniFASNetV2: vùng cắt = 2,7 lần khung mặt


class OnnxFaceEngine:
    def __init__(self, models_dir: str | Path, embed_model: str = "w600k_r50.onnx",
                 spoof_model: str = "MiniFASNetV2.onnx", det_model: str = "face_detection_yunet_2023mar.onnx",
                 det_score: float = 0.8, threads: int = 2):
        d = Path(models_dir)
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        cpu = ["CPUExecutionProvider"]
        self.embed = ort.InferenceSession(str(d / embed_model), opts, providers=cpu)
        self.spoof = ort.InferenceSession(str(d / spoof_model), opts, providers=cpu)
        self._det_path = str(d / det_model)
        self._det_score = det_score
        self._local = threading.local()  # cv2.FaceDetectorYN không an toàn khi dùng chung giữa các luồng
        self.timings: dict[str, float] = {}

    def _detector(self, w: int, h: int):
        det = getattr(self._local, "det", None)
        if det is None:
            det = self._local.det = cv2.FaceDetectorYN.create(self._det_path, "", (w, h), self._det_score)
        det.setInputSize((w, h))
        return det

    # ---- API theo FaceEngine ----

    def analyze(self, jpeg: bytes, *, embed: bool, spoof: bool) -> FrameAnalysis:
        return self.analyze_bgr(decode(jpeg), embed=embed, spoof=spoof)

    def analyze_bgr(self, img: np.ndarray | None, *, embed: bool, spoof: bool) -> FrameAnalysis:
        if img is None:
            return _no_face()
        t0 = time.perf_counter()
        faces = self.detect(img)
        self.timings["detect"] = time.perf_counter() - t0
        if len(faces) == 0:
            return _no_face()
        face = max(faces, key=lambda f: f[2] * f[3])  # mặt lớn nhất là người đang điểm danh
        x, y, w, h = face[:4]
        kps = face[4:14].reshape(5, 2)
        aligned = align(img, kps)
        gray = cv2.cvtColor(aligned, cv2.COLOR_BGR2GRAY)
        emb = spoof_score = None
        if embed:
            t0 = time.perf_counter()
            emb = self._embedding(aligned)
            self.timings["embed"] = time.perf_counter() - t0
        if spoof:
            t0 = time.perf_counter()
            spoof_score = self._spoof(img, (x, y, w, h))
            self.timings["spoof"] = time.perf_counter() - t0
        return FrameAnalysis(
            face_count=len(faces),
            face_width_px=float(w),
            brightness=float(gray.mean()),
            sharpness=float(cv2.Laplacian(gray, cv2.CV_64F).var()),
            yaw_proxy=yaw_proxy(kps),
            embedding=emb,
            spoof_score=spoof_score,
        )

    # ---- Các bước ----

    def detect(self, img: np.ndarray) -> np.ndarray:
        """Mảng N×15: x, y, w, h, 5 điểm mốc (x, y), điểm tin cậy."""
        h, w = img.shape[:2]
        _, faces = self._detector(w, h).detect(img)
        return np.empty((0, 15), np.float32) if faces is None else faces

    def _embedding(self, aligned: np.ndarray) -> np.ndarray:
        blob = cv2.dnn.blobFromImage(aligned, 1 / 127.5, (112, 112), (127.5, 127.5, 127.5), swapRB=True)
        v = self.embed.run(None, {self.embed.get_inputs()[0].name: blob})[0][0].astype(np.float32)
        return v / max(float(np.linalg.norm(v)), 1e-12)

    def _spoof(self, img: np.ndarray, box: tuple[float, float, float, float]) -> float:
        crop = crop_scaled(img, box, SPOOF_SCALE, 80)
        x = np.transpose(crop.astype(np.float32), (2, 0, 1))[None]  # BGR, 0–255, NCHW
        logits = self.spoof.run(None, {self.spoof.get_inputs()[0].name: x})[0]
        e = np.exp(logits - logits.max(axis=1, keepdims=True))
        return float((e / e.sum(axis=1, keepdims=True))[0, 1])  # lớp 1 = người thật


def decode(jpeg: bytes) -> np.ndarray | None:
    """Giải mã ảnh; ảnh hỏng, rỗng, quá lớn → None. Ảnh cạnh dài > 1280 px được thu nhỏ."""
    if not jpeg:
        return None
    try:
        img = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
    except cv2.error:
        return None
    if img is None or img.shape[0] * img.shape[1] > MAX_PIXELS:
        return None
    side = max(img.shape[:2])
    if side > MAX_SIDE:
        s = MAX_SIDE / side
        img = cv2.resize(img, (round(img.shape[1] * s), round(img.shape[0] * s)), interpolation=cv2.INTER_AREA)
    return img


def align(img: np.ndarray, kps: np.ndarray) -> np.ndarray:
    """Căn chỉnh mặt về 112×112 bằng phép đồng dạng theo 5 điểm mốc."""
    m, _ = cv2.estimateAffinePartial2D(kps.astype(np.float32), ARCFACE_DST, method=cv2.LMEDS)
    if m is None:
        m = cv2.getAffineTransform(kps[:3].astype(np.float32), ARCFACE_DST[:3])
    return cv2.warpAffine(img, m, (112, 112), borderValue=0)


def yaw_proxy(kps: np.ndarray) -> float | None:
    """(mũi_x − trung điểm hai mắt_x) / khoảng cách hai mắt, theo tọa độ ảnh. Dấu ứng với hướng quay
    phụ thuộc camera có lật ảnh hay không: yaw_sign trong config.yaml chốt ở Task 0."""
    (ex1, _), (ex2, _), (nx, _) = kps[0], kps[1], kps[2]
    dist = abs(ex2 - ex1)
    return None if dist < 1 else float((nx - (ex1 + ex2) / 2) / dist)


def crop_scaled(img: np.ndarray, box, scale: float, size: int) -> np.ndarray:
    """Cắt vùng gấp `scale` lần khung mặt quanh tâm (co lại nếu chạm biên ảnh), resize về size×size."""
    x, y, w, h = box
    ih, iw = img.shape[:2]
    scale = min((ih - 1) / max(h, 1), (iw - 1) / max(w, 1), scale)
    cx, cy, nw, nh = x + w / 2, y + h / 2, w * scale, h * scale
    x1, y1 = max(0, int(cx - nw / 2)), max(0, int(cy - nh / 2))
    x2, y2 = min(iw - 1, int(cx + nw / 2)), min(ih - 1, int(cy + nh / 2))
    return cv2.resize(img[y1:y2 + 1, x1:x2 + 1], (size, size))


def _no_face() -> FrameAnalysis:
    return FrameAnalysis(face_count=0, face_width_px=0.0, brightness=0.0, sharpness=0.0, yaw_proxy=None,
                         embedding=None, spoof_score=None)
