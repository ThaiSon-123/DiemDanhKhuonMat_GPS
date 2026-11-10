# Ứng dụng điểm danh khuôn mặt + GPS — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Xây backend FastAPI, app Flutter (Android, iOS, Web cho giảng viên và quản trị viên) và các script thí nghiệm theo đúng đặc tả, chạy được trọn luồng đăng ký → mở phiên → điểm danh → duyệt → báo cáo trong một lớp thật.

**Architecture:** Backend đồng bộ (endpoint `def`, FastAPI tự chạy trong thread pool), dùng psycopg 3 với SQL viết tay (CSDL lấy nguyên DDL của đặc tả qua một migration Alembic). Logic quyết định nằm trong các module thuần (`geo`, `room_token`, `face/checks`, `face/verify`) nhận dữ liệu và trả kết quả, nên test không cần DB và script thí nghiệm dùng lại được. Router chỉ kiểm tra quyền và gọi service. Mô hình khuôn mặt nằm sau giao diện `FaceEngine`, nên test API dùng engine giả.

**Tech Stack:** Python 3.12, FastAPI, psycopg[binary,pool] 3, Alembic, PyJWT, argon2-cffi, cryptography (AES-GCM), onnxruntime, opencv-python-headless (YuNet), numpy, pytest + httpx + pgserver (Postgres nhúng để test); Flutter 3 (dio, go_router, flutter_secure_storage, camera, geolocator, mobile_scanner, uuid); PostgreSQL 16; Docker Compose + Caddy để triển khai.

**Spec:** `dac-ta-thiet-ke.md` (bản 2). Đọc cùng plan này; mọi "mục X" bên dưới là mục của đặc tả.

## Global Constraints

- **Giao diện phải làm đúng theo canvas thiết kế** https://claude.ai/artifact/MBn13iMsr2GcsELrV21kzn (24 artboard). Trước khi dựng một màn, đọc artboard tương ứng và chép bố cục, câu chữ, màu, khoảng cách. Token: indigo `#4F46E5`, indigo đậm `#3730A3`, nền `#F5F6FB`, chữ `#1E1B4B`, chữ phụ `#5B6478`, viền `#E6E8F3`; trạng thái xanh lá `#12803C`, cam `#B45309`, đỏ `#C2261D`; font Be Vietnam Pro.
Giá trị lấy nguyên từ đặc tả (mục 4, 6, 9.4, 9.5); chúng nằm trong `backend/config.yaml`, code không hard-code.

- Thử thách: hết hạn **60 s**; tối đa **5 lượt** (số dòng `challenges`) mỗi (phiên, sinh viên); hành động: `turn_left`, `turn_right`.
- Mã phòng: cửa sổ **30 s**, chấp nhận cửa sổ hiện tại và cửa sổ ngay trước; 8 ký tự base32 đầu của `HMAC-SHA256(room_secret, f"{session_id}|{window}")`.
- GPS giảng viên: ≥ **5** mẫu có `acc ≤ 20 m`; GPS sinh viên: ≥ **3** mẫu có `acc ≤ 30 m`; khoảng thời gian mẫu ≤ **20 s**; tốc độ > **30 m/s** là bước nhảy.
- `r = r0 + σ_gv + σ_sv`; `d ≤ r` đạt, `r < d ≤ 2r` lệch nhẹ, `d > 2r` không đạt. `r0` mặc định **20 m**, khoảng **10–50 m**. Thời hạn phiên mặc định **10 phút**.
- Khuôn mặt: mặt rộng ≥ **100 px**; ảnh đăng ký **3–5**; khung hình điểm danh **5–8**; request ≤ **3 MB**; ảnh bằng chứng giữ **30 ngày**.
- Token: access **15 phút**, refresh **7 ngày**; sai mật khẩu **10 lần / 15 phút** cho cùng email thì khóa **15 phút**.
- Định dạng lỗi: `{"error": {"code", "message", "details"}}`; danh sách mã lỗi, mã lý do, mã cờ đúng như mục 9.5. `message` là tiếng Việt.
- Sinh viên không bao giờ nhận điểm số thô hay cờ.
- Đối tượng ngoài phạm vi của người gọi trả **404 `NOT_FOUND`**, không phải 403.
- Mọi thời gian dùng `timestamptz`, JSON trả ISO 8601 có múi giờ.

## Review Focus

Các tình huống đặc tả ngầm yêu cầu nhưng dễ bị bỏ sót; mỗi dòng đã có test ở task sở hữu.

1. **Bấm gửi hai lần / hai request cùng nonce chạy song song** → chỉ một lượt được xử lý, request kia nhận `CHALLENGE_INVALID`; không có hai dòng `checkin_attempts`. Test ở Task 15.
2. **Phiên hết hạn giữa lúc xin thử thách và lúc gửi** (request đến sau `expires_at`) → `409 SESSION_CLOSED`, không ghi lượt, không cập nhật kết quả. Test ở Task 15.
3. **Mẫu GPS rác** (danh sách rỗng, vĩ độ ngoài [-90, 90], `acc ≤ 0`, NaN, `ts` lộn xộn) → `422 VALIDATION_ERROR` hoặc lý do `GPS_ACCURACY_LOW`, không bao giờ 500. Test ở Task 12 và 15.
4. **Khung hình hỏng** (không phải JPEG, ảnh 0 byte, ảnh 8000×8000) → lý do `FACE_NOT_FOUND`, không 500; request > 3 MB → `413 PAYLOAD_TOO_LARGE`. Test ở Task 7 và 15.
5. **Giảng viên đụng lớp không dạy** (mở phiên, xem records, đóng phiên, xem ảnh bằng chứng của lớp khác) → `404 NOT_FOUND`. Test ở Task 14 và 16.

---

## Cấu trúc thư mục

```text
backend/
  pyproject.toml            # deps + pytest config
  config.yaml               # mục 9.4 + các giá trị Global Constraints
  campus.geojson            # đa giác khuôn viên (Polygon, toạ độ [lng, lat])
  alembic.ini
  migrations/versions/0001_init.py      # op.execute(DDL mục 9.2)
  models/                   # file ONNX (gitignore) + README.md ghi nguồn, sha256
  app/
    main.py                 # tạo FastAPI, gắn router, handler lỗi, giới hạn body
    config.py               # Settings (pydantic) đọc config.yaml + biến môi trường
    db.py                   # ConnectionPool, dependency get_conn
    errors.py               # ApiError + exception handlers
    security.py             # băm mật khẩu, JWT, current_user, require_role, khóa đăng nhập
    audit.py                # ghi audit_log
    crypto.py               # AES-GCM + lưu file mã hoá
    routers/ auth.py me.py faces.py sessions.py records.py reports.py admin.py
    services/
      geo.py                # thuần: haversine, gộp mẫu, bán kính, bước nhảy, đa giác, tâm lệch
      room_token.py         # thuần: mã phòng TOTP
      importer.py           # CSV
      sessions.py           # mở/đóng phiên, tính lại tâm
      checkin.py            # cấp thử thách, xử lý 6 bước
      face/ types.py checks.py verify.py onnx_engine.py runtime.py
    jobs/cleanup.py
  tests/ conftest.py fixtures/ test_*.py
mobile/                     # Flutter, một codebase cho Android, iOS, Web
  lib/ main.dart router.dart core/ features/{auth,student,lecturer,admin}/
  test/
experiments/
  spike_face.py metrics.py face_eval.py antispoof_eval.py gps_analysis.py locustfile.py
  tests/test_metrics.py
deploy/ docker-compose.yml Caddyfile backend.Dockerfile
```

---

## Giai đoạn 0 — Thử nhanh chuỗi khuôn mặt (1–2 ngày)

### Task 0: Spike mô hình trên laptop

Không TDD: đây là thử nghiệm để biết sớm mô hình có dùng được không, trước khi đầu tư vào app.

**Files:**
- Create: `experiments/spike_face.py`, `experiments/spike.md`, `backend/models/README.md`

**Interfaces:**
- Produces: danh sách file mô hình trong `backend/models/` (tên file + sha256), và các giá trị hiệu chỉnh ghi vào `experiments/spike.md`: `yaw_sign`, `yaw_threshold`, `min_brightness`, `min_sharpness`. Task 1 chép chúng vào `config.yaml`.

- [ ] **Step 1: Tải mô hình vào `backend/models/`**, ghi nguồn, giấy phép, sha256 vào `models/README.md`:
  - Phát hiện: YuNet `face_detection_yunet_2023mar.onnx` (OpenCV Zoo, MIT).
  - Embedding: InsightFace `w600k_r50.onnx` (buffalo_l) và `w600k_mbf.onnx` (buffalo_s); ghi rõ giấy phép chỉ dùng phi thương mại, nghiên cứu.
  - Anti-spoofing: MiniFASNetV2 (Silent-Face-Anti-Spoofing, Apache-2.0) xuất ONNX, đầu vào 80×80, crop scale 2.7.
- [ ] **Step 2: Viết `spike_face.py`**: mở webcam, mỗi khung hình chạy YuNet → căn chỉnh 112×112 theo 5 điểm (mẫu ArcFace chuẩn) → embedding → spoof score; in ra số mặt, `yaw_proxy`, độ sáng, độ nét, spoof score, cosine với ảnh mẫu của chính mình chụp lúc khởi động.

  `yaw_proxy = (nose_x - (eye_l_x + eye_r_x)/2) / |eye_r_x - eye_l_x|`

- [ ] **Step 3: Đo và ghi vào `spike.md`**:
  - Quay trái, quay phải trên ảnh **chụp bằng camera trước của điện thoại thật** (gửi ảnh từ điện thoại sang, không dùng webcam cho bước này): dấu của `yaw_proxy` khi sinh viên quay sang trái của mình → `yaw_sign` (+1 hoặc -1); giá trị `|yaw_proxy|` khi quay khoảng 20° → `yaw_threshold`.
  - Phòng tối / sáng, ảnh rung / nét → `min_brightness`, `min_sharpness`.
  - Spoof score của: mặt thật, ảnh in, ảnh trên màn hình điện thoại, video trên laptop (mỗi loại ≥ 10 khung hình).
  - Cosine cùng người / khác người (ít nhất 3 người), thời gian mỗi bước trên CPU.
- [ ] **Step 4: Cổng kiểm tra**: spoof score tách được mặt thật với ảnh in và màn hình trên tập nhỏ này, cosine cùng người cao hơn khác người rõ rệt. Nếu anti-spoofing không tách được: ghi vào `spike.md`, thử mô hình khác trước khi sang Task 1; thử thách ngẫu nhiên vẫn là lớp chặn video.
- [ ] **Step 5: Commit** (sau khi Task 1 đã `git init`, hoặc commit cùng Task 1)

---

## Giai đoạn 1 — Nền tảng

### Task 1: Khung backend, cấu hình, lỗi, CSDL và test fixture

**Files:**
- Create: `backend/pyproject.toml`, `backend/config.yaml`, `backend/campus.geojson`, `backend/alembic.ini`, `backend/migrations/env.py`, `backend/migrations/versions/0001_init.py`, `backend/app/{main,config,db,errors}.py`, `backend/tests/conftest.py`, `backend/tests/test_foundation.py`, `.gitignore`

**Interfaces:**
- Produces:
  - `app.config.get_settings() -> Settings` (lru_cache). `Settings.face: FaceCfg` (`model_name, accept_threshold, suspect_threshold, antispoof_threshold, yaw_sign, yaw_threshold, min_brightness, min_sharpness, min_face_px=100, actions=["turn_left","turn_right"]`), `Settings.gps: GpsCfg` (`default_r0_m=20, r0_range_m=(10,50), max_acc_lecturer_m=20, max_acc_student_m=30, min_samples_lecturer=5, min_samples_student=3, max_span_s=20, max_speed_mps=30`), `Settings.session: SessionCfg` (`default_duration_min=10, max_attempts=5, challenge_ttl_s=60, room_token_window_s=30`), `Settings.retention.evidence_days=30`, `Settings.campus_polygon_file`. Từ biến môi trường: `DATABASE_URL`, `JWT_SECRET`, `DATA_KEY` (base64 32 byte), `STORAGE_DIR`.
  - `app.errors.ApiError(status: int, code: str, message: str, details: dict | None = None)`; handler trả envelope. `RequestValidationError` → 422 `VALIDATION_ERROR`, `details` = danh sách `{field, msg}`.
  - `app.db.get_conn() -> Iterator[psycopg.Connection]` (dict_row; commit khi request thành công, rollback khi lỗi).
  - `main.py` gắn `CORSMiddleware(allow_origin_regex=os.environ["CORS_ORIGIN_REGEX"], allow_methods=["*"], allow_headers=["*"])`, vì Flutter Web chạy ở tên miền khác API.
  - Fixture test: `conn`, `client` (TestClient), `make_user(role, **kw) -> dict`, `make_class(lecturer_id, **kw) -> dict`, `enroll(class_id, student_id)`, `auth(user) -> dict` (header). Mỗi test bắt đầu với các bảng đã `TRUNCATE ... RESTART IDENTITY CASCADE`.

- [ ] **Step 1: `git init`, `.gitignore`** (`backend/models/*.onnx`, `.venv`, `storage/`, `mobile/build`).
- [ ] **Step 2: Viết test thất bại** `tests/test_foundation.py`:

```python
def test_migration_creates_10_tables(conn):
    names = {r["table_name"] for r in conn.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name<>'alembic_version'")}
    assert names == {"users","classes","enrollments","consents","face_templates","attendance_sessions",
                     "challenges","checkin_attempts","attendance_records","audit_log"}

def test_api_error_envelope(client):
    r = client.get("/__test/error")          # route chỉ gắn khi testing
    assert r.status_code == 409
    assert r.json() == {"error": {"code": "SESSION_CLOSED", "message": "Phiên điểm danh đã đóng", "details": {}}}

def test_validation_error_envelope(client):
    r = client.post("/auth/login", json={"email": 1})
    assert r.status_code == 422 and r.json()["error"]["code"] == "VALIDATION_ERROR"

def test_cors_allows_configured_origin(client):   # CORS_ORIGIN_REGEX của test: ^http://localhost(:\d+)?$
    r = client.options("/auth/login", headers={"Origin": "http://localhost:5173", "Access-Control-Request-Method": "POST"})
    assert r.headers["access-control-allow-origin"] == "http://localhost:5173"
    r = client.options("/auth/login", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"})
    assert "access-control-allow-origin" not in r.headers

def test_settings_values():
    s = get_settings()
    assert s.session.max_attempts == 5 and s.session.challenge_ttl_s == 60
    assert s.gps.max_acc_student_m == 30 and s.gps.default_r0_m == 20
```

- [ ] **Step 3: Chạy** `cd backend; pytest tests/test_foundation.py -v` → FAIL (chưa có app).
- [ ] **Step 4: Cài đặt.** Migration `0001_init.py` chép **nguyên văn** khối DDL đầu tiên của mục 9.2 vào `op.execute`. `conftest.py`: dùng `DATABASE_URL` nếu có, nếu không thì khởi động `pgserver` trong thư mục tạm (đã chạy được trên máy này), chạy `alembic upgrade head` một lần cho cả phiên test. `config.yaml` theo mục 9.4 cộng các giá trị trong Global Constraints; ngưỡng mô hình lấy từ `spike.md` (sẽ chốt lại ở Task 11).
- [ ] **Step 5: Chạy lại** → PASS.
- [ ] **Step 6: Commit** `feat(backend): khung FastAPI, cấu hình, lỗi, migration CSDL`

### Task 2: Xác thực và phân quyền

**Files:**
- Create: `backend/app/security.py`, `backend/app/routers/auth.py`, `backend/tests/test_auth.py`
- Modify: `backend/tests/conftest.py` (`make_user(..., password="Pass1234")` lưu `hash_password(password)`; `auth(user)` ký access token bằng `create_tokens`)

**Interfaces:**
- Consumes: `get_conn`, `ApiError`, `get_settings`.
- Produces:
  - `hash_password(p: str) -> str`, `verify_password(p: str, h: str) -> bool` (argon2).
  - `create_tokens(user: dict) -> dict` → `{access_token, refresh_token, expires_in: 900}`; JWT có `sub`, `role`, `typ` (`access`/`refresh`), `tv` (token_version).
  - Dependency `current_user(...) -> dict` (dòng `users`); `require_role(*roles) -> Callable` trả dependency. Người dùng `must_change_password` chỉ được gọi `POST /auth/change-password` và `GET /me`; route khác trả 403 `PASSWORD_CHANGE_REQUIRED`.
  - Endpoint: `POST /auth/login`, `POST /auth/refresh`, `POST /auth/change-password` (mục 9.5).

- [ ] **Step 1: Viết test thất bại**:

```python
def test_login_ok_returns_user(client, make_user):
    make_user("student", email="a@x", password="Pass1234", must_change_password=False)
    r = client.post("/auth/login", json={"email": "a@x", "password": "Pass1234"})
    assert r.status_code == 200 and r.json()["expires_in"] == 900
    assert r.json()["user"]["role"] == "student"

def test_login_wrong_password(client, make_user): ...      # 401 AUTH_INVALID_CREDENTIALS
def test_login_locked_after_10_failures(client, make_user):  # lần 11 trong 15 phút → 429 RATE_LIMITED, kể cả mật khẩu đúng
def test_inactive_user_cannot_login(client, make_user): ...  # 401 AUTH_INVALID_CREDENTIALS
def test_expired_access_token(client, make_user, freezer):   # sau 16 phút → 401 AUTH_TOKEN_EXPIRED
def test_refresh_rejected_after_password_change(client, make_user):
    # đổi mật khẩu → refresh token cũ: 401 AUTH_TOKEN_REVOKED; response của change-password có cặp token mới dùng được
def test_must_change_password_blocks_other_routes(client, make_user, auth):
    u = make_user("student", must_change_password=True)
    assert client.get("/me/classes", headers=auth(u)).json()["error"]["code"] == "PASSWORD_CHANGE_REQUIRED"
    assert client.get("/me", headers=auth(u)).status_code == 200
def test_require_role(client, make_user, auth):              # sinh viên gọi GET /faces/pending → 403 FORBIDDEN
```

- [ ] **Step 2: Chạy** `pytest tests/test_auth.py -v` → FAIL.
- [ ] **Step 3: Cài đặt.** Khóa đăng nhập giữ trong bộ nhớ: `dict[email, deque[timestamp]]`, kèm comment `ponytail: chỉ đúng với 1 worker uvicorn; chạy nhiều worker thì chuyển sang bảng hoặc Redis`. `change-password` tăng `token_version`, đặt `must_change_password=false`, trả token mới. Dùng thư viện `freezegun` cho test thời gian.
- [ ] **Step 4: Chạy** → PASS.
- [ ] **Step 5: Commit** `feat(auth): đăng nhập, refresh, đổi mật khẩu, khóa tạm, phân quyền`

### Task 3: Quản trị: người dùng, lớp, nhập CSV, nhật ký

**Files:**
- Create: `backend/app/audit.py`, `backend/app/services/importer.py`, `backend/app/routers/admin.py`, `backend/app/cli.py`, `backend/tests/test_admin.py`, `backend/tests/test_importer.py`

**Interfaces:**
- Consumes: `require_role("admin")`, `hash_password`.
- Produces:
  - `audit.log(conn, actor_id: int, action: str, target: str, before: dict | None = None, after: dict | None = None, ip: str | None = None) -> None`.
  - `importer.run(conn, kind: Literal["users","classes","enrollments"], csv_text: str, dry_run: bool) -> dict` → `{"ok": bool, "errors": [{"line": int, "msg": str}], "created": int, "passwords": [{"email", "temp_password"}]}` (chỉ `users` có `passwords`). Có lỗi thì không ghi dòng nào.
  - Endpoint: CRUD `/admin/users` (có `POST /admin/users/{id}/reset-password`, `POST /admin/users/{id}/deactivate`), `/admin/classes`, `/admin/enrollments`, `POST /admin/import`, `GET /admin/audit-log` (phân trang `page`, `size`, lọc `actor_id`, `action`, `from`, `to`).
  - Lệnh tạo quản trị viên đầu tiên: `python -m app.cli create-admin --email <email>`, in mật khẩu tạm ra màn hình, `must_change_password=true`; email đã tồn tại thì báo lỗi, thoát mã 1.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_import_users_all_or_nothing(conn):
    csv = "role,email,full_name,student_code\nstudent,a@x,A,SV1\nstudent,a@x,B,SV2\n"
    res = importer.run(conn, "users", csv, dry_run=False)
    assert res["ok"] is False and res["errors"] == [{"line": 3, "msg": "Email đã tồn tại: a@x"}]
    assert conn.execute("SELECT count(*) c FROM users").fetchone()["c"] == 0

def test_import_users_creates_temp_passwords(conn): ...  # 2 dòng hợp lệ → created 2, 2 mật khẩu tạm, must_change_password=true
def test_import_dry_run_writes_nothing(conn): ...
def test_import_enrollments_skips_existing(conn): ...     # dòng đã có → không lỗi, không tạo trùng
def test_import_classes_unknown_lecturer(conn): ...       # lỗi theo dòng
def test_deactivate_bumps_token_version(client, ...): ...  # is_active false, token_version tăng, refresh cũ bị từ chối
def test_reset_password_sets_must_change(client, ...): ...
def test_delete_user_with_data_is_blocked(client, ...): ...  # 409, gợi ý vô hiệu hoá
def test_audit_log_paginated(client, ...): ...           # {"items": [...], "total": n}
def test_cli_create_admin(conn): ...                     # tạo admin, must_change_password true; chạy lần 2 cùng email → mã thoát 1
```

- [ ] **Step 2: Chạy** → FAIL. **Step 3: Cài đặt** (đọc CSV bằng module `csv`, chấp nhận BOM UTF-8). **Step 4: Chạy** → PASS.
- [ ] **Step 5: Commit** `feat(admin): quản lý người dùng, lớp, nhập CSV, nhật ký`

### Task 4: `/me`, lớp của tôi, đồng ý dữ liệu

**Files:**
- Create: `backend/app/routers/me.py`, `backend/tests/test_me.py`
- Modify: `backend/config.yaml` (thêm `consent.current_version: v1`)

**Interfaces:**
- Produces: `GET /me`, `GET /me/classes`, `POST /me/consent` (`{"version": "v1"}`), các response đúng mẫu mục 9.5. Hàm `face_state(conn, user_id) -> dict` (`status`, `reject_reason`, `model_ok`, `pending_update`) để Task 9 và 15 dùng lại.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_me_face_none_and_consent_false(client, make_user, auth): ...
def test_me_face_approved_with_pending_update(client, conn, ...):   # 1 approved + 1 pending → status approved, pending_update True
def test_me_face_model_outdated(client, conn, ...):                 # approved nhưng model_name khác cấu hình → model_ok False
def test_consent_wrong_version_422(client, ...): ...
def test_my_classes_student_open_session(client, conn, ...):        # phiên quá hạn → open_session null
def test_my_classes_lecturer_has_student_count(client, conn, ...): ...
```

- [ ] **Step 2–4:** chạy → FAIL, cài đặt, chạy → PASS.
- [ ] **Step 5: Commit** `feat(me): thông tin tài khoản, lớp, đồng ý dữ liệu`

### Task 5: Khung app Flutter

**Files:**
- Create: `mobile/` (`flutter create --platforms=android,ios,web mobile`), `lib/main.dart`, `lib/router.dart`, `lib/core/{api_client,api_error,token_store,device_id}.dart`, `lib/features/auth/{login_page,change_password_page}.dart`, `test/core/api_client_test.dart`, `test/features/login_page_test.dart`

**Interfaces:**
- Consumes: các endpoint của Task 2 và 4.
- Produces:
  - `class ApiError implements Exception { final int status; final String code; final String message; final Map<String, dynamic> details; }`
  - `class ApiClient { ApiClient(String baseUrl, TokenStore store, {void Function()? onLoggedOut}); Future<dynamic> get(String path, {Map<String, dynamic>? query}); Future<dynamic> post(String path, {Object? data}); Future<dynamic> patch(...); Future<dynamic> delete(...); Future<dynamic> postMultipart(String path, {required Map<String, List<Uint8List>> files, Map<String, String> fields = const {}}); }`. Khi gặp `AUTH_TOKEN_EXPIRED` thì gọi `/auth/refresh` một lần rồi gửi lại; gặp `AUTH_TOKEN_REVOKED` thì xóa token và gọi `onLoggedOut`.
  - `Future<String> deviceId()` (UUID v4 lưu trong secure storage).
  - Router theo vai trò: `/student`, `/lecturer`, `/admin`; `must_change_password` → `/change-password`.

- [ ] **Step 1: Viết test thất bại** (dio có adapter giả):

```dart
test('refresh once then retry on AUTH_TOKEN_EXPIRED', () async { /* lần 1: 401 AUTH_TOKEN_EXPIRED; /auth/refresh 200; lần 2: 200 → kết quả trả về, refresh gọi đúng 1 lần */ });
test('AUTH_TOKEN_REVOKED clears tokens and calls onLoggedOut', () async { ... });
test('error envelope parsed into ApiError', () async { /* code, message, details đúng */ });
testWidgets('login shows server message on AUTH_INVALID_CREDENTIALS', (t) async { ... });
testWidgets('must_change_password routes to change password page', (t) async { ... });
```

- [ ] **Step 2: Chạy** `cd mobile; flutter test` → FAIL. **Step 3: Cài đặt.** **Step 4: Chạy** → PASS; `flutter build web` thành công.
- [ ] **Step 5: Commit** `feat(mobile): khung app, API client, đăng nhập, định tuyến theo vai trò`

---

## Giai đoạn 2 — Lõi học máy

### Task 6: Mã hoá dữ liệu và lưu file

**Files:**
- Create: `backend/app/crypto.py`, `backend/tests/test_crypto.py`

**Interfaces:**
- Produces: `encrypt(data: bytes) -> bytes` (nonce 12 byte ‖ ciphertext), `decrypt(blob: bytes) -> bytes`, `save_blob(rel_path: str, data: bytes) -> str`, `load_blob(rel_path: str) -> bytes`, `delete_blob(rel_path: str) -> None` (không lỗi nếu file đã mất). File nằm dưới `STORAGE_DIR`, luôn được mã hoá. `embedding_to_bytes(v: np.ndarray) -> bytes` / `embedding_from_bytes(b: bytes) -> np.ndarray` (float32).

- [ ] **Step 1: Viết test thất bại**:

```python
def test_roundtrip(): assert decrypt(encrypt(b"abc")) == b"abc"
def test_nonce_differs(): assert encrypt(b"abc") != encrypt(b"abc")
def test_tamper_detected():  # sửa 1 byte → InvalidTag
def test_blob_on_disk_is_not_plaintext(tmp_path): ...
def test_rel_path_cannot_escape_storage(): # save_blob("../x", ...) → ValueError
def test_embedding_roundtrip(): ...       # 512 float32
```

- [ ] **Step 2–4:** FAIL → cài đặt (`cryptography.hazmat.primitives.ciphers.aead.AESGCM`) → PASS.
- [ ] **Step 5: Commit** `feat(crypto): AES-GCM cho embedding và ảnh`

### Task 7: Kiểm tra khuôn mặt thuần (không cần mô hình)

**Files:**
- Create: `backend/app/services/face/{types,checks,verify}.py`, `backend/tests/face_fakes.py`, `backend/tests/test_face_checks.py`, `backend/tests/test_face_verify.py`

**Interfaces:**
- Produces:

```python
@dataclass(frozen=True)
class FrameAnalysis:
    face_count: int                 # 0 khi giải mã ảnh lỗi
    face_width_px: float
    brightness: float               # trung bình xám vùng mặt, 0-255
    sharpness: float                # phương sai Laplacian vùng mặt
    yaw_proxy: float | None
    embedding: np.ndarray | None    # đã chuẩn hoá L2
    spoof_score: float | None       # xác suất người thật, 0-1

class FaceEngine(Protocol):
    def analyze(self, jpeg: bytes, *, embed: bool, spoof: bool) -> FrameAnalysis: ...

@dataclass(frozen=True)
class FaceResult:
    status: Literal["pass", "borderline", "fail"]
    reason: str | None              # mã lý do mục 9.5
    face_score: float | None        # trung vị cosine
    liveness_score: float | None
    action_ok: bool | None
    best_frame: int | None          # chỉ số khung nét nhất có mặt

# checks.py
def quality_reason(a: FrameAnalysis, cfg: FaceCfg) -> str | None   # FACE_NOT_FOUND | MULTIPLE_FACES | LOW_LIGHT | BLURRY
def action_done(yaws: list[float | None], action: str, cfg: FaceCfg) -> bool
def match_scores(embs: list[np.ndarray], template: np.ndarray) -> tuple[float, float]  # (trung vị, nhỏ nhất)
def face_status(median: float, minimum: float, cfg: FaceCfg) -> Literal["pass", "borderline", "fail"]
# verify.py
def verify_checkin(frames: list[bytes], action: str, template: np.ndarray, engine: FaceEngine, cfg: FaceCfg) -> FaceResult
def build_template(photos: list[bytes], engine: FaceEngine, cfg: FaceCfg) -> tuple[np.ndarray | None, list[dict]]  # (vector, [{index, reason}])
```

- `tests/face_fakes.py`: `FakeEngine(results: dict[bytes, FrameAnalysis])` trả kết quả soạn sẵn theo nội dung ảnh, để Task 9 và 15 dùng lại.

- [ ] **Step 1: Viết test thất bại** (cfg test: `accept=0.5, suspect=0.4, antispoof=0.5, yaw_sign=1, yaw_threshold=0.25, min_brightness=60, min_sharpness=50`):

```python
def test_quality_reasons():
    assert quality_reason(fa(face_count=0), cfg) == "FACE_NOT_FOUND"
    assert quality_reason(fa(face_count=2), cfg) == "MULTIPLE_FACES"
    assert quality_reason(fa(face_width_px=99), cfg) == "FACE_NOT_FOUND"
    assert quality_reason(fa(brightness=59), cfg) == "LOW_LIGHT"
    assert quality_reason(fa(sharpness=49), cfg) == "BLURRY"
    assert quality_reason(fa(), cfg) is None

def test_action_turn_left_needs_frontal_then_turn():
    # quy ước: giá trị * yaw_sign < 0 là quay sang trái của sinh viên
    assert action_done([0.0, -0.1, -0.3], "turn_left", cfg) is True
    assert action_done([-0.3, 0.0], "turn_left", cfg) is False     # quay trước rồi mới nhìn thẳng
    assert action_done([0.0, 0.3], "turn_left", cfg) is False      # sai hướng
    assert action_done([0.0, -0.2], "turn_left", cfg) is False     # chưa đủ ngưỡng
    assert action_done([None, 0.05, None, -0.26], "turn_left", cfg) is True

def test_face_status_thresholds():
    assert face_status(0.55, 0.45, cfg) == "pass"
    assert face_status(0.45, 0.42, cfg) == "borderline"
    assert face_status(0.60, 0.39, cfg) == "fail"     # một khung dưới ngưỡng nghi ngờ → không đạt

def test_verify_spoof_detected(): ...         # 3 khung nét nhất, min spoof < 0.5 → fail SPOOF_DETECTED
def test_verify_action_not_detected(): ...
def test_verify_mismatch(): ...               # FACE_MISMATCH
def test_verify_needs_3_quality_frames():     # chỉ 2 khung đạt → fail, reason = lỗi chất lượng xuất hiện nhiều nhất
def test_verify_garbage_frames_no_exception(): # b"", b"notjpeg" → FakeEngine trả face_count=0 → FACE_NOT_FOUND
def test_build_template_inconsistent_photo(): # ảnh của người khác → issues [{"index": 2, "reason": "INCONSISTENT_FACE"}]
def test_build_template_returns_unit_vector(): ...
```

- [ ] **Step 2: Chạy** `pytest tests/test_face_checks.py tests/test_face_verify.py -v` → FAIL.
- [ ] **Step 3: Cài đặt.** `action_done`: đổi dấu theo hướng (`turn_left` → `-1`, `turn_right` → `+1`), tính `v = yaw * yaw_sign * dir`; đạt khi có i < j với `|yaw_i| ≤ T/2` và `v_j ≥ T`. `verify_checkin` theo thứ tự: chất lượng (cần ≥ 3 khung đạt) → hành động → anti-spoofing (3 khung nét nhất, lấy min) → so khớp (mọi khung đạt chất lượng). `build_template`: mỗi ảnh phải đạt chất lượng và spoof; cosine của mỗi ảnh với trung bình các ảnh còn lại ≥ `suspect_threshold`; trả trung bình đã chuẩn hoá.
- [ ] **Step 4: Chạy** → PASS.
- [ ] **Step 5: Commit** `feat(face): kiểm tra chất lượng, hành động, liveness, so khớp`

### Task 8: Engine ONNX thật

**Files:**
- Create: `backend/app/services/face/onnx_engine.py`, `backend/app/services/face/runtime.py`, `backend/tests/test_onnx_engine.py`, `backend/tests/fixtures/faces/` (ảnh của người phát triển: `a1.jpg`, `a2.jpg`, `b1.jpg`, `print_a.jpg`, `blank.jpg`)

**Interfaces:**
- Consumes: `FrameAnalysis`, `FaceEngine` (Task 7), các file mô hình (Task 0).
- Produces: `class OnnxFaceEngine(FaceEngine): __init__(self, model_dir: Path, model_name: str)`; `runtime.get_engine() -> FaceEngine` (khởi tạo một lần, FastAPI dependency để test override); `runtime.infer(fn, *args)` chạy dưới `threading.BoundedSemaphore(os.cpu_count())`.

- [ ] **Step 1: Viết test thất bại** (đánh dấu `@pytest.mark.models`, tự skip khi thiếu file `.onnx`):

```python
def test_same_person_scores_higher(engine):
    a1, a2, b1 = (engine.analyze(load(n), embed=True, spoof=False) for n in ("a1", "a2", "b1"))
    assert a1.face_count == 1
    assert cos(a1.embedding, a2.embedding) > cos(a1.embedding, b1.embedding) + 0.2

def test_blank_and_garbage(engine):
    assert engine.analyze(load("blank"), embed=True, spoof=True).face_count == 0
    assert engine.analyze(b"not a jpeg", embed=True, spoof=True).face_count == 0

def test_huge_image_is_downscaled(engine):      # ảnh 8000x8000 → không lỗi, xử lý < 2 s
def test_print_attack_scores_lower(engine): ... # spoof_score(print_a) < spoof_score(a1)
```

- [ ] **Step 2: Chạy** `pytest -m models -v` → FAIL.
- [ ] **Step 3: Cài đặt.** Giải mã bằng `cv2.imdecode` (lỗi → `face_count=0`); thu nhỏ để cạnh dài ≤ 1280 px trước khi phát hiện; YuNet `cv2.FaceDetectorYN`; căn chỉnh bằng `cv2.estimateAffinePartial2D` về 5 điểm chuẩn ArcFace 112×112; `yaw_proxy` theo công thức ở Task 0.
- [ ] **Step 4: Chạy** → PASS.
- [ ] **Step 5: Commit** `feat(face): engine ONNX (YuNet, ArcFace, MiniFASNet)`

### Task 9: API đăng ký, duyệt và xóa khuôn mặt

**Files:**
- Create: `backend/app/routers/faces.py`, `backend/tests/test_faces_api.py`
- Modify: `backend/app/routers/admin.py` (deactivate gọi `delete_face_data`)

**Interfaces:**
- Consumes: `build_template`, `get_engine` (override bằng `FakeEngine` trong test), `crypto.*`, `audit.log`, `face_state` (Task 4).
- Produces: `POST /faces/enroll`, `GET /faces/pending`, `GET /faces/{id}/photos`, `POST /faces/{id}/review`, `DELETE /me/face`, `DELETE /admin/users/{id}/face`; hàm `delete_face_data(conn, student_id: int, actor_id: int) -> None` (thu hồi mọi mẫu, xóa embedding và file, ghi nhật ký); hàm `approved_template(conn, student_id, model_name) -> np.ndarray | None` để Task 15 dùng.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_enroll_requires_consent(...):            # 409 CONSENT_REQUIRED
def test_enroll_photo_count(...):                  # 2 ảnh hoặc 6 ảnh → 422 VALIDATION_ERROR
def test_enroll_rejected_photos(...):              # 422 ENROLL_REJECTED, details.photos[{index, reason}]
def test_enroll_creates_pending_with_encrypted_photos(...):  # 201; photos_path có, file trên đĩa không phải JPEG thô
def test_second_pending_conflict(...):             # 409 FACE_PENDING_EXISTS
def test_lecturer_sees_only_own_class_pending(...):
def test_lecturer_review_other_class_404(...):
def test_view_photos_writes_audit(...):            # audit_log action 'face.photos.view'
def test_approve_deletes_photos_and_revokes_old(...):
    # có approved cũ + pending mới → duyệt → mẫu cũ 'revoked', embedding_enc NULL; ảnh pending bị xóa, photos_path NULL
def test_reject_requires_reason(...):              # 422
def test_delete_my_face(...):                      # mọi mẫu → revoked, embedding_enc NULL, file bị xóa, ghi nhật ký
def test_admin_delete_face_and_deactivate(...):    # DELETE /admin/users/{id}/face và deactivate (Task 3) đều xóa dữ liệu khuôn mặt (mục 4.6)
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS.
- [ ] **Step 5: Commit** `feat(faces): đăng ký, duyệt, xóa dữ liệu khuôn mặt`

### Task 10: Màn hình đăng ký và duyệt khuôn mặt (Flutter)

**Files:**
- Create: `mobile/lib/features/student/{home_page,consent_page,enroll_page,my_face_page,permissions_page}.dart`, `mobile/lib/features/lecturer/face_review_page.dart`, `mobile/lib/core/capture.dart`, `mobile/test/features/enroll_test.dart`, `mobile/test/features/face_review_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (Task 5), endpoint Task 4 và 9.
- Produces: `Future<Uint8List> captureJpeg(CameraController c)` (cạnh dài ≤ 1280 px, chất lượng 80) dùng lại ở Task 18; `PermissionsPage(kind: PermissionKind)` dùng lại cho camera, vị trí, Bluetooth.

- [ ] **Step 1: Viết widget test thất bại** (camera và API giả):

```dart
testWidgets('home shows enroll CTA when face.status == none', ...);
testWidgets('consent required before enroll', ...);
testWidgets('enroll shows per-photo reasons from ENROLL_REJECTED', ...);  // "Ảnh 3: Ảnh bị mờ..."
testWidgets('my face: delete asks confirmation then calls DELETE /me/face', ...);
testWidgets('review: reject requires reason', ...);
testWidgets('camera permission denied shows PermissionsPage', ...);
```

- [ ] **Step 2–4:** `flutter test` → FAIL → cài đặt → PASS. Thử tay trên một máy Android thật: đăng ký, duyệt trên Flutter Web.
- [ ] **Step 5: Commit** `feat(mobile): đồng ý, đăng ký, xóa, duyệt khuôn mặt`

### Task 11: Thí nghiệm chọn mô hình và ngưỡng (cổng giai đoạn 2)

**Files:**
- Create: `experiments/metrics.py`, `experiments/tests/test_metrics.py`, `experiments/face_eval.py`, `experiments/antispoof_eval.py`, `experiments/results/`
- Modify: `backend/config.yaml` (`face.model_name`, các ngưỡng)

**Interfaces:**
- Consumes: `OnnxFaceEngine`, `verify.match_scores`.
- Produces: `far_frr(genuine: list[float], impostor: list[float], thr: float) -> tuple[float, float]`, `eer(genuine, impostor) -> tuple[float, float]` (EER, ngưỡng), `threshold_at_far(impostor, target_far: float) -> float`, `apcer_bpcer(attack_scores, bona_scores, thr) -> tuple[float, float]`.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_far_frr():
    assert far_frr([0.9, 0.8, 0.7], [0.1, 0.2, 0.75], 0.75) == (1/3, 1/3)
def test_threshold_at_far():
    t = threshold_at_far([0.1, 0.2, 0.3, 0.9], 0.25)
    assert far_frr([1.0], [0.1, 0.2, 0.3, 0.9], t)[0] <= 0.25 and t <= 0.9
def test_apcer_bpcer():
    assert apcer_bpcer([0.2, 0.6], [0.9, 0.4], 0.5) == (0.5, 0.5)
```

- [ ] **Step 2–4:** `pytest experiments/tests -v` → FAIL → cài đặt → PASS.
- [ ] **Step 5: Chạy thí nghiệm** trên LFW và tập tự thu (mục 10.1; chia 70/30, chọn ngưỡng trên 70 %, báo cáo trên 30 %): `python experiments/face_eval.py --data <thư mục> --models w600k_r50,w600k_mbf` → `results/face_*.csv` + ROC; `python experiments/antispoof_eval.py ...` → APCER, BPCER.
- [ ] **Step 6: Cổng kiểm tra**: chốt `model_name`, `accept_threshold` (FAR ≤ 0,1 % trên tập kiểm chứng), `suspect_threshold`, `antispoof_threshold` vào `config.yaml`. **Chỉ sau bước này mới cho sinh viên đăng ký thật.**
- [ ] **Step 7: Commit** `exp: chọn mô hình và ngưỡng`

---

## Giai đoạn 3 — GPS, phiên và điểm danh

### Task 12: Hàm vị trí thuần

**Files:**
- Create: `backend/app/services/geo.py`, `backend/tests/test_geo.py`

**Interfaces:**
- Produces:

```python
@dataclass(frozen=True)
class Sample: lat: float; lng: float; acc: float; ts: int; mock: bool = False   # ts: mili giây
@dataclass(frozen=True)
class Fix: lat: float; lng: float; acc: float

def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float          # R = 6371000
def aggregate(samples: list[Sample], max_acc: float, min_count: int, max_span_s: float) -> Fix | None
def adaptive_radius(r0: float, sigma_gv: float, sigma_sv: float) -> float
def classify(d: float, r: float) -> Literal["ok", "drift", "far"]
def has_jump(samples: list[Sample], max_speed: float) -> bool
def jump_from_previous(prev: Fix, prev_t: float, cur: Fix, cur_t: float, max_speed: float) -> bool  # giây
def load_campus(path: str) -> list[tuple[float, float]]                                # vòng ngoài, (lng, lat)
def in_polygon(lat: float, lng: float, ring: list[tuple[float, float]]) -> bool       # ray casting
def suggest_recenter(center: tuple[float, float], positions: list[tuple[float, float]], r0: float) -> bool
def recenter(center: tuple[float, float], positions: list[tuple[float, float]]) -> tuple[float, float]
```

- [ ] **Step 1: Viết test thất bại**:

```python
def test_haversine():
    assert haversine_m(21.0, 105.0, 21.0, 105.001) == pytest.approx(103.8, abs=0.5)
    assert haversine_m(21.0, 105.0, 21.0, 105.0) == 0

def test_aggregate_median_and_filter():
    s = [Sample(21.0, 105.0, 10, 0), Sample(21.0002, 105.0, 12, 1000), Sample(21.0001, 105.0, 8, 2000), Sample(22.0, 106.0, 80, 3000)]
    f = aggregate(s, max_acc=30, min_count=3, max_span_s=20)
    assert (f.lat, f.lng, f.acc) == (21.0001, 105.0, 10)

def test_aggregate_rejects():
    ok = [Sample(21, 105, 10, i * 1000) for i in range(3)]
    assert aggregate(ok[:2], 30, 3, 20) is None                                    # thiếu mẫu
    assert aggregate(ok[:2] + [Sample(21, 105, 10, 25_000)], 30, 3, 20) is None     # span 25 s > 20 s
    assert aggregate([], 30, 3, 20) is None

def test_classify_boundaries():
    assert classify(30, 30) == "ok" and classify(30.1, 30) == "drift"
    assert classify(60, 30) == "drift" and classify(60.1, 30) == "far"

def test_adaptive_radius(): assert adaptive_radius(20, 8, 14) == 42
def test_has_jump(): ...            # 2 mẫu cách 100 m trong 1 s → True; 10 m trong 1 s → False; ts trùng nhau không chia cho 0
def test_in_polygon(): ...          # hình vuông: điểm trong, ngoài, đúng trên cạnh (coi là trong)
def test_suggest_recenter():
    c = (21.0, 105.0)
    east = [(21.0, 105.0004 + i * 1e-5) for i in range(5)]   # ~42-46 m về phía đông
    assert suggest_recenter(c, east, r0=20) is True
    assert suggest_recenter(c, east[:4], r0=20) is False     # chưa đủ 5
    spread = [(21.0004, 105.0), (20.9996, 105.0), (21.0, 105.0004), (21.0, 104.9996), (21.0004, 105.0004)]
    assert suggest_recenter(c, spread, r0=20) is False       # lệch tứ phía
def test_recenter_median(): ...
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS. `suggest_recenter`: ≥ 5 vị trí, trung vị khoảng cách > r0, và > 70 % hướng nằm trong ±45° quanh hướng trung bình (trung bình vòng tròn của các góc).
- [ ] **Step 5: Commit** `feat(geo): gộp mẫu, bán kính thích ứng, bước nhảy, khuôn viên, tâm lệch`

### Task 13: Mã phòng

**Files:**
- Create: `backend/app/services/room_token.py`, `backend/tests/test_room_token.py`

**Interfaces:**
- Produces: `room_code(secret: bytes, session_id: int, t: float, window_s: int = 30) -> str`, `verify_room_code(code: str, secret: bytes, session_id: int, now: float, window_s: int = 30) -> bool`, `window_end(t: float, window_s: int = 30) -> float`.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_code_shape():
    c = room_code(b"k" * 32, 41, 1_000_000.0)
    assert len(c) == 8 and c.isalnum() and c.isupper()
def test_window_acceptance():
    c = room_code(b"k" * 32, 41, 990.0)                   # cửa sổ 33
    assert verify_room_code(c, b"k" * 32, 41, 1000.0)     # cửa sổ 33 → đúng cửa sổ
    assert verify_room_code(c, b"k" * 32, 41, 1029.0)     # cửa sổ 34 → cửa sổ trước, vẫn nhận
    assert not verify_room_code(c, b"k" * 32, 41, 1050.0) # cửa sổ 35 → hết hạn
def test_bound_to_session(): assert room_code(b"k" * 32, 41, 0) != room_code(b"k" * 32, 42, 0)
def test_case_and_garbage(): ...                          # chữ thường vẫn nhận; "" và None → False
```

- [ ] **Step 2–4:** FAIL → cài đặt (`hmac.compare_digest`) → PASS.
- [ ] **Step 5: Commit** `feat(room): mã phòng xoay vòng`

### Task 14: Mở phiên, đóng phiên, mã phòng, lịch sử phiên

**Files:**
- Create: `backend/app/services/sessions.py`, `backend/app/routers/sessions.py` (phần phiên), `backend/tests/test_sessions_api.py`

**Interfaces:**
- Consumes: `geo.aggregate`, `geo.in_polygon`, `geo.load_campus`, `room_token.*`.
- Produces:
  - `is_open(session: dict, now: datetime) -> bool` (`closed_at IS NULL and now < expires_at`).
  - `load_session_for_lecturer(conn, session_id, lecturer_id) -> dict` (không phải lớp mình → 404).
  - `open_session(conn, lecturer: dict, req: OpenSessionIn, now) -> dict`: chạy trong một transaction: đóng phiên quá hạn còn treo của lớp (`closed_at = expires_at`), kiểm tra lớp không có phiên đang mở (`409 SESSION_ALREADY_OPEN`), gộp mẫu GPS (`422 GPS_ACCURACY_LOW`), kiểm tra đa giác (`422 OUTSIDE_CAMPUS`), insert phiên với `room_secret = secrets.token_bytes(32)`, insert dòng `absent` (câu SQL mục 9.2).
  - Endpoint: `POST /sessions`, `POST /sessions/{id}/close`, `GET /sessions/{id}/room-token`, `GET /classes/{id}/sessions`.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_open_creates_absent_rows(...):              # lớp 3 SV → 3 dòng absent; response có center, expires_at = now + 10 phút
def test_open_requires_5_good_samples(...):          # 4 mẫu acc ≤ 20 → 422 GPS_ACCURACY_LOW
def test_open_outside_campus(...):                   # 422 OUTSIDE_CAMPUS
def test_open_twice_conflict(...):                   # 409 SESSION_ALREADY_OPEN
def test_open_after_expired_session_ok(...):         # phiên cũ quá hạn chưa đóng → mở mới được, phiên cũ có closed_at
def test_r0_out_of_range(...):                       # base_radius_m = 5 hoặc 60 → 422
def test_lecturer_other_class_404(...):              # mở phiên, đóng phiên, lấy room-token lớp khác → 404 (Review Focus 5)
def test_room_token_when_disabled(...):              # room_check false → 409 với code ROOM_CHECK_DISABLED
def test_close_then_history(...):                    # GET /classes/{id}/sessions có số có mặt / vắng
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS.
- [ ] **Step 5: Commit** `feat(sessions): mở, đóng phiên, mã phòng, lịch sử`

### Task 15: Cấp thử thách và xử lý điểm danh 6 bước

**Files:**
- Create: `backend/app/services/checkin.py`, `backend/tests/test_checkin.py`
- Modify: `backend/app/routers/sessions.py` (thêm `/challenge`, `/checkin`), `backend/app/main.py` (giới hạn body 3 MB → 413)

**Interfaces:**
- Consumes: `is_open`, `face_state`, `approved_template`, `verify_checkin`, `geo.*`, `verify_room_code`, `runtime.infer`, `crypto.save_blob`.
- Produces:
  - `issue_challenge(conn, session_id: int, student: dict, now) -> dict` → `{nonce, action, expires_at, attempts_left, room_check}`. Kiểm tra theo thứ tự: phiên tồn tại và sinh viên thuộc lớp (404) → phiên mở (`SESSION_CLOSED`) → mẫu đã duyệt với mô hình hiện tại (`FACE_NOT_ENROLLED`) → chưa `present`/`manual_present` (`ALREADY_PRESENT`) → số challenge < 5 (`ATTEMPTS_EXHAUSTED`). `action = secrets.choice(cfg.face.actions)`.
  - `class CheckinMeta(BaseModel)`: `nonce: str`, `device_id: str`, `room_token: str | None`, `gps_samples: list[SampleIn]` (1–100 phần tử; `lat ∈ [-90, 90]`, `lng ∈ [-180, 180]`, `acc > 0`, số hữu hạn).
  - `process_checkin(conn, session_id: int, student: dict, frames: list[bytes], meta: CheckinMeta, ip: str, engine: FaceEngine, now) -> dict` → response mục 9.5 (`result`, `record_status`, `reason`, `attempts_left`).
  - `collect_flags(face: FaceResult, loc: str, samples: list[Sample], jump_prev: bool, shared_device: bool, token_burst: bool) -> list[str]`: thuần; kết quả `pass` khi và chỉ khi danh sách cờ rỗng.

- [ ] **Step 1: Viết test thất bại** (engine giả; sinh viên có mẫu đã duyệt; tâm phiên (21.0, 105.0), σ_gv = 8, r0 = 20):

```python
def test_happy_path_present(...):            # d ≈ 10 m, mặt pass → 200 pass, record 'present', attempts_left 4
def test_drift_is_suspicious(...):           # d ≈ 50 m, σ_sv = 10 → r = 38, lệch nhẹ → suspicious, flags ['LOCATION_DRIFT']
def test_far_fails_without_running_face(...):# d ≈ 500 m → fail GPS_TOO_FAR, engine.analyze không được gọi
def test_low_accuracy(...):                  # mọi mẫu acc 40 → fail GPS_ACCURACY_LOW (trần σ_max_sv)
def test_mock_location_flag(...):            # mặt pass, d ok, mock True → suspicious ['MOCK_LOCATION']
def test_shared_device_flag(...):            # SV khác đã dùng cùng device_id trong phiên → ['SHARED_DEVICE']
def test_borderline_face(...):               # → suspicious ['FACE_BORDERLINE']
def test_spoof_reason(...):                  # → fail SPOOF_DETECTED, record vẫn 'absent'
def test_room_token_required_when_enabled(...):  # thiếu/sai → fail ROOM_TOKEN_INVALID, có ghi attempt fail_step 3
def test_fail_never_downgrades_present(...): # present rồi gửi lượt fail → vẫn present
def test_lecturer_decision_locked(...):      # decided_by có giá trị → pass không ghi đè
def test_late_enrolled_student(...):         # vào lớp sau khi mở phiên (không có dòng absent) → present
def test_attempts_exhausted(...):            # challenge thứ 6 → 429 ATTEMPTS_EXHAUSTED
def test_already_present_challenge(...):     # 409 ALREADY_PRESENT
def test_nonce_reuse(...):                   # gửi lại cùng nonce → 409 CHALLENGE_INVALID, chỉ 1 attempt
def test_nonce_other_student(...):           # 409 CHALLENGE_INVALID
def test_concurrent_same_nonce(...):         # 2 thread gửi cùng lúc → đúng 1 thành công, 1 CHALLENGE_INVALID (Review Focus 1)
def test_session_expired_between(...):       # freezer: xin thử thách ở phút 9:50, gửi ở phút 10:05 → 409 SESSION_CLOSED, không attempt (Review Focus 2)
def test_gps_garbage_422(...):               # [], lat 200, acc 0, NaN → 422 VALIDATION_ERROR (Review Focus 3)
def test_payload_too_large(...):             # 3,1 MB → 413 PAYLOAD_TOO_LARGE (Review Focus 4)
def test_frame_count(...):                   # 4 hoặc 9 khung → 422
def test_suspicious_saves_evidence(...):     # evidence_path có, evidence_expires_at = now + 30 ngày; pass/fail không lưu
def test_student_response_hides_scores(...): # response không có face_score, flags
```

- [ ] **Step 2: Chạy** `pytest tests/test_checkin.py -v` → FAIL.
- [ ] **Step 3: Cài đặt** đúng thứ tự mục 4.4. Bước 2 dùng câu `UPDATE challenges ... RETURNING` của mục 9.2 (đây là chỗ chặn request song song). Từ bước 3 trở đi luôn insert `checkin_attempts` (kèm `fail_step`, `radius_m`, `distance_m`, `gps_samples` thô), rồi nếu `pass`/`suspicious` thì chạy câu `INSERT ... ON CONFLICT` của mục 9.2. Cờ `ROOM_TOKEN_BURST`: ≥ 3 lượt cùng `room_token` và cùng `ip` trong 10 giây. Giới hạn body: middleware đọc `Content-Length` (và đếm khi stream) > 3 MB → 413.
- [ ] **Step 4: Chạy** → PASS.
- [ ] **Step 5: Commit** `feat(checkin): thử thách và điểm danh 6 bước`

### Task 16: Danh sách thời gian thực, duyệt tay, tính lại tâm, ảnh bằng chứng, báo cáo

**Files:**
- Create: `backend/app/routers/records.py`, `backend/app/routers/reports.py`, `backend/tests/test_records_api.py`, `backend/tests/test_reports.py`
- Modify: `backend/app/services/sessions.py` (thêm `recenter_session`), `backend/app/routers/me.py` (thêm `/me/attendance`)

**Interfaces:**
- Consumes: `load_session_for_lecturer`, `geo.suggest_recenter`, `geo.recenter`, `geo.classify`, `audit.log`, `crypto.load_blob`.
- Produces: `GET /sessions/{id}/records` (đúng mẫu mục 9.5, có `recenter_suggested`), `PATCH /sessions/{id}/records/{student_id}`, `POST /sessions/{id}/recenter` → `{center, re_evaluated}`, `GET /attempts/{id}/evidence` (`image/jpeg`), `GET /reports/classes/{id}` (JSON; `?format=csv` → `text/csv` có BOM), `GET /me/attendance`. `recenter_session(conn, session, now) -> dict`: lưu `orig_center_*` lần đầu, tính tâm mới từ vị trí các lượt có `face_score` qua ngưỡng chấp nhận, chấm lại `distance_m/radius_m` của các lượt có cờ `LOCATION_DRIFT`; dòng chưa có quyết định tay mà hết cờ thì nâng lên `present`.

- [ ] **Step 1: Viết test thất bại**:

```python
def test_records_counts_and_last_attempt(...): ...
def test_recenter_suggested_flag(...): ...           # 5 lượt qua mặt lệch cùng hướng → True
def test_recenter_upgrades_drift_only(...):          # lượt drift thành ok → present; lượt FACE_BORDERLINE vẫn suspicious; không hạ ai
def test_recenter_keeps_original_center(...):        # gọi 2 lần → orig_center vẫn là tâm ban đầu
def test_patch_record_locks_and_audits(...):         # decided_by, note; audit before/after
def test_patch_after_close_allowed(...): ...
def test_patch_invalid_status(...):                  # 'present' (trạng thái hệ thống) → 422
def test_evidence_other_class_404(...):              # Review Focus 5
def test_evidence_view_audited(...): ...
def test_report_counts(...):                         # khớp câu báo cáo mục 9.2 (co_mat, vang_co_phep, vang, chua_duyet, so_buoi)
def test_report_csv_has_bom(...):                    # body bắt đầu bằng b'\xef\xbb\xbf'
def test_me_attendance_only_mine(...): ...
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS.
- [ ] **Step 5: Commit** `feat(records): theo dõi, duyệt tay, tính lại tâm, báo cáo`

### Task 17: Tác vụ dọn dữ liệu

**Files:**
- Create: `backend/app/jobs/cleanup.py`, `backend/tests/test_cleanup.py`

**Interfaces:**
- Produces: `run(conn, now) -> dict` → `{"evidence": n, "photos": n, "challenges": n}`; chạy bằng `python -m app.jobs.cleanup` (cron hằng ngày trên VPS, Task 20).

- [ ] **Step 1: Viết test thất bại**:

```python
def test_deletes_expired_evidence(...):     # quá 30 ngày → file mất, evidence_path NULL; chưa quá → giữ
def test_deletes_photos_of_reviewed(...):   # approved/rejected còn photos_path (do lỗi giữa chừng) → xóa
def test_deletes_old_challenges_without_attempt(...):  # challenge > 1 ngày, không có attempt trỏ tới → xóa
def test_missing_file_is_not_error(...): ...
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS.
- [ ] **Step 5: Commit** `feat(jobs): dọn ảnh bằng chứng, ảnh đăng ký, thử thách cũ`

### Task 18: Luồng điểm danh và lịch sử của sinh viên (Flutter)

**Files:**
- Create: `mobile/lib/core/gps_sampler.dart`, `mobile/lib/features/student/checkin/{checkin_controller,checkin_page}.dart`, `mobile/lib/features/student/history_page.dart`, `mobile/test/core/gps_sampler_test.dart`, `mobile/test/features/checkin_controller_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `captureJpeg`, `deviceId`, `PermissionsPage`.
- Produces:
  - `class GpsSample { double lat, lng, acc; int ts; bool mock; Map<String, dynamic> toJson(); }`
  - `class GpsSampler { GpsSampler(Stream<GpsSample> source, {required double maxAcc, required int minGood, required Duration minDuration, required Duration timeout}); Future<List<GpsSample>> collect(); Stream<double?> get currentAccuracy; }`: trả **mọi** mẫu đã thu (mẫu thô) khi đã qua `minDuration` và có ≥ `minGood` mẫu đạt; quá `timeout` thì ném `GpsTimeout`. Sinh viên: `maxAcc 30, minGood 3, minDuration 5 s, timeout 10 s`. Giảng viên (Task 19): `maxAcc 20, minGood 5, minDuration 3 s, timeout 20 s`.
  - `enum CheckinStep { challenge, roomCode, gps, camera, submitting, result }`; `class CheckinController extends ChangeNotifier { Future<void> start(int sessionId); ... CheckinStep step; String? reasonMessage; int? attemptsLeft; }`.

- [ ] **Step 1: Viết test thất bại**:

```dart
test('sampler returns all raw samples once minGood reached after minDuration', ...);
test('sampler throws GpsTimeout when not enough good samples', ...);
test('controller skips roomCode step when room_check is false', ...);
test('controller shows server reason and attemptsLeft on fail', ...);
test('CHALLENGE_INVALID → controller requests a new challenge automatically once', ...);
test('ATTEMPTS_EXHAUSTED / ALREADY_PRESENT / SESSION_CLOSED map to final messages', ...);
test('challenge countdown expiring before submit returns to challenge step', ...);
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS. Camera chụp chuỗi 6 khung trong khoảng 2 giây khi sinh viên làm hành động; quét QR bằng `mobile_scanner`, đọc `qr_payload` dạng `dd:{session_id}:{code}`, sai `session_id` thì báo quét lại. Thử tay trên một máy Android và một máy iOS.
- [ ] **Step 5: Commit** `feat(mobile): luồng điểm danh và lịch sử chuyên cần`

### Task 19: Màn hình giảng viên và quản trị viên (Flutter, app + web)

**Files:**
- Create: `mobile/lib/features/lecturer/{classes_page,open_session_page,live_session_page,student_detail_page,session_history_page,room_code_page,report_page}.dart`, `mobile/lib/features/admin/{users_page,classes_page,import_page,audit_page}.dart`, `mobile/test/features/lecturer_test.dart`, `mobile/test/features/admin_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `GpsSampler` (cấu hình giảng viên), các endpoint Task 3, 14, 16.
- Produces: các màn hình đúng bảng mục 4.7 (chưa làm màn ESP32).

- [ ] **Step 1: Viết widget test thất bại**:

```dart
testWidgets('open session button disabled until sampler has 5 good samples', ...);
testWidgets('live session polls every 4 s and stops when page disposed', ...);
testWidgets('recenter banner shown when recenter_suggested', ...);
testWidgets('student detail PATCH with note updates list', ...);
testWidgets('room code page refreshes at window_ends_at', ...);
testWidgets('import shows per-line errors from dry run before confirm', ...);
testWidgets('admin deactivate asks confirmation', ...);
```

- [ ] **Step 2–4:** FAIL → cài đặt → PASS; `flutter build web` thành công.
- [ ] **Step 5: Commit** `feat(mobile): màn hình giảng viên và quản trị viên`

---

## Giai đoạn 4 — Triển khai và thử nghiệm

### Task 20: Triển khai lên VPS, đo GPS, kiểm thử tải, chạy thử thật

**Files:**
- Create: `deploy/docker-compose.yml`, `deploy/Caddyfile`, `deploy/backend.Dockerfile`, `deploy/README.md`, `experiments/gps_analysis.py`, `experiments/locustfile.py`

**Interfaces:**
- Consumes: toàn bộ backend; bảng `attendance_sessions`, `checkin_attempts` (cột `gps_samples`).
- Produces: hệ thống chạy trên VPS qua HTTPS; `results/gps_*.csv` và biểu đồ; `results/load_*.csv`.

- [ ] **Step 1: Docker Compose** gồm `postgres:16`, `backend` (uvicorn **1 worker**, theo giới hạn khóa đăng nhập ở Task 2), `caddy` (HTTPS tự động cho tên miền), volume cho Postgres, `storage/`, `models/`. Bí mật (`JWT_SECRET`, `DATA_KEY`, mật khẩu DB) để trong file `.env` không commit. Cron trên host: `0 3 * * * docker compose exec -T backend python -m app.jobs.cleanup`. Sao lưu Postgres hằng ngày bằng `pg_dump`.
- [ ] **Step 2: Kiểm tra triển khai**: `curl https://<tên miền>/docs` → 200; app Android bản release đăng nhập được qua HTTPS.
- [ ] **Step 3: Đo GPS** trong ít nhất 3 phòng học thật (mục 10.2), sau đó chạy `python experiments/gps_analysis.py --dsn ...` → phân bố d (trung vị, phân vị 90), tỉ lệ chấp nhận đúng / sai theo r0 ∈ {10, 15, 20, 30, 40, 50}, và so sánh offline một lần đo / trung vị / trung bình có trọng số / Kalman trên cùng `gps_samples`. Chốt `default_r0_m`, `max_acc_student_m` vào `config.yaml`.
- [ ] **Step 4: Kiểm thử tải**: `locust -f experiments/locustfile.py --users 60 --spawn-rate 1 --run-time 3m` (mỗi user: login → challenge → checkin với ảnh mẫu thật). Đạt khi p95 < 3 s và tỉ lệ lỗi 0 %; không đạt thì xem lại `runtime.infer` hoặc thu nhỏ ảnh.
- [ ] **Step 5: Chạy thử một lớp thật** (sau khi nhà trường cho phép và sinh viên đã đồng ý): ghi tỉ lệ thành công lần đầu, số lần thử trung bình, tỉ lệ đáng ngờ, phản hồi của giảng viên và sinh viên.
- [ ] **Step 6: Commit** `chore(deploy): triển khai VPS, đo GPS, kiểm thử tải`

### Tùy chọn (sau khi giai đoạn 3 ổn định)

- **ESP32 phát BLE** (mục 7.2 giai đoạn 2): firmware ESP32, màn "Gửi mã ESP32" trên Flutter Web (Web Serial qua JS interop), quét BLE trong app sinh viên. Lập plan riêng khi đến lúc làm.

---

## Thứ tự và phụ thuộc

```text
T0 → T1 → T2 → T3, T4 (song song) → T5
T1 → T6 → T7 → T8 → T9 → T10 ; T8 → T11 (cổng: chốt mô hình)
T1 → T12, T13 (thuần, làm bất cứ lúc nào sau T1)
T9 + T12 + T13 → T14 → T15 → T16 → T17
T5 + T15 → T18 ; T5 + T16 → T19
T16 + T18 + T19 → T20
```

Lịch theo tuần chưa có vì chưa biết hạn nộp; khi có ngày nộp thì gán tuần cho từng task theo đồ thị trên.
