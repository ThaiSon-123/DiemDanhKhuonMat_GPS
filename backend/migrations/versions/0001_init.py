"""init: 10 bảng theo đặc tả mục 9.2 (DDL chép nguyên văn)."""
from alembic import op

revision = "0001"
down_revision = None

DDL = """
CREATE TABLE users (
  id                   bigserial PRIMARY KEY,
  role                 text NOT NULL CHECK (role IN ('student','lecturer','admin')),
  email                text NOT NULL UNIQUE,
  password_hash        text NOT NULL,
  full_name            text NOT NULL,
  student_code         text UNIQUE,              -- chỉ sinh viên
  is_active            boolean NOT NULL DEFAULT true,
  must_change_password boolean NOT NULL DEFAULT true,
  token_version        integer NOT NULL DEFAULT 0, -- tăng khi đổi/đặt lại mật khẩu, vô hiệu hóa → mọi refresh token cũ mất hiệu lực
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE classes (
  id          bigserial PRIMARY KEY,
  code        text NOT NULL,                     -- mã lớp học phần
  name        text NOT NULL,
  semester    text NOT NULL,                     -- vd '2026-1'
  lecturer_id bigint NOT NULL REFERENCES users(id),
  UNIQUE (code, semester)
);

CREATE TABLE enrollments (
  class_id   bigint NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  student_id bigint NOT NULL REFERENCES users(id),
  PRIMARY KEY (class_id, student_id)
);

CREATE TABLE consents (
  user_id     bigint NOT NULL REFERENCES users(id),
  version     text   NOT NULL,                   -- phiên bản văn bản đồng ý
  accepted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at  timestamptz,
  PRIMARY KEY (user_id, version)
);

CREATE TABLE face_templates (
  id            bigserial PRIMARY KEY,
  student_id    bigint NOT NULL REFERENCES users(id),
  model_name    text   NOT NULL,                 -- vd 'arcface_r50_onnx_v1'
  embedding_enc bytea,                           -- NULL sau khi từ chối/thu hồi
  status        text   NOT NULL CHECK (status IN ('pending','approved','rejected','revoked')),
  photos_path   text,                            -- NULL sau khi duyệt/từ chối
  reviewed_by   bigint REFERENCES users(id),
  reject_reason text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  reviewed_at   timestamptz
);
CREATE UNIQUE INDEX one_approved_face ON face_templates(student_id) WHERE status = 'approved';
CREATE UNIQUE INDEX one_pending_face  ON face_templates(student_id) WHERE status = 'pending';

CREATE TABLE attendance_sessions (
  id                bigserial PRIMARY KEY,
  class_id          bigint NOT NULL REFERENCES classes(id),
  opened_by         bigint NOT NULL REFERENCES users(id),
  center_lat        double precision NOT NULL,
  center_lng        double precision NOT NULL,
  center_accuracy_m real NOT NULL,               -- σ_gv
  orig_center_lat   double precision,            -- giữ tâm gốc khi tính lại tâm
  orig_center_lng   double precision,
  base_radius_m     real NOT NULL,               -- r0
  room_check        boolean NOT NULL DEFAULT false,
  room_secret       bytea NOT NULL,
  opened_at         timestamptz NOT NULL DEFAULT now(),
  expires_at        timestamptz NOT NULL,
  closed_at         timestamptz                  -- NULL = chưa đóng tay
);
-- Mỗi lớp tối đa một phiên chưa đóng tay; phiên quá hạn được đóng (ghi closed_at) khi mở phiên mới
CREATE UNIQUE INDEX one_open_session ON attendance_sessions(class_id) WHERE closed_at IS NULL;

CREATE TABLE challenges (
  id         bigserial PRIMARY KEY,
  session_id bigint NOT NULL REFERENCES attendance_sessions(id),
  student_id bigint NOT NULL REFERENCES users(id),
  nonce      text   NOT NULL UNIQUE,             -- secrets.token_urlsafe(32)
  action     text   NOT NULL,                    -- 'turn_left' | 'turn_right' | ...
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at    timestamptz
);
CREATE INDEX ON challenges(session_id, student_id);

CREATE TABLE checkin_attempts (
  id                  bigserial PRIMARY KEY,
  session_id          bigint NOT NULL REFERENCES attendance_sessions(id),
  student_id          bigint NOT NULL REFERENCES users(id),
  challenge_id        bigint NOT NULL UNIQUE REFERENCES challenges(id),
  device_id           text,
  ip                  inet,
  received_at         timestamptz NOT NULL DEFAULT now(),
  gps_samples         jsonb NOT NULL,            -- mẫu thô: [{lat,lng,acc,ts,mock}]
  lat                 double precision,          -- vị trí đã gộp
  lng                 double precision,
  accuracy_m          real,                      -- σ_sv
  distance_m          real,                      -- d
  radius_m            real,                      -- r đã dùng
  room_token_ok       boolean,
  face_score          real,
  liveness_score      real,
  action_ok           boolean,
  result              text NOT NULL CHECK (result IN ('pass','suspicious','fail')),
  fail_step           smallint,                  -- 1..6, bước dừng lại (mục 4.4)
  fail_reason         text,
  flags               jsonb NOT NULL DEFAULT '[]', -- vd ["mock_location","shared_device"]
  evidence_path       text,
  evidence_expires_at timestamptz
);
CREATE INDEX ON checkin_attempts(session_id, student_id);
CREATE INDEX ON checkin_attempts(session_id, device_id);
CREATE INDEX ON checkin_attempts(evidence_expires_at) WHERE evidence_path IS NOT NULL;

CREATE TABLE attendance_records (
  session_id      bigint NOT NULL REFERENCES attendance_sessions(id),
  student_id      bigint NOT NULL REFERENCES users(id),
  status          text NOT NULL CHECK (status IN
                    ('absent','suspicious','present','manual_present','excused','rejected')),
  best_attempt_id bigint REFERENCES checkin_attempts(id),
  decided_by      bigint REFERENCES users(id),   -- NULL = hệ thống quyết; khác NULL = đã khóa
  note            text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, student_id)
);
CREATE INDEX ON attendance_records(student_id);   -- lịch sử chuyên cần của một sinh viên, báo cáo

CREATE TABLE audit_log (
  id         bigserial PRIMARY KEY,
  actor_id   bigint REFERENCES users(id),
  action     text NOT NULL,                      -- 'face.review', 'record.update', 'evidence.view', ...
  target     text NOT NULL,                      -- vd 'attendance_records:12:345'
  before     jsonb,
  after      jsonb,
  ip         inet,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON audit_log(target);
CREATE INDEX ON audit_log(created_at);
"""


def upgrade() -> None:
    op.execute(DDL)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS audit_log, attendance_records, checkin_attempts, challenges, attendance_sessions, face_templates, consents, enrollments, classes, users CASCADE")
