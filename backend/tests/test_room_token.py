import pytest

from app.services.room_token import room_code, verify_room_code, window_end

K = b"k" * 32


def test_code_shape():
    c = room_code(K, 41, 1_000_000.0)
    assert len(c) == 8 and c.isalnum() and c.isupper()


def test_same_window_same_code():
    assert room_code(K, 41, 990.0) == room_code(K, 41, 1019.9)
    assert room_code(K, 41, 1019.9) != room_code(K, 41, 1020.0)


def test_window_acceptance():
    c = room_code(K, 41, 990.0)                   # cửa sổ 33
    assert verify_room_code(c, K, 41, 1000.0)     # cửa sổ 33: đúng cửa sổ
    assert verify_room_code(c, K, 41, 1029.0)     # cửa sổ 34: cửa sổ trước, vẫn nhận
    assert not verify_room_code(c, K, 41, 1050.0) # cửa sổ 35: hết hạn
    assert not verify_room_code(c, K, 41, 960.0)  # cửa sổ 32: mã của tương lai không nhận


def test_bound_to_session_and_secret():
    assert room_code(K, 41, 0) != room_code(K, 42, 0)
    assert not verify_room_code(room_code(K, 41, 0), b"x" * 32, 41, 0)


@pytest.mark.parametrize("bad", ["", None, "ABC", "!!!!!!!!", 12345678])
def test_garbage_rejected(bad):
    assert verify_room_code(bad, K, 41, 1000.0) is False


def test_case_and_spaces_tolerated():
    c = room_code(K, 41, 1000.0)
    assert verify_room_code(c.lower(), K, 41, 1000.0)
    assert verify_room_code(f" {c[:4]} {c[4:]} ", K, 41, 1000.0)  # dạng "K7Q2 M9XA" chiếu trên màn hình


def test_window_end():
    assert window_end(990.0) == 1020.0 and window_end(1020.0) == 1050.0
