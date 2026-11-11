import numpy as np
import pytest
from cryptography.exceptions import InvalidTag

from app import crypto


@pytest.fixture
def storage(tmp_path, monkeypatch):
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path))
    return tmp_path


def test_roundtrip():
    assert crypto.decrypt(crypto.encrypt(b"abc")) == b"abc"
    assert crypto.decrypt(crypto.encrypt(b"")) == b""


def test_nonce_differs():
    assert crypto.encrypt(b"abc") != crypto.encrypt(b"abc")


def test_tamper_detected():
    blob = bytearray(crypto.encrypt(b"du lieu sinh trac"))
    blob[-1] ^= 1
    with pytest.raises(InvalidTag):
        crypto.decrypt(bytes(blob))


def test_blob_on_disk_is_not_plaintext(storage):
    rel = crypto.save_blob("faces/12/0.jpg", b"JPEG-PLAINTEXT")
    assert rel == "faces/12/0.jpg"
    raw = (storage / "faces" / "12" / "0.jpg").read_bytes()
    assert b"JPEG-PLAINTEXT" not in raw
    assert crypto.load_blob(rel) == b"JPEG-PLAINTEXT"


def test_delete_blob_and_tree_are_idempotent(storage):
    crypto.save_blob("faces/12/0.jpg", b"a")
    crypto.save_blob("faces/12/1.jpg", b"b")
    crypto.delete_blob("faces/12/0.jpg")
    crypto.delete_blob("faces/12/0.jpg")  # đã mất: không lỗi
    assert not (storage / "faces/12/0.jpg").exists()
    crypto.delete_tree("faces/12")
    crypto.delete_tree("faces/12")
    assert not (storage / "faces/12").exists()


@pytest.mark.parametrize("bad", ["../x", "faces/../../x", "/etc/passwd", "C:/x", "..\\x", "", "."])
def test_rel_path_cannot_escape_storage(storage, bad):
    with pytest.raises(ValueError):
        crypto.save_blob(bad, b"x")
    with pytest.raises(ValueError):
        crypto.delete_tree(bad)


def test_embedding_roundtrip():
    v = np.random.default_rng(0).standard_normal(512).astype(np.float32)
    b = crypto.embedding_to_bytes(v)
    assert len(b) == 512 * 4
    out = crypto.embedding_from_bytes(b)
    assert out.dtype == np.float32 and np.array_equal(out, v)
    out[0] = 99  # mảng trả về ghi được (không phải view chỉ đọc của bytes)
