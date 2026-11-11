"""Hàm vị trí thuần (đặc tả mục 4.5, 6): gộp mẫu, bán kính thích ứng, bước nhảy, khuôn viên, tâm lệch."""
import json
import math
from dataclasses import dataclass
from statistics import median
from typing import Literal

EARTH_R = 6_371_000


@dataclass(frozen=True)
class Sample:
    lat: float
    lng: float
    acc: float
    ts: int          # mili giây, đồng hồ điện thoại: chỉ dùng hiệu số, không dùng giờ tuyệt đối
    mock: bool = False


@dataclass(frozen=True)
class Fix:
    lat: float
    lng: float
    acc: float


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.asin(min(1.0, math.sqrt(a)))


def _sane(s: Sample) -> bool:
    return (all(math.isfinite(x) for x in (s.lat, s.lng, s.acc)) and -90 <= s.lat <= 90
            and -180 <= s.lng <= 180 and s.acc > 0)


def aggregate(samples: list[Sample], max_acc: float, min_count: int, max_span_s: float) -> Fix | None:
    """Mục 6.2: bỏ mẫu rác và mẫu acc > max_acc; đủ min_count mẫu trong max_span_s giây thì lấy trung vị."""
    good = [s for s in samples if _sane(s) and s.acc <= max_acc]
    if len(good) < min_count:
        return None
    ts = [s.ts for s in good]
    if (max(ts) - min(ts)) / 1000 > max_span_s:
        return None
    return Fix(median(s.lat for s in good), median(s.lng for s in good), median(s.acc for s in good))


def adaptive_radius(r0: float, sigma_gv: float, sigma_sv: float) -> float:
    return r0 + sigma_gv + sigma_sv


def classify(d: float, r: float) -> Literal["ok", "drift", "far"]:
    if d <= r:
        return "ok"
    return "drift" if d <= 2 * r else "far"


def _too_fast(meters: float, seconds: float, max_speed: float) -> bool:
    return meters / max(seconds, 1.0) > max_speed  # khoảng thời gian < 1 s (kể cả 0) tính như 1 s


def has_jump(samples: list[Sample], max_speed: float) -> bool:
    """Tốc độ giữa hai mẫu liên tiếp (theo ts) vượt max_speed m/s."""
    s = sorted((x for x in samples if _sane(x)), key=lambda x: x.ts)
    return any(_too_fast(haversine_m(a.lat, a.lng, b.lat, b.lng), (b.ts - a.ts) / 1000, max_speed)
               for a, b in zip(s, s[1:]))


def jump_from_previous(prev: Fix, prev_t: float, cur: Fix, cur_t: float, max_speed: float) -> bool:
    """Lượt này cách lượt trước trong cùng phiên quá xa so với thời gian server ghi nhận (giây)."""
    return _too_fast(haversine_m(prev.lat, prev.lng, cur.lat, cur.lng), cur_t - prev_t, max_speed)


# ---- Khuôn viên ----

def load_campus(path: str) -> list[tuple[float, float]]:
    """Vòng ngoài của đa giác (lng, lat) từ GeoJSON Polygon / Feature / FeatureCollection (lấy feature đầu)."""
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    if doc.get("type") == "FeatureCollection":
        doc = doc["features"][0]
    if doc.get("type") == "Feature":
        doc = doc["geometry"]
    if doc.get("type") != "Polygon":
        raise ValueError("File khuôn viên phải là một Polygon GeoJSON")
    return [(float(x), float(y)) for x, y, *_ in doc["coordinates"][0]]


def _on_segment(x: float, y: float, a: tuple[float, float], b: tuple[float, float], eps: float = 1e-12) -> bool:
    (x1, y1), (x2, y2) = a, b
    cross = (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1)
    return (abs(cross) <= eps and min(x1, x2) - eps <= x <= max(x1, x2) + eps
            and min(y1, y2) - eps <= y <= max(y1, y2) + eps)


def in_polygon(lat: float, lng: float, ring: list[tuple[float, float]]) -> bool:
    """Ray casting; điểm nằm đúng trên cạnh coi là ở trong."""
    x, y = lng, lat
    inside = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if _on_segment(x, y, a, b):
            return True
        (x1, y1), (x2, y2) = a, b
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


# ---- Tâm lệch (mục 4.5) ----

def _bearing(center: tuple[float, float], p: tuple[float, float]) -> float:
    """Hướng (radian) từ tâm tới điểm trên mặt phẳng xấp xỉ cục bộ."""
    dx = (p[1] - center[1]) * math.cos(math.radians(center[0]))
    dy = p[0] - center[0]
    return math.atan2(dy, dx)


def suggest_recenter(center: tuple[float, float], positions: list[tuple[float, float]], r0: float) -> bool:
    """Gợi ý tính lại tâm: ≥ 5 vị trí, trung vị khoảng cách > r0 và > 70 % hướng nằm trong ±45° quanh hướng trung bình."""
    if len(positions) < 5:
        return False
    if median(haversine_m(*center, *p) for p in positions) <= r0:
        return False
    angles = [_bearing(center, p) for p in positions]
    mean = math.atan2(sum(math.sin(a) for a in angles), sum(math.cos(a) for a in angles))
    near = sum(1 for a in angles if abs(math.remainder(a - mean, math.tau)) <= math.pi / 4)
    return near / len(angles) > 0.7


def recenter(center: tuple[float, float], positions: list[tuple[float, float]]) -> tuple[float, float]:
    """Tâm mới = trung vị vị trí các sinh viên đã qua khuôn mặt; không có vị trí thì giữ tâm cũ."""
    if not positions:
        return center
    return median(p[0] for p in positions), median(p[1] for p in positions)
