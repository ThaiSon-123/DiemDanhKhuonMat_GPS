"""username: tên đăng nhập riêng cho mọi tài khoản; email thành tùy chọn."""
from alembic import op

revision = "0002"
down_revision = "0001"


def upgrade() -> None:
    op.execute("""
ALTER TABLE users ADD COLUMN username text;
-- Tài khoản đã có: lấy phần trước @ của email; không hợp lệ thì 'user<id>'; trùng thì thêm id.
UPDATE users SET username = CASE WHEN split_part(lower(email), '@', 1) ~ '^[a-z0-9._-]{3,50}$'
                                 THEN split_part(lower(email), '@', 1) ELSE 'user' || id END;
UPDATE users u SET username = u.username || u.id
WHERE EXISTS (SELECT 1 FROM users o WHERE o.username = u.username AND o.id < u.id);
ALTER TABLE users ALTER COLUMN username SET NOT NULL,
                  ADD CONSTRAINT users_username_key UNIQUE (username),
                  ADD CONSTRAINT users_username_format CHECK (username ~ '^[a-z0-9._-]{3,50}$'),
                  ALTER COLUMN email DROP NOT NULL;
""")


def downgrade() -> None:
    op.execute("""
UPDATE users SET email = username || '@local' WHERE email IS NULL;
ALTER TABLE users ALTER COLUMN email SET NOT NULL, DROP COLUMN username;
""")
