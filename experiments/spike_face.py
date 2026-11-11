"""Task 0 — thử mô hình khuôn mặt trên laptop (không phải code chạy thật; số đo ghi vào experiments/spike.md).

Chạy từ thư mục gốc dự án, bằng Python của backend:
    backend/.venv/Scripts/python.exe experiments/spike_face.py webcam            # đo bằng webcam
    backend/.venv/Scripts/python.exe experiments/spike_face.py images a.jpg ...  # đo ảnh chụp từ điện thoại
    backend/.venv/Scripts/python.exe experiments/spike_face.py cos a.jpg b.jpg ...  # ma trận cosine giữa các ảnh
    backend/.venv/Scripts/python.exe experiments/spike_face.py summary           # tổng hợp số đo webcam đã ghi

Phím trong cửa sổ webcam:
    e   chụp ảnh mẫu của chính bạn (dòng "cos" so với ảnh mẫu này)
    1   ghi 10 khung kế tiếp với nhãn "that"   (mặt thật)
    2   ghi 10 khung với nhãn "anh_in"          (giơ ảnh in trước webcam)
    3   ghi 10 khung với nhãn "man_hinh"        (giơ ảnh trên màn hình điện thoại)
    4   ghi 10 khung với nhãn "video"           (phát video khuôn mặt trên điện thoại / laptop khác)
    5   ghi 10 khung với nhãn "toi"             (ngồi chỗ tối)
    6   ghi 10 khung với nhãn "rung"            (lắc máy / di chuyển nhanh)
    q   thoát
"""
import csv
import os
import statistics
import sys
import time
from pathlib import Path

os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
import cv2  # noqa: E402
import numpy as np  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from app.services.face.onnx_engine import OnnxFaceEngine  # noqa: E402

LOG = ROOT / "experiments" / "data" / "spike_log.csv"
WINDOW = "spike_face (q: thoat)"
LABELS = {ord("1"): "that", ord("2"): "anh_in", ord("3"): "man_hinh", ord("4"): "video", ord("5"): "toi",
          ord("6"): "rung"}
FIELDS = ["label", "faces", "width", "brightness", "sharpness", "yaw", "spoof", "cos", "ms_detect", "ms_embed",
          "ms_spoof"]


def engine() -> OnnxFaceEngine:
    model = "w600k_mbf.onnx" if "--mbf" in sys.argv else "w600k_r50.onnx"
    print(f"Mô hình embedding: {model}")
    return OnnxFaceEngine(ROOT / "backend" / "models", embed_model=model)


def fmt(v, nd=2):
    return "-" if v is None else f"{v:.{nd}f}"


def webcam() -> None:
    eng = engine()
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW) if os.name == "nt" else cv2.VideoCapture(0)
    if not cap.isOpened():
        sys.exit("Không mở được webcam (camera 0). Đóng ứng dụng khác đang dùng camera rồi thử lại.")
    LOG.parent.mkdir(parents=True, exist_ok=True)
    new_file = not LOG.exists() or LOG.stat().st_size == 0
    out = open(LOG, "a", newline="", encoding="utf-8")
    writer = csv.DictWriter(out, FIELDS)
    if new_file:
        writer.writeheader()
        out.flush()
    ref = None
    recording, left = None, 0
    print(__doc__.split("Phím trong cửa sổ webcam:")[1])
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        a = eng.analyze_bgr(frame, embed=True, spoof=True)
        cos = float(a.embedding @ ref) if (ref is not None and a.embedding is not None) else None
        t = eng.timings
        lines = [
            f"mat: {a.face_count}   rong: {a.face_width_px:.0f}px",
            f"sang: {a.brightness:.0f}   net: {a.sharpness:.0f}",
            f"yaw: {fmt(a.yaw_proxy)}   spoof(that): {fmt(a.spoof_score)}",
            f"cos voi mau: {fmt(cos)}" + ("" if ref is not None else "   (bam e de chup mau)"),
            f"ms: detect {t.get('detect', 0) * 1000:.0f} embed {t.get('embed', 0) * 1000:.0f} "
            f"spoof {t.get('spoof', 0) * 1000:.0f}",
        ]
        if recording:
            lines.append(f"DANG GHI [{recording}] con {left} khung")
        for i, s in enumerate(lines):
            cv2.putText(frame, s, (10, 28 + 26 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 4)
            cv2.putText(frame, s, (10, 28 + 26 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (80, 255, 80), 1)
        for f in eng.detect(frame):
            x, y, w, h = map(int, f[:4])
            cv2.rectangle(frame, (x, y), (x + w, y + h), (80, 255, 80), 2)
        cv2.imshow(WINDOW, frame)

        if recording and a.face_count > 0:
            writer.writerow({"label": recording, "faces": a.face_count, "width": round(a.face_width_px),
                             "brightness": round(a.brightness, 1), "sharpness": round(a.sharpness, 1),
                             "yaw": fmt(a.yaw_proxy, 3), "spoof": fmt(a.spoof_score, 4), "cos": fmt(cos, 4),
                             "ms_detect": round(t.get("detect", 0) * 1000, 1),
                             "ms_embed": round(t.get("embed", 0) * 1000, 1),
                             "ms_spoof": round(t.get("spoof", 0) * 1000, 1)})
            out.flush()  # ghi ngay: tắt cửa sổ bằng nút X hay Ctrl+C vẫn giữ số đo
            left -= 1
            if left == 0:
                print(f"Đã ghi 10 khung [{recording}] vào {LOG}")
                recording = None
        key = cv2.waitKey(1) & 0xFF
        if key == ord("q") or cv2.getWindowProperty(WINDOW, cv2.WND_PROP_VISIBLE) < 1:
            break
        if key == ord("e"):
            if a.embedding is None:
                print("Chưa thấy mặt, chưa chụp được ảnh mẫu.")
            else:
                ref = a.embedding
                print("Đã chụp ảnh mẫu (chỉ giữ trong bộ nhớ để so cosine, không lưu file).")
        if key in LABELS:
            recording, left = LABELS[key], 10
    out.close()
    cap.release()
    cv2.destroyAllWindows()
    print(f"Số đo đã ghi vào {LOG}. Chạy lệnh 'summary' để tổng hợp.")


def images(paths: list[str]) -> None:
    eng = engine()
    print(f"{'file':40} {'mat':>3} {'rong':>5} {'sang':>5} {'net':>6} {'yaw':>6} {'spoof':>6}")
    for p in paths:
        a = eng.analyze(Path(p).read_bytes(), embed=False, spoof=True)
        print(f"{Path(p).name[:40]:40} {a.face_count:>3} {a.face_width_px:>5.0f} {a.brightness:>5.0f} "
              f"{a.sharpness:>6.0f} {fmt(a.yaw_proxy):>6} {fmt(a.spoof_score):>6}")


def cos(paths: list[str]) -> None:
    eng = engine()
    embs = []
    for p in paths:
        a = eng.analyze(Path(p).read_bytes(), embed=True, spoof=False)
        if a.embedding is None:
            sys.exit(f"Không thấy mặt trong {p}")
        embs.append(a.embedding)
    names = [Path(p).stem[:10] for p in paths]
    print(" " * 11 + " ".join(f"{n:>10}" for n in names))
    for n, e in zip(names, embs):
        print(f"{n:>10} " + " ".join(f"{float(e @ f):>10.3f}" for f in embs))


def summary() -> None:
    if not LOG.exists():
        sys.exit("Chưa có số đo: chạy 'webcam' và bấm phím 1–6 trước.")
    rows = list(csv.DictReader(open(LOG, encoding="utf-8")))
    by: dict[str, list[dict]] = {}
    for r in rows:
        by.setdefault(r["label"], []).append(r)

    def stat(rs, k):
        v = [float(r[k]) for r in rs if r[k] not in ("", "-")]
        return "-" if not v else f"tb {statistics.mean(v):7.2f}  nho {min(v):7.2f}  lon {max(v):7.2f}"

    for label, rs in by.items():
        print(f"\n== {label} ({len(rs)} khung)")
        for k in ("spoof", "cos", "brightness", "sharpness", "yaw", "ms_detect", "ms_embed", "ms_spoof"):
            print(f"   {k:11} {stat(rs, k)}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "webcam"
    args = [a for a in sys.argv[2:] if not a.startswith("--")]
    {"webcam": lambda: webcam(), "images": lambda: images(args), "cos": lambda: cos(args),
     "summary": lambda: summary()}.get(cmd, lambda: sys.exit(__doc__))()
