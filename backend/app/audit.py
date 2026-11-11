"""Nhật ký thao tác nhạy cảm (đặc tả mục 8, bảng audit_log)."""
import ipaddress

import psycopg
from psycopg.types.json import Jsonb


def log(conn: psycopg.Connection, actor_id: int | None, action: str, target: str,
        before: dict | None = None, after: dict | None = None, ip: str | None = None) -> None:
    try:
        ip = str(ipaddress.ip_address(ip)) if ip else None
    except ValueError:  # vd "testclient"
        ip = None
    conn.execute(
        "INSERT INTO audit_log (actor_id, action, target, before, after, ip) VALUES (%s, %s, %s, %s, %s, %s)",
        (actor_id, action, target, Jsonb(before) if before is not None else None,
         Jsonb(after) if after is not None else None, ip))
