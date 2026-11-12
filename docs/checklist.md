# Checklist Tiến Độ - Ứng Dụng Điểm Danh Khuôn Mặt + GPS

Tham chiếu: [`dac-ta-thiet-ke.md`](./dac-ta-thiet-ke.md) (đặc tả bản 2), [`plan.md`](./plan.md) (task T0 → T20), [`huong-dan-cai-dat.md`](./huong-dan-cai-dat.md) (lệnh cài đặt, Docker, triển khai).

Quy ước:

- `[ ]` = chưa làm
- `[~]` = đang làm
- `[x]` = đã xong
- `[!]` = bị block / chờ quyết định

Mỗi tính năng thường cần làm cả **Backend** (API + SQL + kiểm tra đầu vào + test) và **App Flutter** (màn hình + state + test). Cùng một tính năng có thể xuất hiện ở cả hai phần, tick độc lập theo công việc thực tế. Ký hiệu `§4.4` là mục của đặc tả, `T15` là task trong plan.

---

## 0. Hạ tầng & Setup

### 0.1. Công cụ trên máy phát triển

- [x] Python 3.12 (3.12.10)
- [x] Docker Desktop 29.8.1 + WSL 2 (Ubuntu), `docker run hello-world` chạy được
- [x] Git 2.55 + cấu hình `user.name` / `user.email`
- [x] VS Code + extension Python, Pylance, Flutter, Dart, Containers
- [x] Android Studio + Android SDK 36 + máy ảo `Pixel_4_API_37`, `Medium_Phone_API_37.0`
- [x] Flutter 3.47.5 stable tại `C:\flutter`, `flutter doctor` sạch (chỉ thiếu Visual Studio, không cần vì không build app Windows)
- [ ] Máy test thật: 1 Android, 1 iOS

### 0.2. Backend skeleton (T1)

- [x] `git init` + `.gitignore` (loại `.env`, `storage/`, `*.onnx`, `*.jks`)
- [x] Khởi tạo FastAPI project (`backend/`) + venv + `pyproject.toml`
- [x] `config.yaml` theo §9.4 + `campus.geojson` (đa giác tạm, chờ tọa độ thật ở mục 6)
- [x] Đọc bí mật từ biến môi trường: `DATABASE_URL`, `JWT_SECRET`, `DATA_KEY`, `STORAGE_DIR`, `CORS_ORIGIN_REGEX`
- [x] PostgreSQL 16 chạy bằng Docker Compose cho dev (`deploy/docker-compose.dev.yml`)
- [x] Alembic + migration `0001_init` chép nguyên DDL §9.2
- [x] Connection pool psycopg 3 + dependency `get_conn` (commit / rollback theo request)
- [x] `ApiError` + handler trả envelope `{"error": {code, message, details}}` (§9.5)
- [x] `RequestValidationError` → 422 `VALIDATION_ERROR`
- [x] Giới hạn body 3 MB → 413 `PAYLOAD_TOO_LARGE` (theo Content-Length; Caddy chặn thêm ở production)
- [x] CORS cho Flutter Web
- [x] Swagger / OpenAPI tại `/docs`
- [x] Test fixture: Postgres nhúng (`pgserver`) hoặc `TEST_DATABASE_URL`, `TRUNCATE` giữa các test, `make_user`, `make_class`, `enroll` (`auth` thêm ở T2)

### 0.3. App skeleton (T5)

- [x] `flutter create --platforms=android,ios,web mobile`
- [x] Thêm package: dio, go_router, flutter_secure_storage, uuid (camera, geolocator, mobile_scanner thêm ở T10/T18 khi dùng)
- [x] Quyền Android (`INTERNET`, `CAMERA`, `ACCESS_FINE_LOCATION`), `minSdk 24` (mặc định Flutter, ≥ 23), cleartext chỉ ở bản debug
- [x] Quyền iOS (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`)
- [x] `API_URL` truyền qua `--dart-define`
- [x] `ApiClient` + interceptor: tự refresh khi `AUTH_TOKEN_EXPIRED`, đăng xuất khi `AUTH_TOKEN_REVOKED`
- [x] `ApiError` đọc envelope lỗi
- [x] `TokenStore` (secure storage) + `deviceId()` (UUID lưu lần đầu)
- [x] Router theo vai trò `/student`, `/lecturer`, `/admin` + chặn khi `must_change_password`
- [x] Layout chung cho app điện thoại và layout rộng cho web (khung, màn thật làm ở T10/T18/T19)

### 0.4. Mô hình học máy (T0)

- [x] Tải YuNet, ArcFace `w600k_r50`, MobileFaceNet `w600k_mbf`, MiniFASNetV2 vào `backend/models/`
- [x] `models/README.md`: nguồn, giấy phép, sha256
- [x] `experiments/spike_face.py` chạy bằng webcam (+ engine ONNX dùng chung với backend)
- [ ] Đo `yaw_sign`, `yaw_threshold` trên ảnh chụp bằng camera trước của điện thoại thật
- [ ] Đo `min_brightness`, `min_sharpness`
- [x] Spoof score của mặt thật / ảnh in / màn hình điện thoại / video (thật ≥ 0,95; giả ≤ 0,68)
- [~] Ghi kết quả vào `experiments/spike.md` (còn góc quay ảnh điện thoại, cosine khác người)
- [~] 🚦 Cổng 0: anti-spoofing tách được thật / giả (ĐẠT); cosine cùng người > khác người rõ rệt (chưa đo)

### 0.5. DevOps (T20)

- [ ] `deploy/backend.Dockerfile` (python:3.12-slim, 1 worker)
- [ ] `backend/.dockerignore`
- [ ] `deploy/docker-compose.yml` (db + backend + caddy)
- [ ] `deploy/Caddyfile`: `api.<domain>` → backend, `app.<domain>` → Flutter Web, HTTPS tự động
- [ ] `deploy/.env.example`
- [x] Lệnh `python -m app.cli create-admin`
- [ ] Cron dọn dữ liệu hằng ngày
- [ ] Cron `pg_dump` hằng ngày + xóa bản sao lưu quá 14 ngày
- [ ] Thử khôi phục bản sao lưu thành công

### 0.6. Tài liệu

- [x] Đặc tả thiết kế bản 2 (`dac-ta-thiet-ke.md`): luồng, CSDL, API, màn hình
- [x] DDL + các câu SQL chính đã chạy thử trên PostgreSQL 16
- [x] Kế hoạch triển khai (`plan.md`), 21 task
- [x] Hướng dẫn cài đặt (`huong-dan-cai-dat.md`)
- [x] Sơ đồ kiến trúc, sơ đồ luồng điểm danh, ERD (Mermaid trong đặc tả)
- [ ] README root project
- [ ] `deploy/README.md`
- [ ] Văn bản đồng ý `v1` cho sinh viên
- [ ] Văn bản đồng ý riêng cho tình nguyện viên thí nghiệm

---

# 1. Backend (FastAPI)

## 1.1. Database & Migration (§9.2)

- [x] `users` (3 vai trò, `is_active`, `must_change_password`, `token_version`)
- [x] `classes` (mã, tên, học kỳ, giảng viên) + `UNIQUE(code, semester)`
- [x] `enrollments` + khóa chính `(class_id, student_id)`
- [x] `consents` (phiên bản văn bản, thời điểm đồng ý / rút lại)
- [x] `face_templates` (tên mô hình, embedding mã hóa, trạng thái, ảnh tạm)
- [x] Partial unique index: 1 mẫu `approved` + 1 mẫu `pending` mỗi sinh viên
- [x] `attendance_sessions` (tâm, tâm gốc, σ_gv, r0, `room_secret`, hạn đóng)
- [x] Partial unique index: 1 phiên chưa đóng mỗi lớp
- [x] `challenges` (nonce unique, hành động, hạn, `used_at`)
- [x] `checkin_attempts` (mẫu GPS thô, d, r, điểm số, kết quả, bước dừng, cờ, ảnh bằng chứng)
- [x] `attendance_records` + khóa chính `(session_id, student_id)` + index `student_id`
- [x] `audit_log` (before / after jsonb, ip) + index `target`, `created_at`
- [x] Test: migration tạo đủ 10 bảng

## 1.2. Auth & Account API (T2)

- [x] `POST /auth/login` (access 15 phút, refresh 7 ngày)
- [x] `POST /auth/refresh` (kiểm tra `token_version`, `is_active`)
- [x] `POST /auth/change-password` (tăng `token_version`, trả cặp token mới)
- [x] Băm mật khẩu argon2
- [x] Khóa tạm 15 phút sau 10 lần sai trong 15 phút → 429 `RATE_LIMITED`
- [x] Dependency `current_user` + `require_role(...)`
- [x] Chặn mọi route khi `must_change_password` (trừ đổi mật khẩu và `GET /me`) → 403 `PASSWORD_CHANGE_REQUIRED`
- [x] Tài khoản bị vô hiệu hóa không đăng nhập / refresh được

## 1.3. Quản trị (T3)

- [x] CRUD `/admin/users` + tìm kiếm, lọc theo vai trò, phân trang
- [x] `POST /admin/users/{id}/reset-password` (mật khẩu tạm, `must_change_password`)
- [x] `POST /admin/users/{id}/deactivate` (tăng `token_version`, xóa dữ liệu khuôn mặt)
- [x] Chặn xóa cứng người dùng đã có dữ liệu → 409
- [x] CRUD `/admin/classes` (theo học kỳ, giảng viên phụ trách)
- [x] CRUD `/admin/enrollments`
- [x] `POST /admin/import`: CSV `users` / `classes` / `enrollments`, có lỗi thì không nhập dòng nào, `dry_run`
- [x] Nhập `users` trả file mật khẩu tạm
- [x] Đọc CSV có BOM UTF-8
- [x] `audit.log(...)` dùng chung
- [x] `GET /admin/audit-log` (phân trang, lọc người thực hiện / hành động / thời gian)
- [x] `python -m app.cli create-admin`

## 1.4. Tài khoản của tôi (T4)

- [x] `GET /me` (đồng ý, trạng thái khuôn mặt, `model_ok`, `pending_update`)
- [x] `GET /me/classes` (sinh viên: `open_session`; giảng viên: `student_count`)
- [x] `POST /me/consent` (đúng phiên bản hiện hành)
- [x] `GET /me/attendance` (T16)

## 1.5. Khuôn mặt (T6 → T9, §4.2, §5)

### 1.5.1. Mã hóa & lưu trữ

- [x] `encrypt` / `decrypt` AES-GCM
- [x] `save_blob` / `load_blob` / `delete_blob` dưới `STORAGE_DIR`, chặn đường dẫn `../`
- [x] Chuyển đổi embedding float32 ↔ bytes

### 1.5.2. Pipeline nhận diện

- [x] Giao diện `FaceEngine` + `FrameAnalysis` + `FaceResult`
- [x] Kiểm tra chất lượng: số mặt, mặt ≥ 100 px, độ sáng, độ nét
- [x] Kiểm tra hành động `turn_left` / `turn_right` (nhìn thẳng trước rồi mới quay)
- [x] Anti-spoofing: 3 khung nét nhất, lấy điểm thấp nhất
- [x] So khớp 1-1 trên mọi khung đạt chất lượng (trung vị + nhỏ nhất)
- [x] Hai ngưỡng: chấp nhận / nghi ngờ
- [x] `verify_checkin` (cần ≥ 3 khung đạt)
- [x] `build_template` (mỗi ảnh phải nhất quán với các ảnh còn lại, trả vector chuẩn hóa)
- [x] `OnnxFaceEngine`: YuNet + căn chỉnh 112×112 + ArcFace + MiniFASNet
- [x] Ảnh hỏng / quá lớn không gây lỗi 500
- [x] Giới hạn số luồng suy luận bằng semaphore

### 1.5.3. API khuôn mặt

- [x] `POST /faces/enroll` (3–5 ảnh, cần đồng ý, chỉ 1 mẫu chờ duyệt)
- [x] `GET /faces/pending` (giảng viên chỉ thấy sinh viên lớp mình)
- [x] `GET /faces/{id}/photos` (ghi nhật ký)
- [x] `POST /faces/{id}/review` (từ chối bắt buộc có lý do)
- [x] Duyệt xong: xóa ảnh, mẫu cũ chuyển `revoked`
- [x] `DELETE /me/face`
- [x] `DELETE /admin/users/{id}/face`
- [x] `approved_template(...)` cho luồng điểm danh

## 1.6. Phiên điểm danh (T12 → T14, §4.3, §6)

### 1.6.1. Hàm vị trí

- [x] `haversine_m`
- [x] `aggregate`: lọc theo độ chính xác, đủ số mẫu, span ≤ 20 s, lấy trung vị
- [x] `adaptive_radius`, `classify` (ok / drift / far)
- [x] `has_jump`, `jump_from_previous` (> 30 m/s)
- [x] `load_campus`, `in_polygon`
- [x] `suggest_recenter`, `recenter`

### 1.6.2. Mã phòng (§7.2)

- [x] `room_code` (HMAC-SHA256, 8 ký tự base32)
- [x] `verify_room_code` (cửa sổ hiện tại + cửa sổ trước)

### 1.6.3. API phiên

- [x] `POST /sessions`: GPS ≥ 5 mẫu ≤ 20 m, tâm trong khuôn viên, r0 trong 10–50 m
- [x] Tạo sẵn dòng `absent` cho cả lớp khi mở phiên
- [x] Tự đóng phiên quá hạn còn treo khi mở phiên mới
- [x] `POST /sessions/{id}/close`
- [x] `GET /sessions/{id}/room-token` (+ `ROOM_CHECK_DISABLED`)
- [x] `GET /classes/{id}/sessions` (lịch sử + số có mặt / vắng)

## 1.7. Điểm danh (T15, §4.4)

- [x] `POST /sessions/{id}/challenge`: kiểm tra lớp, phiên mở, mẫu mặt hợp lệ, chưa có mặt, còn lượt
- [x] `POST /sessions/{id}/checkin`: multipart 5–8 khung + `meta` JSON
- [x] Kiểm tra `meta`: mẫu GPS 1–100, tọa độ hợp lệ, `acc > 0`, không NaN
- [x] Bước 1: phiên mở theo giờ server
- [x] Bước 2: đánh dấu nonce đã dùng bằng `UPDATE ... RETURNING` (chặn request song song)
- [x] Bước 3: mã phòng (khi bật)
- [x] Bước 4: GPS, dừng sớm khi `d > 2r` (không chạy mô hình)
- [x] Bước 5: liveness
- [x] Bước 6: so khớp khuôn mặt
- [x] Ghi `checkin_attempts` từ bước 3 trở đi (kèm `fail_step`, `radius_m`, mẫu thô)
- [x] Cờ: `LOCATION_DRIFT`, `FACE_BORDERLINE`, `MOCK_LOCATION`, `LOCATION_JUMP`, `SHARED_DEVICE`, `ROOM_TOKEN_BURST`
- [x] Cập nhật kết quả bằng `INSERT ... ON CONFLICT` (chỉ nâng hạng, tôn trọng quyết định tay)
- [x] Lưu ảnh bằng chứng (mã hóa, 30 ngày) chỉ cho lượt đáng ngờ
- [x] Response cho sinh viên không có điểm số và cờ

## 1.8. Theo dõi, duyệt & báo cáo (T16, §4.5)

- [x] `GET /sessions/{id}/records` (bộ đếm, lượt cuối, `recenter_suggested`)
- [x] `PATCH /sessions/{id}/records/{student_id}` (chỉ trạng thái tay, ghi nhật ký trước / sau)
- [x] `POST /sessions/{id}/recenter` (giữ tâm gốc, chấm lại lượt drift, không hạ ai)
- [x] `GET /attempts/{id}/evidence` (ghi nhật ký)
- [x] `GET /reports/classes/{id}` (JSON + `?format=csv` có BOM)

## 1.9. Tác vụ nền (T17)

- [x] Xóa ảnh bằng chứng quá 30 ngày
- [x] Xóa ảnh đăng ký còn sót của mẫu đã duyệt / từ chối
- [x] Xóa thử thách cũ không có lượt thử
- [x] File đã mất không gây lỗi

## 1.10. Quy tắc nghiệp vụ

- [x] QT-01 · Tối đa 5 lượt (thử thách) mỗi sinh viên mỗi phiên (§4.4)
- [x] QT-02 · Nonce dùng một lần, hết hạn sau 60 s, gắn với sinh viên và phiên
- [x] QT-03 · Kiểm tra theo thứ tự 6 bước, dừng ở bước đầu tiên không đạt
- [x] QT-04 · Bảng quyết định: có mặt khi và chỉ khi không có cờ nào
- [x] QT-05 · Kết quả chỉ nâng hạng: vắng < đáng ngờ < có mặt
- [x] QT-06 · Quyết định tay của giảng viên khóa kết quả
- [x] QT-07 · `r = r0 + σ_gv + σ_sv`, trần `σ_sv ≤ 30 m` (§6.3)
- [x] QT-08 · Mở phiên cần ≥ 5 mẫu GPS có độ chính xác ≤ 20 m
- [x] QT-09 · Tâm phiên phải nằm trong đa giác khuôn viên
- [x] QT-10 · Mỗi lớp tối đa một phiên đang mở
- [x] QT-11 · Mở phiên thì tạo dòng "vắng" cho cả lớp
- [x] QT-12 · Mỗi sinh viên tối đa 1 mẫu đã duyệt + 1 mẫu chờ duyệt
- [x] QT-13 · Mẫu thuộc mô hình khác cấu hình hiện tại thì không hợp lệ, phải đăng ký lại
- [x] QT-14 · Ảnh đăng ký bị xóa ngay khi duyệt hoặc từ chối
- [x] QT-15 · Ảnh bằng chứng chỉ lưu cho lượt đáng ngờ, giữ 30 ngày
- [x] QT-16 · Mã phòng đổi mỗi 30 s, chấp nhận cửa sổ trước
- [x] QT-17 · So khớp trên mọi khung hình, không chỉ khung đẹp nhất
- [x] QT-18 · Sinh viên không bao giờ thấy điểm số hay cờ
- [x] QT-19 · Đối tượng ngoài phạm vi trả 404, sai vai trò trả 403
- [x] QT-20 · Vô hiệu hóa tài khoản thì xóa dữ liệu khuôn mặt (§4.6)

## 1.11. Backend testing

- [x] `test_foundation.py` (migration, envelope lỗi, 404, 413, CORS, cấu hình): 8/8 xanh
- [x] `test_auth.py` (khóa tạm, token hết hạn, refresh bị thu hồi, đổi mật khẩu)
- [x] `test_admin.py`, `test_importer.py`
- [x] `test_me.py`
- [x] `test_crypto.py`
- [x] `test_face_checks.py`, `test_face_verify.py`
- [x] `test_onnx_engine.py` (`-m models`)
- [x] `test_faces_api.py`
- [x] `test_geo.py`, `test_room_token.py`
- [x] `test_sessions_api.py`
- [x] `test_checkin.py` (gồm 5 tình huống Review Focus)
- [x] `test_records_api.py` (15 test, gồm cả báo cáo và `/me/attendance`)
- [x] `test_cleanup.py` (4 test; chạy `python -m app.jobs.cleanup`)

### 1.11.1. Review Focus (plan.md)

- [x] RF-1 · Hai request cùng nonce chạy song song → chỉ 1 thành công
- [x] RF-2 · Phiên hết hạn giữa lúc xin thử thách và lúc gửi → `SESSION_CLOSED`, không ghi lượt
- [x] RF-3 · Mẫu GPS rác → 422 hoặc `GPS_ACCURACY_LOW`, không 500
- [x] RF-4 · Khung hình hỏng → `FACE_NOT_FOUND`; > 3 MB → 413
- [x] RF-5 · Giảng viên đụng lớp không dạy → 404

---

## 1.9. Chức năng mở rộng (ngoài đặc tả)

- [x] Bảng `requests` (migration 0003): đơn xin nghỉ (`leave`) và khiếu nại (`appeal`) cho buổi đã đóng, trong 14 ngày
- [x] `POST /me/requests` (lý do + ảnh giấy tờ JPEG/PNG ≤ 5 MB, mã hóa), `GET /me/requests`
- [x] `GET /requests`, `GET /requests/{id}/attachment` (ghi nhật ký), `POST /requests/{id}/decide` (xin nghỉ → vắng có phép, khiếu nại → có mặt; từ chối bắt buộc lý do)
- [x] Cảnh báo chuyên cần: `attendance.warn_absent` (mặc định 3 buổi, chỉ tính buổi đã đóng); `absences`/`warn` trong `/me/classes`, `/sessions/{id}/records`, báo cáo
- [x] `GET /admin/overview`: tỉ lệ có mặt theo lớp và học kỳ, sinh viên vắng nhiều, cờ đáng ngờ, lý do lượt không đạt
- [x] `POST /faces/precheck`: kiểm tra nhanh một khung (chất lượng + hướng mặt) để app tự chụp
- [x] `test_requests.py` (8 test)
- [x] Báo cáo nộp khoa: `GET /reports/classes/{id}?format=xlsx` (sheet Tổng hợp + Chi tiết buổi, tô đỏ SV vắng nhiều, chỗ ký) và `?format=pdf` (A4, font Inter tiếng Việt); tên trường/khoa trong `report:` của `config.yaml`

# 2. App Flutter (Android / iOS / Web)

## 2.1. Chung

- [x] Màn **Đăng nhập** (hiện thông điệp lỗi từ server)
- [x] Màn **Đổi mật khẩu bắt buộc**
- [x] Nút đăng xuất
- [x] Tự đổi mật khẩu (Tài khoản / thanh bên web); quản trị viên không tự đặt lại mật khẩu của mình; lệnh `python -m app.cli reset-password`
- [x] **Thông báo** của sinh viên (phiên đang mở, kết quả duyệt mặt, quyết định của giảng viên trong 7 ngày)
- [x] Sinh viên gửi **đơn xin nghỉ / khiếu nại** từ Lịch sử chuyên cần; thẻ cảnh báo vắng nhiều; kết quả đơn trong Thông báo
- [x] Giảng viên duyệt đơn (tab **Đơn** trên dock, mục trên thanh bên web); nhãn đỏ "Vắng N buổi" ở Phiên đang chạy
- [x] **Tự chụp** khi đăng ký khuôn mặt (2 khung đạt liên tiếp đúng hướng), vẫn có nút chụp tay
- [x] Trang **Tổng quan** cho quản trị (mặc định khi đăng nhập)
- [x] Màn **Quyền truy cập** (camera / vị trí / Bluetooth bị từ chối → giải thích + mở cài đặt; web: hướng dẫn biểu tượng ổ khóa)
- [ ] `captureJpeg` (cạnh dài ≤ 1280 px, chất lượng 80)
- [x] `GpsSampler` (thu mẫu thô, `minGood`, `minDuration`, `timeout`)
- [ ] Component dùng chung: loading, empty state, banner lỗi, hộp xác nhận

## 2.2. Sinh viên (app điện thoại)

- [x] **Trang chủ**: thẻ trạng thái khuôn mặt + danh sách lớp + nút "Điểm danh" khi có phiên mở + đồng hồ đếm ngược
- [x] **Đồng ý dữ liệu** (hiện lại khi có phiên bản mới)
- [x] **Đăng ký khuôn mặt**: hướng dẫn, khung oval, chụp thẳng / trái / phải, lý do từng ảnh không đạt (tự chụp qua `/faces/precheck`, vẫn có nút chụp tay)
- [x] **Khuôn mặt của tôi**: trạng thái, lý do từ chối, đăng ký lại, xóa dữ liệu (có xác nhận)
- [x] **Điểm danh** bước 1: xin thử thách (`/student/checkin/:sid`)
- [x] **Điểm danh** bước 2: quét QR (khi phiên bật mã phòng), kiểm tra đúng `session_id`, có ô nhập mã tay
- [x] **Điểm danh** bước 3: lấy GPS (30 m, 3 mẫu, 5 s, hết 15 s báo lỗi), hiện độ chính xác và gợi ý; từ chối quyền → màn cấp quyền
- [x] **Điểm danh** bước 4: camera với chỉ dẫn hành động + đếm ngược 60 s (6 khung cách ~350 ms)
- [x] **Điểm danh** bước 5: gửi, hiện kết quả, lý do, số lượt còn lại, nút thử lại
- [x] Tự xin thử thách mới khi gặp `CHALLENGE_INVALID` (một lần, giữ mẫu GPS)
- [x] **Lịch sử chuyên cần** theo lớp

## 2.3. Giảng viên (app điện thoại)

- [x] **Lớp của tôi** (vào thẳng phiên đang chạy nếu có)
- [x] **Mở phiên**: thời hạn, r0, bật mã phòng, thanh trạng thái GPS, nút mở chỉ bật khi đủ mẫu
- [x] **Phiên đang chạy**: bộ đếm, danh sách lọc theo trạng thái, tự làm mới 3–5 s
- [x] Dải cảnh báo "tâm có thể lệch" + nút tính lại tâm
- [x] Nút đóng phiên
- [x] **Chi tiết sinh viên**: ảnh bằng chứng, điểm, d, r, cờ, các lượt; đặt trạng thái tay kèm ghi chú
- [x] **Lịch sử phiên** + chỉnh kết quả sau khi đóng
- [x] **Duyệt khuôn mặt** (sinh viên lớp mình; từ chối bắt buộc có lý do)

## 2.4. Giảng viên (Flutter Web trên laptop)

- [x] **Chiếu mã phòng**: QR toàn màn hình, đổi mỗi 30 s, tên lớp + đồng hồ phiên
- [x] Khung web giảng viên có thanh bên (Phiên điểm danh, Chiếu mã phòng, Duyệt khuôn mặt, Báo cáo); trang con giữ bố cục cột
- [x] **Báo cáo lớp** + nút xuất CSV

## 2.5. Quản trị viên (Flutter Web)

- [x] **Người dùng**: tìm kiếm, lọc, tạo, sửa, đặt lại mật khẩu, vô hiệu hóa, xóa dữ liệu khuôn mặt
- [x] **Lớp**: theo học kỳ, đổi giảng viên, thêm / bớt sinh viên
- [x] **Nhập CSV**: tải file, xem trước lỗi từng dòng (`dry_run`), xác nhận
- [x] **Duyệt khuôn mặt** (mọi sinh viên)
- [x] **Báo cáo** + xuất CSV
- [x] **Nhật ký** (lọc người thực hiện, hành động, thời gian)

## 2.6. Flutter testing

- [x] `api_client_test.dart` (refresh 1 lần, thu hồi token, đọc envelope lỗi): 4/4 xanh
- [x] `auth_flow_test.dart` (sai mật khẩu, bắt đổi mật khẩu, vào trang theo vai trò, đăng xuất): 3/3 xanh
- [x] `gps_sampler_test.dart`: 4/4 xanh
- [x] `checkin_controller_test.dart` (10/10) và `checkin_page_test.dart` (6/6)
- [x] `lecturer_test.dart` (9/9): mở phiên, phiên đang chạy, tâm lệch, đóng phiên, chi tiết SV, chiếu mã, lịch sử phiên, báo cáo, lịch sử chuyên cần
- [x] `shell_test.dart` (khung web giảng viên, chọn phiên chiếu, tự đổi mật khẩu), `notices_test.dart`
- [x] `requests_test.dart` (đơn, cảnh báo, tổng quan); test tự chụp trong `enroll_test.dart`
- [x] `enroll_test.dart` (đồng ý, đăng ký, quyền camera, xóa, duyệt)
- [x] `home_pages_test.dart`, `admin_pages_test.dart` (trang chủ, quản trị)
- [x] `flutter build web` thành công (và `flutter build apk --debug`)
- [ ] Thử tay trọn luồng trên Android thật
- [ ] Thử tay trọn luồng trên iOS thật

---

# 3. Học máy & Thí nghiệm (§10)

- [ ] `experiments/metrics.py`: `far_frr`, `eer`, `threshold_at_far`, `apcer_bpcer` + test
- [ ] Thu tập tự thu 30–50 tình nguyện viên (sau khi có đồng ý bằng văn bản)
- [ ] Thu tập tấn công giả: ảnh in, màn hình, video phát lại
- [ ] So sánh mô hình (ArcFace r50 vs MobileFaceNet): FAR, FRR, EER, ROC, thời gian / ảnh trên CPU
- [ ] Ảnh hưởng điều kiện chụp: ánh sáng, góc, kính, khẩu trang
- [ ] Anti-spoofing: APCER, BPCER
- [ ] Chọn ngưỡng trên 70 % dữ liệu, kiểm chứng trên 30 % còn lại
- [ ] 🚦 Cổng 2: chốt `model_name` + ngưỡng trong `config.yaml` (FAR ≤ 0,1 %). **Chưa qua thì chưa cho sinh viên đăng ký thật**
- [ ] Đo GPS ở ≥ 3 phòng học: phân bố d (trung vị, phân vị 90)
- [ ] Tỉ lệ chấp nhận đúng / sai theo r0 ∈ {10, 15, 20, 30, 40, 50}
- [ ] So sánh offline: một lần đo / trung vị / trung bình có trọng số / Kalman
- [ ] Chốt `default_r0_m`, `max_acc_student_m`
- [ ] Kiểm thử tải 60 người / 3 phút: p95 < 3 s, lỗi 0 %

---

## 4. Phi chức năng (§8)

- [ ] NFR-SEC-01 · HTTPS toàn bộ; app bản release không gọi HTTP
- [ ] NFR-SEC-02 · Phân quyền theo vai trò và phạm vi lớp
- [ ] NFR-SEC-03 · Embedding và ảnh mã hóa AES-GCM, khóa nằm ngoài CSDL
- [ ] NFR-SEC-04 · Bí mật production là giá trị mới, không nằm trong git
- [ ] NFR-SEC-05 · Log server không in token, mật khẩu, embedding, ảnh
- [x] NFR-PRV-01 · Đồng ý có phiên bản trước khi đăng ký khuôn mặt
- [ ] NFR-PRV-02 · Khung hình điểm danh không ghi ra đĩa (trừ ảnh bằng chứng)
- [ ] NFR-PRV-03 · Nhật ký đủ các thao tác nhạy cảm (§8)
- [ ] NFR-PRV-04 · Sinh viên tự xóa được dữ liệu khuôn mặt
- [ ] NFR-AVL-01 · Sao lưu hằng ngày + đã thử khôi phục
- [ ] NFR-AVL-02 · `DATA_KEY` lưu ở nơi an toàn riêng (mất khóa = mất toàn bộ embedding)
- [ ] NFR-PER-01 · p95 điểm danh < 3 s với 60 người trong 3 phút
- [ ] NFR-CMP-01 · Android (minSdk 23), iOS, Chrome / Edge cho bản web

---

## 5. Triển khai & Chạy thử

- [ ] Thuê VPS (4 vCPU, 8 GB RAM) + tên miền + DNS `api.` / `app.`
- [ ] Tường lửa (22, 80, 443) + cài Docker trên VPS
- [ ] `docker compose up -d --build` + migration + tạo quản trị viên đầu tiên
- [ ] `https://api.<domain>/docs` trả 200; `https://app.<domain>` hiện màn đăng nhập
- [ ] Khóa ký Android + build APK release
- [ ] Build iOS (cần Mac + Apple Developer) hoặc ghi rõ chỉ chạy thử trên Android
- [ ] Nhập danh sách lớp chạy thử bằng CSV
- [ ] Sinh viên lớp chạy thử đồng ý + đăng ký + được duyệt
- [ ] Hướng dẫn giảng viên: mở phiên, duyệt, tính lại tâm, đặt tay khi mất mạng
- [ ] 🚦 Cổng 3: chạy trọn một vòng thật (nhập CSV → đăng ký → duyệt → mở phiên → điểm danh → duyệt → đóng → xuất CSV)
- [ ] Chạy thử một buổi: tỉ lệ thành công lần đầu, số lần thử trung bình, tỉ lệ đáng ngờ, phản hồi

---

## 6. Câu hỏi mở / Rủi ro

- [!] Hạn nộp chưa có → chưa chia được lịch theo tuần
- [!] Chờ nhà trường cho phép thu dữ liệu sinh trắc học và chạy thử
- [!] Văn bản đồng ý `v1` chờ nhà trường duyệt
- [ ] Tọa độ đa giác khuôn viên
- [ ] Chọn phòng đo GPS và lớp chạy thử; xác nhận phòng có sóng mạng
- [ ] RISK · Anti-spoofing không tách được ảnh giả trên ảnh điện thoại thật (kiểm tra ở Cổng 0)
- [ ] RISK · GPS trong nhà lệch quá nhiều (đo ở §3, chọn r0 theo số liệu)
- [ ] RISK · Giấy phép mô hình InsightFace chỉ cho nghiên cứu (ghi trong báo cáo)
- [ ] RISK · Không có máy Mac để build iOS
- [ ] RISK · iOS không phát hiện được mock location (ghi trong phần giới hạn)

---

## 7. Tổng quan tiến độ

| Layer | Hoàn thành | Ghi chú |
|---|---|---|
| Công cụ (0.1) | 6/7 | Đủ công cụ; còn chuẩn bị máy test thật |
| Backend skeleton (0.2) | 13/13 | FastAPI + Alembic + Postgres Docker chạy được, 8 test xanh |
| App skeleton (0.3) | 10/10 | Đăng nhập, đổi mật khẩu, router theo vai trò; 7 test xanh; build web + APK OK |
| Mô hình (0.4) | 4/8 | Anti-spoofing đạt Cổng 0 trên webcam (ngưỡng tạm 0,8); còn ảnh điện thoại (yaw) và cosine khác người |
| DevOps (0.5) | 1/9 | Lệnh create-admin |
| Tài liệu (0.6) | 5/9 | Đặc tả, plan, hướng dẫn cài đặt xong; còn README, văn bản đồng ý |
| Database (1.1) | 13/13 | Migration 0001 tạo đủ 10 bảng |
| Backend API (1.2 – 1.9) | 73/83 | Auth, Quản trị, /me, khuôn mặt, phiên, điểm danh 6 bước; còn theo dõi/duyệt tay/báo cáo (T16), tác vụ nền (T17) |
| Quy tắc nghiệp vụ (1.10) | 20/20 | Mọi quy tắc đều có test |
| Backend testing (1.11) | 16/18 | 201 test xanh, gồm 5 tình huống Review Focus |
| App Flutter (2.1 – 2.5) | 8/35 | Đăng nhập, trang chủ SV/GV, đồng ý, đăng ký và xóa khuôn mặt, duyệt khuôn mặt; web quản trị: người dùng, lớp, CSV, nhật ký |
| Flutter testing (2.6) | 5/9 | 24 test xanh; còn GPS, điểm danh, thử tay trên máy thật |
| Học máy & thí nghiệm (3) | 0% | |
| Phi chức năng (4) | 0/13 | |
| Triển khai & chạy thử (5) | 0% | |

**Tổng cộng**: 231 mục `[x]` / 2 mục `[~]` / 3 mục `[!]` / 62 mục `[ ]` (298 items)

### Bước tiếp theo khuyến nghị

1. **Bật Docker, chạy thử trọn luồng trên máy thật**: giảng viên mở phiên → chiếu mã → sinh viên điểm danh → duyệt → đóng → xuất CSV
2. **T20 · Triển khai** lên VPS (Dockerfile, compose có Caddy, cron dọn dữ liệu + sao lưu); thử trên Android thật, chốt ngưỡng (T11)
3. **Bật Docker**: chạy `alembic upgrade head` và `create-admin --username admin` để thử app thật
4. **Gửi nhà trường xin phép** (mục 6) và lấy tọa độ đa giác khuôn viên thật cho `campus.geojson`

---

## Lịch sử các thay đổi lớn

### Phase 0 — Tài liệu (2026-11-10)

- Rà đặc tả bản 1: phát hiện ràng buộc `UNIQUE(phiên, sinh viên)` chặn việc thử lại, thiếu quy tắc ghép kết quả khuôn mặt với GPS, thiếu trần sai số GPS
- Viết lại đặc tả bản 2: luồng 6 bước, bảng quyết định, CSDL 10 bảng, API, quy ước lỗi, danh sách màn hình
- Chạy thử DDL và các câu SQL chính trên PostgreSQL 16 (pgserver): mọi kiểm tra đạt
- Viết `plan.md` (21 task, TDD) và `huong-dan-cai-dat.md`
- Bổ sung vào plan: CORS cho Flutter Web, lệnh `create-admin`

### Phase 1 — Backend (2026-11-11)

- 1.2 Auth, 1.3 Quản trị, 1.4 /me, T6 mã hóa, T12 hàm vị trí, T13 mã phòng xong
- Đổi cách đăng nhập: thêm cột `username` cho mọi tài khoản (migration 0002), email thành tùy chọn; CSV `users` thêm cột `username`; `create-admin --username`
