# Hướng dẫn cài đặt và xây dựng: từng bước từ máy phát triển đến VPS

Làm theo thứ tự từ trên xuống. Mỗi bước có lệnh chạy và **kết quả mong đợi**; chỉ đánh dấu `[x]` khi thấy đúng kết quả đó. Lệnh viết cho **Windows PowerShell** (máy phát triển) và **bash** (VPS Ubuntu). Phần code của từng tính năng làm theo [plan.md](plan.md); yêu cầu nằm ở [dac-ta-thiet-ke.md](dac-ta-thiet-ke.md).

---

## Bước 1. Cài công cụ trên máy phát triển

- [ ] **Git**

  ```powershell
  winget install --id Git.Git -e
  git --version
  ```
  Mong đợi: `git version 2.x`. Sau đó cấu hình tên và email: `git config --global user.name "..."`, `git config --global user.email "..."`.

- [ ] **Python 3.12** (máy đã có 3.12.10)

  ```powershell
  python --version
  ```
  Mong đợi: `Python 3.12.x`. Nếu chưa có: `winget install --id Python.Python.3.12 -e`.

- [ ] **Docker Desktop** (đã cài; cần bật WSL 2)

  ```powershell
  wsl --install          # chỉ chạy nếu chưa có WSL, xong thì khởi động lại máy
  docker version
  docker run --rm hello-world
  ```
  Mong đợi: có cả mục `Client` lẫn `Server`, và dòng `Hello from Docker!`. Nếu báo không kết nối được: mở Docker Desktop, đợi biểu tượng chuyển xanh.

- [ ] **VS Code** và các extension: Python, Pylance, Flutter, Dart, Docker

  ```powershell
  winget install --id Microsoft.VisualStudioCode -e
  code --install-extension ms-python.python
  code --install-extension Dart-Code.flutter
  code --install-extension ms-azuretools.vscode-docker
  ```

- [ ] **Android Studio** (để có Android SDK và máy ảo)

  ```powershell
  winget install --id Google.AndroidStudio -e
  ```
  Mở Android Studio → More Actions → SDK Manager: cài **Android SDK Platform** mới nhất, **Android SDK Command-line Tools**, **Android SDK Build-Tools**. Vào Device Manager tạo một máy ảo Pixel có Google Play.

- [ ] **Flutter SDK** (kênh stable)
  1. Tải file zip Flutter stable cho Windows từ trang chính thức `docs.flutter.dev` và giải nén vào `C:\src\flutter` (không để trong `Program Files`).
  2. Thêm `C:\src\flutter\bin` vào biến môi trường `Path` của user, mở lại PowerShell.

  ```powershell
  flutter --version
  flutter doctor --android-licenses     # gõ y cho tất cả
  flutter doctor
  ```
  Mong đợi: dấu ✓ ở Flutter, Windows Version, Android toolchain, Chrome, Android Studio, VS Code. Mục Xcode không cần (iOS chỉ build được trên máy Mac, xem Bước 11).

- [ ] **Google Chrome** (để chạy bản Flutter Web): `winget install --id Google.Chrome -e`

---

## Bước 2. Tạo kho mã nguồn

- [ ] Khởi tạo git và cấu trúc thư mục

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS
  git init
  mkdir backend, mobile, experiments, deploy
  ```

- [ ] Tạo file `.gitignore` ở thư mục gốc:

  ```gitignore
  # Python
  .venv/
  __pycache__/
  *.pyc
  .pytest_cache/
  # Bí mật và dữ liệu
  .env
  backend/storage/
  backend/models/*.onnx
  experiments/data/
  # Flutter
  mobile/build/
  mobile/.dart_tool/
  mobile/android/key.properties
  *.jks
  ```

- [ ] Commit đầu tiên

  ```powershell
  git add .
  git commit -m "chore: khởi tạo dự án, đặc tả, plan, checklist"
  ```
  Mong đợi: `git log --oneline` hiện 1 commit.

---

## Bước 3. Dựng môi trường Python cho backend

- [ ] Tạo virtualenv

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS\backend
  python -m venv .venv
  .\.venv\Scripts\Activate.ps1
  python -m pip install --upgrade pip
  ```
  Nếu PowerShell chặn script: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. Mong đợi: dấu nhắc lệnh có tiền tố `(.venv)`.

- [ ] Tạo `backend/pyproject.toml`:

  ```toml
  [project]
  name = "diemdanh-backend"
  version = "0.1.0"
  requires-python = ">=3.12"
  dependencies = [
    "fastapi", "uvicorn[standard]", "python-multipart",
    "psycopg[binary,pool]", "alembic", "sqlalchemy",
    "pydantic", "pyyaml", "pyjwt", "argon2-cffi", "cryptography",
    "numpy", "opencv-python-headless", "onnxruntime",
  ]

  [project.optional-dependencies]
  dev = ["pytest", "httpx", "freezegun", "pgserver", "locust"]

  [tool.pytest.ini_options]
  testpaths = ["tests"]
  markers = ["models: cần file mô hình ONNX trong backend/models"]

  [tool.setuptools]
  packages = ["app"]
  ```

- [ ] Cài thư viện

  ```powershell
  pip install -e ".[dev]"
  python -c "import fastapi, psycopg, cv2, onnxruntime; print('ok')"
  ```
  Mong đợi: in ra `ok`.

- [ ] Tạo file `backend/.env` cho môi trường phát triển (đã có trong `.gitignore`):

  ```dotenv
  DATABASE_URL=postgresql://app:app@localhost:5432/diemdanh
  JWT_SECRET=dev-chi-dung-tren-may-minh
  DATA_KEY=<chuỗi base64 32 byte, sinh bằng lệnh bên dưới>
  STORAGE_DIR=./storage
  CORS_ORIGIN_REGEX=^http://(localhost|127\.0\.0\.1)(:\d+)?$
  ```

  ```powershell
  python -c "import os,base64; print(base64.b64encode(os.urandom(32)).decode())"
  ```

- [ ] Tạo `backend/config.yaml` (lấy theo mục 9.4 của đặc tả cộng phần Global Constraints trong plan) và `backend/campus.geojson` (vẽ trên geojson.io, lưu một Polygon).

---

## Bước 4. Dựng database PostgreSQL cho phát triển

- [ ] Tạo `deploy/docker-compose.dev.yml`:

  ```yaml
  services:
    db:
      image: postgres:16
      environment:
        POSTGRES_USER: app
        POSTGRES_PASSWORD: app
        POSTGRES_DB: diemdanh
      ports: ["5432:5432"]
      volumes: [pgdata:/var/lib/postgresql/data]
  volumes:
    pgdata:
  ```

- [ ] Chạy database

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS
  docker compose -f deploy/docker-compose.dev.yml up -d
  docker compose -f deploy/docker-compose.dev.yml ps
  ```
  Mong đợi: service `db` ở trạng thái `running`.

- [ ] Khởi tạo Alembic và migration đầu tiên

  ```powershell
  cd backend
  alembic init migrations
  alembic revision -m "init"
  ```
  - Sửa `migrations/env.py` để đọc `DATABASE_URL` từ môi trường (thay `postgresql://` bằng `postgresql+psycopg://` cho SQLAlchemy).
  - Mở file vừa sinh trong `migrations/versions/`, đổi tên thành `0001_init.py`; trong `upgrade()` gọi `op.execute("""<dán nguyên khối DDL đầu tiên của mục 9.2>""")`.

- [ ] Chạy migration và kiểm tra

  ```powershell
  alembic upgrade head
  docker compose -f ..\deploy\docker-compose.dev.yml exec db psql -U app -d diemdanh -c "\dt"
  ```
  Mong đợi: liệt kê 10 bảng (`users`, `classes`, `enrollments`, `consents`, `face_templates`, `attendance_sessions`, `challenges`, `checkin_attempts`, `attendance_records`, `audit_log`) và `alembic_version`.

- [ ] Commit: `git commit -am "feat(db): docker postgres dev và migration 0001"`

---

## Bước 5. Chạy backend lần đầu

- [ ] Làm **Task 1** trong plan.md: `app/main.py`, `config.py`, `db.py`, `errors.py`, `tests/conftest.py`. Trong `main.py` thêm `CORSMiddleware` với `allow_origin_regex` lấy từ biến `CORS_ORIGIN_REGEX`; nếu thiếu thì Flutter Web không gọi được API.
- [ ] Chạy server

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS\backend
  uvicorn app.main:app --reload --env-file .env
  ```
  Mong đợi: mở `http://localhost:8000/docs` thấy trang Swagger.

- [ ] Chạy test

  ```powershell
  pytest -v
  ```
  Mong đợi: tất cả xanh. Test dùng `pgserver` nên không cần Docker; đặt `DATABASE_URL` thì test sẽ dùng database đó.

---

## Bước 6. Tải mô hình nhận diện khuôn mặt

- [ ] Làm **Task 0** trong plan.md. Tải các file vào `backend/models/`:
  - `face_detection_yunet_2023mar.onnx` (OpenCV Zoo)
  - `w600k_r50.onnx`, `w600k_mbf.onnx` (InsightFace buffalo_l, buffalo_s; giấy phép chỉ cho nghiên cứu)
  - MiniFASNetV2 bản ONNX (Silent-Face-Anti-Spoofing)
- [ ] Ghi checksum vào `backend/models/README.md`

  ```powershell
  Get-FileHash backend\models\*.onnx -Algorithm SHA256 | Format-Table Hash, Path
  ```

- [ ] Chạy spike bằng webcam

  ```powershell
  python experiments/spike_face.py
  ```
  Mong đợi: thấy số mặt, `yaw_proxy`, spoof score, cosine thay đổi theo thời gian thực. Ghi kết quả vào `experiments/spike.md`.

---

## Bước 7. Tạo app Flutter

- [ ] Tạo dự án

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS
  flutter create --org vn.edu.truong --platforms=android,ios,web mobile
  cd mobile
  flutter pub add dio go_router flutter_secure_storage camera geolocator mobile_scanner uuid
  flutter pub add --dev mocktail
  ```

- [ ] **Quyền trên Android**: trong `android/app/src/main/AndroidManifest.xml`, ngay trong thẻ `<manifest>`:

  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  ```
  Trong `android/app/build.gradle(.kts)` đặt `minSdk = 23` (thấp hơn thì một số plugin không chạy).

- [ ] **Cho phép HTTP khi debug trên Android** (server dev không có HTTPS): trong `android/app/src/debug/AndroidManifest.xml`, thêm `android:usesCleartextTraffic="true"` vào thẻ `<application>`. Chỉ đặt ở bản debug; bản release chỉ dùng HTTPS.

- [ ] **Quyền trên iOS** (`ios/Runner/Info.plist`):

  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Dùng camera để chụp khuôn mặt khi đăng ký và điểm danh</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Dùng vị trí để xác nhận bạn đang ở lớp học khi điểm danh</string>
  ```

- [ ] **Địa chỉ backend** truyền lúc chạy, không ghi cứng trong code: `const apiUrl = String.fromEnvironment('API_URL');`

- [ ] Chạy thử

  ```powershell
  flutter run -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:8000   # máy ảo Android: 10.0.2.2 trỏ về máy tính
  flutter run -d chrome --dart-define=API_URL=http://localhost:8000          # bản web
  ```
  Mong đợi: app mở được và gọi được `/docs` hoặc `/auth/login`.

- [ ] **Chạy trên điện thoại thật cùng mạng Wi-Fi**: cho uvicorn nghe mọi địa chỉ (`uvicorn app.main:app --host 0.0.0.0 --reload --env-file .env`), mở cổng 8000 trên Windows Firewall, rồi dùng IP LAN của máy tính:

  ```powershell
  New-NetFirewallRule -DisplayName "FastAPI dev 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow -Profile Private
  ipconfig      # lấy IPv4 của card Wi-Fi, vd 192.168.1.20
  flutter run --dart-define=API_URL=http://192.168.1.20:8000
  ```
  Lưu ý: camera và GPS phải thử trên **máy thật**, máy ảo không đại diện được.

- [ ] Chạy test Flutter: `flutter test` → tất cả xanh.
- [ ] Commit: `git commit -am "feat(mobile): khởi tạo app Flutter, quyền camera và vị trí"`

---

## Bước 8. Xây tính năng theo plan

Mỗi task: viết test → thấy test đỏ → viết code → thấy test xanh → commit. Chi tiết ở [plan.md](plan.md).

- [ ] T0 Spike mô hình — 🚦 anti-spoofing tách được ảnh thật với ảnh giả
- [ ] T1 Khung backend · T2 Xác thực · T3 Quản trị, nhập CSV · T4 `/me` · T5 Khung app Flutter — 🚦 đăng nhập được trên app và web
- [ ] T6 Mã hoá · T7 Kiểm tra khuôn mặt · T8 Engine ONNX · T9 API khuôn mặt · T10 Màn hình đăng ký
- [ ] T11 Thí nghiệm chọn mô hình — 🚦 chốt `model_name` và ngưỡng trong `config.yaml`
- [ ] T12 Hàm vị trí · T13 Mã phòng · T14 Phiên · T15 Điểm danh 6 bước · T16 Duyệt, báo cáo · T17 Dọn dữ liệu
- [ ] T18 Điểm danh trên app · T19 Màn hình giảng viên, quản trị viên — 🚦 chạy trọn một vòng: nhập CSV → đăng ký → duyệt → mở phiên → điểm danh → duyệt → đóng → xuất CSV

Sau mỗi task chạy lại toàn bộ test: `pytest -v` (trong `backend`) và `flutter test` (trong `mobile`).

---

## Bước 9. Đóng gói bằng Docker

- [ ] Tạo `deploy/backend.Dockerfile`:

  ```dockerfile
  FROM python:3.12-slim
  RUN apt-get update && apt-get install -y --no-install-recommends libglib2.0-0 libgomp1 \
      && rm -rf /var/lib/apt/lists/*
  WORKDIR /srv
  COPY backend/ .
  RUN pip install --no-cache-dir .
  EXPOSE 8000
  # 1 worker: khóa đăng nhập giữ trong bộ nhớ (plan Task 2)
  CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
  ```
  Tạo thêm `backend/.dockerignore` gồm `.venv`, `storage`, `tests`, `.env`, `__pycache__` để không đưa rác và bí mật vào image.

- [ ] Tạo `deploy/Caddyfile` (API và web chạy ở hai tên miền con, Caddy tự lấy chứng chỉ HTTPS):

  ```caddyfile
  api.{$DOMAIN} {
      request_body {
          max_size 4MB
      }
      reverse_proxy backend:8000
  }

  app.{$DOMAIN} {
      root * /srv/web
      try_files {path} /index.html
      file_server
  }
  ```

- [ ] Tạo `deploy/docker-compose.yml`:

  ```yaml
  services:
    db:
      image: postgres:16
      restart: unless-stopped
      env_file: .env
      volumes: [pgdata:/var/lib/postgresql/data]
    backend:
      build: { context: .., dockerfile: deploy/backend.Dockerfile }
      restart: unless-stopped
      env_file: .env
      depends_on: [db]
      volumes:
        - storage:/srv/storage
        - ../backend/models:/srv/models:ro
    caddy:
      image: caddy:2
      restart: unless-stopped
      env_file: .env
      ports: ["80:80", "443:443"]
      volumes:
        - ./Caddyfile:/etc/caddy/Caddyfile:ro
        - ../mobile/build/web:/srv/web:ro
        - caddy_data:/data
  volumes:
    pgdata:
    storage:
    caddy_data:
  ```

- [ ] Tạo `deploy/.env.example` (commit file này) và `deploy/.env` (không commit):

  ```dotenv
  DOMAIN=example.edu.vn
  POSTGRES_USER=app
  POSTGRES_PASSWORD=<mật khẩu ngẫu nhiên>
  POSTGRES_DB=diemdanh
  DATABASE_URL=postgresql://app:<mật khẩu>@db:5432/diemdanh
  JWT_SECRET=<chuỗi ngẫu nhiên dài>
  DATA_KEY=<base64 32 byte>
  STORAGE_DIR=/srv/storage
  CORS_ORIGIN_REGEX=^https://app\.example\.edu\.vn$
  ```

- [ ] Build và chạy thử toàn bộ trên máy mình

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS\mobile
  flutter build web --release --dart-define=API_URL=https://api.example.edu.vn
  cd ..\deploy
  docker compose build
  docker compose up -d db backend
  docker compose exec backend alembic upgrade head
  docker compose logs backend --tail 20
  ```
  Mong đợi: build không lỗi, log có dòng `Uvicorn running on http://0.0.0.0:8000`, migration chạy xong. (Caddy chỉ thử được thật khi đã có tên miền, ở Bước 10.)

- [ ] Commit: `git commit -am "chore(deploy): Dockerfile, compose, Caddy"`

---

## Bước 10. Triển khai lên VPS (Ubuntu 24.04)

- [ ] Trỏ DNS: bản ghi A cho `api.<tên miền>` và `app.<tên miền>` về IP của VPS. Kiểm tra: `nslookup api.<tên miền>` trả đúng IP.
- [ ] Đăng nhập VPS, cập nhật hệ thống, tạo user thường, chỉ cho đăng nhập SSH bằng khóa

  ```bash
  ssh root@<IP>
  apt update && apt upgrade -y
  adduser deploy && usermod -aG sudo deploy
  ```

- [ ] Tường lửa

  ```bash
  ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw enable
  ufw status
  ```

- [ ] Cài Docker

  ```bash
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker deploy
  docker run --rm hello-world
  ```

- [ ] Đưa mã nguồn, mô hình và bản web lên

  ```bash
  git clone <địa chỉ repo> /opt/diemdanh
  ```
  ```powershell
  # từ máy Windows: file mô hình và bản web không nằm trong git
  scp backend\models\*.onnx deploy@<IP>:/opt/diemdanh/backend/models/
  scp -r mobile\build\web deploy@<IP>:/opt/diemdanh/mobile/build/
  ```

- [ ] Tạo `/opt/diemdanh/deploy/.env` với **bí mật mới** (không dùng lại giá trị lúc phát triển). Lưu `DATA_KEY` vào trình quản lý mật khẩu hoặc nơi an toàn riêng: **mất khóa này là mất toàn bộ embedding**.
- [ ] Chạy

  ```bash
  cd /opt/diemdanh/deploy
  docker compose up -d --build
  docker compose exec backend alembic upgrade head
  docker compose ps
  curl -I https://api.<tên miền>/docs
  ```
  Mong đợi: 3 service ở trạng thái `running`, `curl` trả `HTTP/2 200`, trình duyệt mở `https://app.<tên miền>` thấy màn đăng nhập.

- [ ] Tạo tài khoản quản trị đầu tiên (một lần)

  ```bash
  docker compose exec backend python -m app.cli create-admin --username admin
  ```

- [ ] Cron dọn dữ liệu và sao lưu (`crontab -e` của user `deploy`):

  ```cron
  0 3 * * * cd /opt/diemdanh/deploy && docker compose exec -T backend python -m app.jobs.cleanup
  30 3 * * * cd /opt/diemdanh/deploy && docker compose exec -T db pg_dump -U app diemdanh | gzip > /opt/backup/diemdanh-$(date +\%F).sql.gz
  0 4 * * * find /opt/backup -name 'diemdanh-*.sql.gz' -mtime +14 -delete
  ```
  Tạo thư mục trước: `mkdir -p /opt/backup`.

- [ ] **Thử khôi phục bản sao lưu** vào một database tạm, và kiểm tra có đủ dữ liệu

  ```bash
  docker compose exec -T db createdb -U app restore_test
  gunzip -c /opt/backup/diemdanh-<ngày>.sql.gz | docker compose exec -T db psql -U app -d restore_test
  docker compose exec db psql -U app -d restore_test -c "select count(*) from users"
  docker compose exec db dropdb -U app restore_test
  ```

- [ ] Cập nhật phiên bản mới về sau:

  ```bash
  cd /opt/diemdanh && git pull
  cd deploy && docker compose up -d --build && docker compose exec backend alembic upgrade head
  ```

---

## Bước 11. Build app để phát cho người dùng

- [ ] **Android: tạo khóa ký app** (một lần, giữ file này cẩn thận; mất khóa thì không cập nhật được app đã cài)

  ```powershell
  keytool -genkey -v -keystore $env:USERPROFILE\diemdanh-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias diemdanh
  ```
  Tạo `mobile/android/key.properties` (đã có trong `.gitignore`) và cấu hình `signingConfigs.release` trong `android/app/build.gradle(.kts)` theo hướng dẫn "Build and release an Android app" của Flutter.

- [ ] Build APK

  ```powershell
  cd D:\DiemDanhKhuonMat_GPS\mobile
  flutter build apk --release --dart-define=API_URL=https://api.<tên miền>
  ```
  Mong đợi: file `build\app\outputs\flutter-apk\app-release.apk`. Cài thử trên máy thật, đăng nhập được qua HTTPS.

- [ ] **iOS**: cần máy Mac có Xcode và tài khoản Apple Developer (phát qua TestFlight). Không có Mac thì ghi rõ trong báo cáo là chạy thử chỉ trên Android, hoặc mượn Mac để build một lần.
- [ ] **Web** cho giảng viên và quản trị viên: build lại (`flutter build web --release --dart-define=API_URL=https://api.<tên miền>`), chép `build/web` lên VPS như Bước 10. Caddy phục vụ thẳng, không cần khởi động lại.

---

## Bước 12. Kiểm thử và chạy thử thật

- [ ] Đo GPS ở 3 phòng trở lên, chạy `python experiments/gps_analysis.py`, chốt `default_r0_m` và `max_acc_student_m` vào `config.yaml`, rồi `docker compose restart backend`.
- [ ] Kiểm thử tải từ máy phát triển

  ```powershell
  locust -f experiments/locustfile.py --host https://api.<tên miền> --users 60 --spawn-rate 1 --run-time 3m --headless
  ```
  Mong đợi: p95 < 3 s, tỉ lệ lỗi 0 %.

- [ ] **Trước buổi chạy thử với lớp thật**, kiểm tra:
  - [ ] Nhà trường đã cho phép bằng văn bản; mọi sinh viên đã đồng ý trong app
  - [ ] `config.yaml` không còn ngưỡng `0.0`; `model_name` khớp với mô hình đã dùng khi sinh viên đăng ký
  - [ ] Bí mật trên VPS là giá trị mới; `DATA_KEY` đã lưu ở nơi an toàn riêng; đã thử khôi phục bản sao lưu thành công
  - [ ] Sinh viên không nhận được điểm số hay cờ trong bất kỳ response nào; giảng viên gọi tài nguyên lớp khác bị 404
  - [ ] Log server không in token, mật khẩu, embedding hay ảnh
  - [ ] Phòng học có sóng mạng; giảng viên biết cách mở phiên, duyệt lượt đáng ngờ, tính lại tâm, đặt trạng thái tay khi mất mạng
- [ ] Chạy thử một buổi, ghi lại: tỉ lệ thành công lần đầu, số lần thử trung bình, tỉ lệ đáng ngờ, phản hồi của giảng viên và sinh viên.
