"""requests: đơn xin nghỉ (leave) và khiếu nại kết quả (appeal) của sinh viên cho một buổi đã diễn ra."""
from alembic import op

revision = "0003"
down_revision = "0002"


def upgrade() -> None:
    op.execute("""
CREATE TABLE requests (
  id              bigserial PRIMARY KEY,
  kind            text NOT NULL CHECK (kind IN ('leave', 'appeal')),
  session_id      bigint NOT NULL REFERENCES attendance_sessions(id),
  student_id      bigint NOT NULL REFERENCES users(id),
  reason          text NOT NULL,
  attachment_path text,                          -- ảnh giấy tờ, mã hóa như ảnh khác
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  decided_by      bigint REFERENCES users(id),
  decided_at      timestamptz,
  decision_note   text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
-- Mỗi (buổi, sinh viên) chỉ một đơn đang chờ
CREATE UNIQUE INDEX one_pending_request ON requests(session_id, student_id) WHERE status = 'pending';
CREATE INDEX ON requests(student_id);
""")


def downgrade() -> None:
    op.execute("DROP TABLE requests")
