"""class_schedules: lịch học hằng tuần của lớp (thứ, giờ, phòng) để sinh viên xem và được nhắc giờ."""
from alembic import op

revision = "0004"
down_revision = "0003"


def upgrade() -> None:
    op.execute("""
CREATE TABLE class_schedules (
  id         bigserial PRIMARY KEY,
  class_id   bigint NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  weekday    smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),   -- 1 = Thứ Hai … 7 = Chủ nhật (ISO 8601)
  start_time time NOT NULL,
  end_time   time NOT NULL CHECK (end_time > start_time),
  room       text
);
CREATE INDEX ON class_schedules(class_id);
""")


def downgrade() -> None:
    op.execute("DROP TABLE class_schedules")
