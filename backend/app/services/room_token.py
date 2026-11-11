"""Mã phòng xoay vòng kiểu TOTP (đặc tả mục 7.2): không lưu từng mã, nhận cửa sổ hiện tại và cửa sổ ngay trước."""
import base64
import hashlib
import hmac


def _window(t: float, window_s: int) -> int:
    return int(t // window_s)


def _code(secret: bytes, session_id: int, window: int) -> str:
    digest = hmac.new(secret, f"{session_id}|{window}".encode(), hashlib.sha256).digest()
    return base64.b32encode(digest).decode()[:8]


def room_code(secret: bytes, session_id: int, t: float, window_s: int = 30) -> str:
    return _code(secret, session_id, _window(t, window_s))


def window_end(t: float, window_s: int = 30) -> float:
    """Thời điểm mã hiện tại hết làm mã "hiện tại" (app dùng để đếm ngược)."""
    return float((_window(t, window_s) + 1) * window_s)


def verify_room_code(code: object, secret: bytes, session_id: int, now: float, window_s: int = 30) -> bool:
    if not isinstance(code, str):
        return False
    given = "".join(code.split()).upper()  # bỏ khoảng trắng: mã chiếu dạng "K7Q2 M9XA"
    if len(given) != 8:
        return False
    w = _window(now, window_s)
    # So cả hai cửa sổ (không dừng sớm) để thời gian trả lời không lộ cửa sổ nào khớp.
    ok = [hmac.compare_digest(given, _code(secret, session_id, x)) for x in (w, w - 1)]
    return any(ok)
