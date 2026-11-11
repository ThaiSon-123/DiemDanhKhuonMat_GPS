import json
import math

import pytest

from app.services.geo import (Fix, Sample, adaptive_radius, aggregate, classify, has_jump, haversine_m, in_polygon,
                              jump_from_previous, load_campus, recenter, suggest_recenter)


def test_haversine():
    assert haversine_m(21.0, 105.0, 21.0, 105.001) == pytest.approx(103.8, abs=0.5)
    assert haversine_m(21.0, 105.0, 21.0, 105.0) == 0
    assert haversine_m(21.0, 105.0, 21.001, 105.0) == pytest.approx(111.2, abs=0.5)


def test_aggregate_median_and_filter():
    s = [Sample(21.0, 105.0, 10, 0), Sample(21.0002, 105.0, 12, 1000), Sample(21.0001, 105.0, 8, 2000),
         Sample(22.0, 106.0, 80, 3000)]  # mẫu cuối: acc 80 > 30 bị bỏ
    f = aggregate(s, max_acc=30, min_count=3, max_span_s=20)
    assert (f.lat, f.lng, f.acc) == (21.0001, 105.0, 10)


def test_aggregate_rejects():
    ok = [Sample(21, 105, 10, i * 1000) for i in range(3)]
    assert aggregate(ok, 30, 3, 20) is not None
    assert aggregate(ok[:2], 30, 3, 20) is None                                    # thiếu mẫu
    assert aggregate(ok[:2] + [Sample(21, 105, 10, 25_000)], 30, 3, 20) is None     # span 25 s > 20 s
    assert aggregate([], 30, 3, 20) is None


def test_aggregate_ignores_garbage():
    good = [Sample(21, 105, 10, i * 1000) for i in range(3)]
    junk = [Sample(91, 105, 10, 0), Sample(21, 181, 10, 0), Sample(21, 105, 0, 0), Sample(21, 105, -5, 0),
            Sample(math.nan, 105, 10, 0), Sample(21, 105, math.inf, 0)]
    assert aggregate(junk, 30, 3, 20) is None
    assert aggregate(good + junk, 30, 3, 20) == Fix(21, 105, 10)


def test_aggregate_span_uses_unordered_ts():
    s = [Sample(21, 105, 10, 5000), Sample(21, 105, 10, 0), Sample(21, 105, 10, 2000)]
    assert aggregate(s, 30, 3, 4) is None and aggregate(s, 30, 3, 5) is not None


def test_classify_boundaries():
    assert classify(30, 30) == "ok" and classify(30.1, 30) == "drift"
    assert classify(60, 30) == "drift" and classify(60.1, 30) == "far"


def test_adaptive_radius():
    assert adaptive_radius(20, 8, 14) == 42


def test_has_jump():
    near = 10 / 111_195  # ~10 m theo vĩ độ
    far = 100 / 111_195
    assert has_jump([Sample(21, 105, 10, 0), Sample(21 + far, 105, 10, 1000)], max_speed=30) is True
    assert has_jump([Sample(21, 105, 10, 0), Sample(21 + near, 105, 10, 1000)], max_speed=30) is False
    assert has_jump([Sample(21, 105, 10, 0), Sample(21 + far, 105, 10, 0)], max_speed=30) is True    # ts trùng
    assert has_jump([Sample(21, 105, 10, 0), Sample(21 + near, 105, 10, 0)], max_speed=30) is False
    assert has_jump([Sample(21, 105, 10, 0)], max_speed=30) is False
    # sắp theo ts trước khi so: mẫu đến lộn xộn không tạo bước nhảy giả
    assert has_jump([Sample(21 + 2 * near, 105, 10, 2000), Sample(21, 105, 10, 0), Sample(21 + near, 105, 10, 1000)],
                    max_speed=30) is False


def test_jump_from_previous():
    a, b = Fix(21, 105, 10), Fix(21 + 1000 / 111_195, 105, 10)  # cách ~1 km
    assert jump_from_previous(a, 0, b, 10, max_speed=30) is True      # 100 m/s
    assert jump_from_previous(a, 0, b, 100, max_speed=30) is False    # 10 m/s
    assert jump_from_previous(a, 5, b, 5, max_speed=30) is True       # cùng thời điểm


SQUARE = [(105.0, 21.0), (105.01, 21.0), (105.01, 21.01), (105.0, 21.01), (105.0, 21.0)]  # (lng, lat)


def test_in_polygon():
    assert in_polygon(21.005, 105.005, SQUARE) is True
    assert in_polygon(21.02, 105.005, SQUARE) is False
    assert in_polygon(21.005, 104.99, SQUARE) is False
    assert in_polygon(21.0, 105.005, SQUARE) is True    # đúng trên cạnh dưới
    assert in_polygon(21.005, 105.01, SQUARE) is True   # đúng trên cạnh phải
    assert in_polygon(21.0, 105.0, SQUARE) is True      # đỉnh


def test_load_campus_feature_and_collection(tmp_path):
    geom = {"type": "Polygon", "coordinates": [[list(p) for p in SQUARE]]}
    for doc in (geom, {"type": "Feature", "geometry": geom},
                {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": geom}]}):
        f = tmp_path / "c.geojson"
        f.write_text(json.dumps(doc), encoding="utf-8")
        assert load_campus(str(f)) == SQUARE


def test_load_real_campus_file():
    from app.config import BASE_DIR, get_settings
    ring = load_campus(str(BASE_DIR / get_settings().campus_polygon_file))
    assert len(ring) >= 4 and ring[0] == ring[-1]


def test_suggest_recenter():
    c = (21.0, 105.0)
    east = [(21.0, 105.0004 + i * 1e-5) for i in range(5)]   # ~42-46 m về phía đông
    assert suggest_recenter(c, east, r0=20) is True
    assert suggest_recenter(c, east[:4], r0=20) is False     # chưa đủ 5
    assert suggest_recenter(c, east, r0=50) is False         # lệch chưa vượt r0
    spread = [(21.0004, 105.0), (20.9996, 105.0), (21.0, 105.0004), (21.0, 104.9996), (21.0004, 105.0004)]
    assert suggest_recenter(c, spread, r0=20) is False       # lệch tứ phía


def test_recenter_median():
    pts = [(21.0, 105.0004), (21.0001, 105.0005), (21.0002, 105.0006), (25.0, 110.0), (21.0001, 105.0005)]
    assert recenter((21.0, 105.0), pts) == (21.0001, 105.0005)
