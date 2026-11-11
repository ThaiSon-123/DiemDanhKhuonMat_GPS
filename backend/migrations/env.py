import os
from pathlib import Path

from alembic import context
from dotenv import load_dotenv
from sqlalchemy import create_engine

# Chạy tay thì lấy DATABASE_URL từ backend/.env; test đã đặt sẵn biến môi trường nên không bị ghi đè.
load_dotenv(Path(__file__).resolve().parent.parent / ".env")
url = os.environ["DATABASE_URL"].replace("postgresql://", "postgresql+psycopg://", 1)

with create_engine(url).connect() as connection:
    context.configure(connection=connection, target_metadata=None)
    with context.begin_transaction():
        context.run_migrations()
