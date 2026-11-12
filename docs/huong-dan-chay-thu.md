# Hướng dẫn chạy thử trên máy PC (không cần Docker)

Mục tiêu: chạy trọn một vòng nhập CSV → đăng ký mặt → duyệt → mở phiên → điểm danh → duyệt tay → đóng → báo cáo, chỉ với một máy tính có webcam.

> Chế độ dev nới ngưỡng GPS (50 km) và dùng khuôn viên phủ cả Việt Nam (`config.dev.yaml`, `campus.dev.geojson`), vì PC định vị qua Wi-Fi sai hàng trăm mét. Chỉ để thử luồng, **không** phản ánh độ chính xác thật. Ngưỡng thật thử trên điện thoại (mục 13).

## 1. Bật hệ thống

Mở hai cửa sổ PowerShell.

**Backend** (chạy migration rồi chạy API ở cổng 8000). Bật Docker Desktop trước, rồi:

```powershell
cd D:\DiemDanhKhuonMat_GPS\backend
powershell -ExecutionPolicy Bypass -File scripts\dev_backend.ps1 -Docker
```

`-Docker` bật container `db` (chỉ có Postgres; backend và app chạy thẳng trên máy) và dùng `DATABASE_URL` trong `.env`.
Không có Docker thì bỏ `-Docker`: script dùng Postgres nhúng ở `backend/.pgdata` (CSDL riêng, phải tạo admin lại).

Thấy `Application startup complete.` là xong.

**App web** (lần đầu chờ khoảng 20 giây):

```powershell
cd D:\DiemDanhKhuonMat_GPS\mobile
flutter run -d web-server --web-port 8091 --dart-define=API_URL=http://localhost:8000 --dart-define=DEV_GPS=true
```

Mở http://localhost:8091.

## 2. Tạo tài khoản quản trị (chỉ làm một lần cho mỗi CSDL)

CSDL Docker đã có `admin` thì bỏ qua bước này. Nếu chưa có, mở thêm một cửa sổ PowerShell:

```powershell
cd D:\DiemDanhKhuonMat_GPS\backend
.\.venv\Scripts\python.exe -m app.cli create-admin --username admin
```

Dùng Postgres nhúng thì chạy thêm `$env:DATABASE_URL = (.\.venv\Scripts\python.exe scripts\dev_db.py)` trước lệnh trên.

Lệnh in ra mật khẩu tạm. Ghi lại, lần đăng nhập đầu sẽ phải đổi.

## 3. Cần ba cửa sổ trình duyệt tách biệt

Trên web, một trình duyệt chỉ giữ được một phiên đăng nhập. Để đóng vai cùng lúc, dùng:

| Vai | Cửa sổ |
| --- | --- |
| Quản trị, sau đó Giảng viên | Chrome thường |
| Sinh viên | Chrome **ẩn danh** (Ctrl+Shift+N) |
| Giảng viên (nếu muốn song song với quản trị) | Edge |

Mọi cửa sổ đều mở http://localhost:8091.

## 4. Quản trị: nhập dữ liệu mẫu

1. Đăng nhập `admin`, đổi mật khẩu.
2. Mục **Nhập CSV**, chọn loại **Người dùng**, chọn file `docs/du-lieu-mau/users.csv`, bấm kiểm tra rồi xác nhận nhập.
   Màn kết quả có danh sách **mật khẩu tạm** của `gv.duc`, `sv001`, `sv002`, `sv003`: tải file về hoặc chép lại.
3. Nhập tiếp `classes.csv` (loại **Lớp**), rồi `enrollments.csv` (loại **Danh sách lớp**).
4. Kiểm tra ở mục **Lớp**: lớp IT4060 có 3 sinh viên, giảng viên là TS. Trần Minh Đức.

## 5. Sinh viên: đăng ký khuôn mặt

Cửa sổ ẩn danh:

1. Đăng nhập `sv001` bằng mật khẩu tạm, đổi mật khẩu.
2. Trang chủ, bấm **Đăng ký khuôn mặt**, đọc rồi đồng ý văn bản.
3. Cho phép trình duyệt dùng camera. Chụp 3 ảnh: nhìn thẳng, quay trái, quay phải. Chỗ sáng, mặt rõ, không đeo khẩu trang.
4. Gửi xong sẽ thấy trạng thái **Chờ duyệt**. Nếu ảnh bị loại, đọc lý do dưới từng ảnh và chụp lại.

## 6. Giảng viên: duyệt mặt, mở phiên, chiếu mã

Cửa sổ Chrome thường (đăng xuất `admin` trước) hoặc Edge:

1. Đăng nhập `gv.duc`, đổi mật khẩu.
2. Tab **Duyệt mặt**: mở yêu cầu của Nguyễn Văn An, xem ảnh, bấm **Duyệt**.
3. Tab **Lớp**: ở lớp IT4060 bấm **Mở phiên**. Cho phép trình duyệt dùng vị trí.
   Chờ thanh mẫu GPS đủ 5/5, để nguyên 10 phút và r₀ 20 m, **bật mã phòng**, rồi bấm **Mở phiên điểm danh**.
4. Màn **Phiên đang chạy** hiện ra. Bấm nút QR trên đầu trang để mở màn **Chiếu mã phòng**: mã 8 ký tự đổi mỗi 30 giây.

## 7. Sinh viên: điểm danh

Cửa sổ ẩn danh:

1. Bấm F5 để tải lại trang chủ: thẻ lớp IT4060 có nhãn **Đang mở điểm danh**. Bấm **Điểm danh ngay**.
2. Bước **Mã phòng**: webcam khó quét QR trên chính màn hình máy mình, nên gõ mã 8 ký tự đang hiện ở màn chiếu vào ô **Nhập mã dưới QR**, rồi bấm **Xác nhận**. Mã đổi sau 30 giây, gõ nhanh.
3. Bước **Vị trí**: cho phép vị trí, chờ đủ 3/3 mẫu.
4. Bước **Khuôn mặt**: đọc hành động trên thẻ trắng (vd *Quay đầu sang trái*), bấm **Bắt đầu**. Nhìn thẳng khoảng nửa giây, rồi quay đầu rõ ràng theo hướng được yêu cầu cho tới khi chụp đủ 6/6.
5. Màn kết quả có một trong ba dạng:
   - **Đã điểm danh**.
   - **Đang chờ giảng viên**: lượt bị gắn cờ.
   - **Chưa điểm danh được**: có lý do và nút **Thử lại**, tối đa 5 lượt mỗi phiên.

## 8. Giảng viên: theo dõi, duyệt tay, đóng, báo cáo

1. Màn **Phiên đang chạy** tự làm mới mỗi 4 giây: bộ đếm Có mặt / Đáng ngờ / Chưa thay đổi.
2. Lọc **Tất cả** hoặc **Chưa**, chạm vào `sv002` (chưa điểm danh), chọn **Vắng có phép**, ghi chú, rồi bấm **Lưu quyết định**.
3. Bấm **Đóng** và xác nhận. Sau khi đóng vẫn sửa được kết quả.
4. Về **Lớp**, bấm **Lịch sử**: thấy buổi vừa rồi. Nút biểu đồ trên đầu trang mở **Báo cáo**:
   **Xuất Excel** (sheet Tổng hợp + Chi tiết từng buổi), **PDF nộp khoa** (A4, có chỗ ký), hoặc **CSV**.
   Tên trường và khoa trên báo cáo sửa ở mục `report:` trong `backend/config.yaml`.
5. Quản trị cũng xem được báo cáo ở mục **Báo cáo**.
6. Sinh viên mở tab **Lịch sử** để thấy buổi vừa điểm danh.

## 9. Những phần khác nên thử

- **Đổi mật khẩu**: sinh viên ở tab Tài khoản (biểu tượng ổ khóa), giảng viên ở bảng Tài khoản trên dock, quản trị và giảng viên trên web ở menu ⋮ cạnh tên.
- **Thông báo** (chuông trên trang chủ sinh viên): có chấm đỏ khi lớp đang mở điểm danh hoặc ảnh khuôn mặt bị từ chối.
- **Giảng viên trên laptop** (cửa sổ rộng ≥ 900 px): thanh bên có Phiên điểm danh, Chiếu mã phòng, Duyệt khuôn mặt, Báo cáo.
- **Quên mật khẩu quản trị**: `.\.venv\Scripts\python.exe -m app.cli reset-password --username admin` (in mật khẩu tạm mới).
- **Dọn dữ liệu cũ**: `.\.venv\Scripts\python.exe -m app.jobs.cleanup` (trên VPS chạy bằng cron hằng ngày).

## 10. Đơn xin nghỉ, khiếu nại, cảnh báo, tổng quan

1. Giảng viên mở rồi **đóng** một phiên mà `sv002` không điểm danh.
2. `sv002` → tab **Lịch sử** → buổi đó → **Xin nghỉ / khiếu nại**: chọn loại, ghi lý do, đính kèm ảnh (tùy chọn) → **Gửi đơn**.
3. Giảng viên → tab **Đơn** (điện thoại) hoặc mục **Đơn xin nghỉ, khiếu nại** (web) → **Duyệt** hoặc **Từ chối** (phải ghi lý do).
   Duyệt đơn xin nghỉ → buổi đó thành "Vắng có phép"; duyệt khiếu nại → "Có mặt".
4. Sinh viên vắng từ 3 buổi đã đóng: thẻ đỏ ở Lịch sử, thông báo trên chuông, nhãn "Vắng N buổi" ở danh sách của giảng viên.
5. Quản trị đăng nhập vào thẳng trang **Tổng quan** (tỉ lệ có mặt theo lớp, cờ đáng ngờ, lý do không đạt).
6. Đăng ký khuôn mặt: bật **Tự chụp** (mặc định), nhìn thẳng → quay trái → quay phải theo gợi ý, máy tự giữ ảnh.

## 11. Lịch học, điểm danh hàng loạt, điểm chuyên cần, cấm thi

1. Quản trị → **Lớp** → chọn lớp → mục **Lịch học hằng tuần**: chọn thứ, giờ, phòng → **Thêm lịch**.
   Sinh viên thấy *Lịch hôm nay* trên trang chủ (nút **Cả tuần**) và thông báo "Sắp đến giờ học" trước 30 phút.
2. Giảng viên → **Phiên đang chạy** → **Điểm danh hàng loạt** → chạm chọn nhiều sinh viên → **Có mặt / Có phép / Vắng**.
3. **Báo cáo** có cột **Điểm CC** (thang 10) và nhãn **Cấm thi**; Excel/PDF cũng có.
4. Quản trị → **Cấm thi**: danh sách theo học kỳ, xuất **PDF nộp phòng đào tạo** hoặc Excel.
   Công thức và ngưỡng sửa ở mục `grading:` trong `backend/config.yaml`.

## 12. Lỗi thường gặp

| Hiện tượng | Cách xử lý |
| --- | --- |
| Mở phiên báo GPS kém hoặc ngoài khuôn viên | Backend chưa chạy bằng `dev_backend.ps1`, hoặc app chưa có `--dart-define=DEV_GPS=true` |
| Không lấy được vị trí | Bật **Settings → Privacy & security → Location** của Windows, và cho phép vị trí trong trình duyệt (biểu tượng ổ khóa cạnh địa chỉ) |
| Không mở được camera | Cho phép camera ở biểu tượng ổ khóa; tắt ứng dụng khác đang dùng webcam |
| Điểm danh báo "Sai mã phòng" | Mã đã đổi; gõ mã đang hiện, trong vòng 30 giây |
| Báo "Chưa thấy bạn quay đầu…" | Quay đầu rõ hơn và sớm hơn sau khi bấm Bắt đầu. Nếu luôn sai hướng, `yaw_sign` cần đổi (chốt bằng ảnh điện thoại thật) |
| Trang trắng | Chờ thêm khoảng 20 giây ở lần đầu, rồi bấm F5 |
| Muốn xóa sạch dữ liệu thử | Tắt backend; trong PowerShell ở thư mục backend chạy `.\.venv\Scripts\python.exe -c "import pgserver; pgserver.get_server('.pgdata', cleanup_mode=None).cleanup()"`; xóa thư mục `backend\.pgdata` và `STORAGE_DIR` |

## 13. Thử trên điện thoại thật (bước sau)

Đây là bước để thấy GPS thật và camera trước của điện thoại:

1. Chạy backend với `-Lan`: `powershell -ExecutionPolicy Bypass -File scripts\dev_backend.ps1 -Lan`, rồi mở cổng 8000 trên Windows Firewall.
2. Cắm điện thoại Android (bật USB debugging), chạy `flutter run --dart-define=API_URL=http://<IP-LAN-của-PC>:8000`. Lấy IP bằng lệnh `ipconfig`.
3. Không dùng `DEV_GPS` trên điện thoại. Server vẫn chạy cấu hình dev (khuôn viên phủ cả nước) cho tới khi có đa giác khuôn viên thật.
