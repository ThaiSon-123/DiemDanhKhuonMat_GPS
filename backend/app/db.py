import os
from collections.abc import Iterator
from functools import lru_cache

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


@lru_cache
def get_pool() -> ConnectionPool:
    return ConnectionPool(os.environ["DATABASE_URL"], kwargs={"row_factory": dict_row}, open=True)


def get_conn() -> Iterator[psycopg.Connection]:
    """Mỗi request một transaction: pool tự commit khi xong, rollback khi có exception."""
    with get_pool().connection() as conn:
        yield conn
