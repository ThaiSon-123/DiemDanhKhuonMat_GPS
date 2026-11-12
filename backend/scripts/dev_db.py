r"""Bật Postgres nhúng (pgserver) cho máy dev không có Docker; in ra DATABASE_URL.

Dữ liệu nằm ở backend/.pgdata, giữ lại giữa các lần bật. Mỗi lần bật lại có thể đổi cổng, nên luôn lấy URL từ script:
    $env:DATABASE_URL = (.venv\Scripts\python.exe scripts\dev_db.py)
"""
from pathlib import Path

import pgserver

server = pgserver.get_server(Path(__file__).resolve().parent.parent / ".pgdata", cleanup_mode=None)  # None: chạy tiếp sau khi script thoát
if "diemdanh" not in server.psql("SELECT datname FROM pg_database;"):
    server.psql("CREATE DATABASE diemdanh;")
print(server.get_uri().rsplit("/", 1)[0] + "/diemdanh")
