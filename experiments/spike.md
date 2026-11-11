# Task 0 — Kết quả thử mô hình

Máy đo: PC, webcam rời, CPU  ·  Ngày: 2026-11-11  ·  Mô hình embedding: `w600k_r50.onnx`

Cách đo xem `spike_face.py` (đầu file). Số webcam lấy từ lệnh `summary`; số thô trong `experiments/data/spike_log.csv` (không đưa vào git).

## 1. Kiểm tra trên ảnh mẫu

| Ảnh | Mặt | Rộng | Sáng | Nét | yaw | spoof (thật) |
| --- | --- | --- | --- | --- | --- | --- |
| `lena.jpg` (OpenCV samples) | 1 | 146 | 117 | 1247 | +0,17 | 1,00 |
| Cùng ảnh lật ngang | 1 | 149 | 117 | 1274 | −0,11 | 1,00 |

- Lật ảnh thì `yaw` đổi dấu: chỉ số quay đầu đúng hướng.
- Cosine ảnh gốc / ảnh lật: R50 0,926; MobileFaceNet 0,922.
- Ảnh rỗng, không phải JPEG, ảnh 7000×7000: trả "không thấy mặt", không lỗi.

## 2. Webcam, một người, 10 khung mỗi tình huống

| Nhãn | spoof tb | spoof nhỏ nhất | spoof lớn nhất | cos với mẫu (tb) | Sáng tb | Nét tb |
| --- | --- | --- | --- | --- | --- | --- |
| that (mặt thật) | 0,98 | **0,95** | 1,00 | 0,92 | 131 | 4686 |
| anh_in | 0,00 | 0,00 | 0,02 | 0,73 | 187 | 250 |
| man_hinh (ảnh trên điện thoại) | 0,00 | 0,00 | 0,00 | 0,72 | 182 | 196 |
| video (trên điện thoại) | 0,26 | 0,00 | **0,68** | 0,65 | 187 | 231 |
| toi (bớt sáng) | 1,00 | 1,00 | 1,00 | 0,78 | 113 | 2706 |
| rung (lắc đầu) | 1,00 | 0,99 | 1,00 | 0,56 (nhỏ nhất 0,38) | 137 | 2445 |

Thời gian CPU mỗi khung: phát hiện 5 ms, embedding R50 95 ms, anti-spoofing 1,3 ms. Một lượt điểm danh 6–8 khung ≈ 0,7 s.

### Nhận xét

- **Anti-spoofing tách rõ thật / giả.** Mặt thật thấp nhất 0,95; ảnh in và ảnh trên màn hình gần 0; video cao nhất 0,68.
  Ngưỡng tạm `antispoof_threshold = 0.8`: chặn được mọi khung giả đo được, vẫn cách mặt thật thấp nhất 0,15.
  Video là trường hợp sát nhất (0,68). Nếu video lọt, lớp thử thách quay đầu ngẫu nhiên vẫn chặn được video quay sẵn.
  Verify lấy điểm **thấp nhất** của 3 khung nét nhất nên một khung video lọt cũng không đủ.
- **Rung làm cosine tụt** (nhỏ nhất 0,38) dù độ nét vẫn ~1800+. Độ nét đo trên mặt đã căn chỉnh 112×112 của webcam này rất cao (thật ~4700, ảnh giả ~200), nên ngưỡng `min_sharpness = 50` hiện tại không bắt được ảnh rung.
  Chưa đủ dữ liệu để nâng ngưỡng: camera trước điện thoại + JPEG nén có thể cho số rất khác. Tạm giữ 50; đo lại khi có ảnh điện thoại. Ảnh rung hiện sẽ bị chặn ở bước so khớp (cosine thấp) thay vì báo "ảnh mờ".
- **Chỗ tối**: webcam tự tăng phơi sáng nên độ sáng chỉ xuống 113. Chưa đo được ngưỡng tối; giữ `min_brightness = 60`.
- **Cosine với chính mình**: mặt thật nhìn thẳng 0,91–0,93; ảnh của chính mình trên giấy/màn hình 0,71–0,73 (vẫn là cùng người, chỉ kém chất lượng).

## 3. Góc quay đầu — ảnh chụp bằng camera trước điện thoại (CHƯA ĐO)

Chụp 3 ảnh bằng camera trước: nhìn thẳng, quay sang **trái của bạn** khoảng 20°, quay sang phải khoảng 20°. Chép sang máy rồi chạy `images`.

| Ảnh | yaw |
| --- | --- |
| Nhìn thẳng | |
| Quay trái của bạn ~20° | |
| Quay phải của bạn ~20° | |

- Quay trái ra yaw âm → `yaw_sign = 1`; ra yaw dương → `yaw_sign = -1`.
- `yaw_threshold` ≈ |yaw| khi quay ~20°. Trên webcam, lắc đầu đạt |yaw| tới 0,47; giá trị tạm 0,25 có vẻ hợp lý.

## 4. Cùng người / khác người (CHƯA ĐO)

Lệnh `cos` trên ảnh của ít nhất 3 người (mỗi người 2 ảnh). Cần để chọn `accept_threshold`, `suspect_threshold` (chốt ở Task 11).

## 5. Cổng 0

- [x] Anti-spoofing tách được mặt thật với ảnh in, màn hình (gần 0) và video (≤ 0,68) → `antispoof_threshold = 0.8` (tạm, đo thêm ở Task 11)
- [ ] Cosine cùng người > khác người rõ rệt → cần ảnh của người khác

Kết luận tạm: **qua phần chống giả mạo**. Mô hình dùng được, đi tiếp T8 (engine) và T9 (API đăng ký). Còn nợ: góc quay trên ảnh điện thoại và cosine khác người.
