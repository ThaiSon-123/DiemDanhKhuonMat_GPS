"""Quy trình khuôn mặt khi điểm danh và khi đăng ký (đặc tả mục 4.2, 4.4 bước 5–6, 5.1)."""
from collections import Counter

import numpy as np

from app.config import FaceCfg
from app.services.face.checks import action_done, face_status, match_scores, quality_reason, unit
from app.services.face.types import FaceEngine, FaceResult

MIN_QUALITY_FRAMES = 3
SPOOF_FRAMES = 3


def verify_checkin(frames: list[bytes], action: str, template: np.ndarray, engine: FaceEngine,
                   cfg: FaceCfg) -> FaceResult:
    """Chất lượng (≥ 3 khung đạt) → hành động → anti-spoofing (3 khung nét nhất, lấy min) → so khớp mọi khung đạt."""
    # Lượt 1: chỉ phát hiện mặt + chất lượng + góc quay, chưa chạy mô hình nặng.
    first = [engine.analyze(f, embed=False, spoof=False) for f in frames]
    reasons = [quality_reason(a, cfg) for a in first]
    good = [i for i, r in enumerate(reasons) if r is None]
    best = max(good, key=lambda i: first[i].sharpness) if good else None

    def fail(reason: str, **kw) -> FaceResult:
        return FaceResult("fail", reason, kw.get("face"), kw.get("live"), kw.get("action"), best)

    if len(good) < MIN_QUALITY_FRAMES:
        return fail(Counter(r for r in reasons if r).most_common(1)[0][0])

    yaws = [a.yaw_proxy if a.face_count == 1 else None for a in first]
    if not action_done(yaws, action, cfg):
        return fail("ACTION_NOT_DETECTED", action=False)

    # Lượt 2: embedding cho mọi khung đạt; anti-spoofing chỉ trên 3 khung nét nhất.
    sharpest = set(sorted(good, key=lambda i: first[i].sharpness, reverse=True)[:SPOOF_FRAMES])
    second = {i: engine.analyze(frames[i], embed=True, spoof=i in sharpest) for i in good}
    spoof = [second[i].spoof_score for i in sharpest]
    live = min(s if s is not None else 0.0 for s in spoof)
    if live < cfg.antispoof_threshold:
        return fail("SPOOF_DETECTED", live=live, action=True)

    embs = [second[i].embedding for i in good if second[i].embedding is not None]
    if len(embs) < MIN_QUALITY_FRAMES:  # engine mất mặt ở lượt 2: coi như không thấy mặt
        return fail("FACE_NOT_FOUND", live=live, action=True)
    med, low = match_scores(embs, template)
    status = face_status(med, low, cfg)
    return FaceResult(status, "FACE_MISMATCH" if status == "fail" else None, med, live, True, best)


def build_template(photos: list[bytes], engine: FaceEngine, cfg: FaceCfg) -> tuple[np.ndarray | None, list[dict]]:
    """Mẫu đăng ký = trung bình embedding đã chuẩn hóa. Mỗi ảnh phải đạt chất lượng, là người thật,
    và giống trung bình các ảnh còn lại (cosine ≥ ngưỡng nghi ngờ). Có ảnh lỗi thì trả (None, danh sách lỗi)."""
    analyses = [engine.analyze(p, embed=True, spoof=True) for p in photos]
    issues: list[dict] = []
    embs: dict[int, np.ndarray] = {}
    for i, a in enumerate(analyses):
        reason = quality_reason(a, cfg)
        if reason is None and (a.spoof_score is None or a.spoof_score < cfg.antispoof_threshold):
            reason = "SPOOF_DETECTED"
        if reason is None and a.embedding is None:
            reason = "FACE_NOT_FOUND"
        if reason:
            issues.append({"index": i, "reason": reason})
        else:
            embs[i] = unit(a.embedding)
    if len(embs) >= 2:
        for i, e in embs.items():
            others = unit(np.mean([v for j, v in embs.items() if j != i], axis=0))
            if float(e @ others) < cfg.suspect_threshold:
                issues.append({"index": i, "reason": "INCONSISTENT_FACE"})
    if issues or not embs:
        return None, sorted(issues, key=lambda x: x["index"])
    return unit(np.mean(list(embs.values()), axis=0)), []

