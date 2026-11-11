# Mô hình khuôn mặt

File `.onnx` không đưa vào git (`.gitignore`). Tải lại theo bảng dưới, rồi kiểm tra sha256:

```powershell
Get-FileHash backend\models\*.onnx -Algorithm SHA256
```

| File | Vai trò | Nguồn | Giấy phép | sha256 |
| --- | --- | --- | --- | --- |
| `face_detection_yunet_2023mar.onnx` | Phát hiện mặt + 5 điểm mốc | [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) | MIT | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` |
| `w600k_r50.onnx` | Embedding ArcFace R50 (512 chiều), mặc định | InsightFace `buffalo_l.zip` ([release v0.7](https://github.com/deepinsight/insightface/releases/tag/v0.7)) | Chỉ phi thương mại, nghiên cứu | `4c06341c33c2ca1f86781dab0e829f88ad5b64be9fba56e56bc9ebdefc619e43` |
| `w600k_mbf.onnx` | Embedding MobileFaceNet (512 chiều), bản nhẹ để so sánh | InsightFace `buffalo_sc.zip` (release v0.7) | Chỉ phi thương mại, nghiên cứu | `9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f` |
| `MiniFASNetV2.onnx` | Chống giả mạo, đầu vào 80×80, crop 2,7 lần khung mặt | Bản ONNX của [yakhyo/face-anti-spoofing](https://github.com/yakhyo/face-anti-spoofing/releases/tag/weights), chuyển từ [Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) | Apache-2.0 (gốc) | `b32929adc2d9c34b9486f8c4c7bc97c1b69bc0ea9befefc380e4faae4e463907` |

Ghi chú

- Mô hình InsightFace chỉ được dùng cho mục đích phi thương mại. Đồ án môn học dùng được; muốn thương mại hóa phải thay mô hình hoặc mua giấy phép.
- MiniFASNetV2 bản ONNX do bên thứ ba chuyển đổi. Tiền xử lý: ảnh BGR, giá trị 0–255 dạng float, NCHW, softmax trên 3 lớp, lớp 1 là người thật.
- ArcFace: ảnh căn chỉnh 112×112 theo 5 điểm mốc chuẩn, RGB, `(x − 127,5) / 127,5`, chuẩn hóa L2 đầu ra.
- Đổi file embedding thì đổi `face.model_name` trong `config.yaml`: mẫu khuôn mặt của mô hình cũ trở thành không hợp lệ (đặc tả mục 4.2).

## Ảnh mẫu cho `tests/test_onnx_engine.py`

Không đưa vào git (ảnh có khuôn mặt người). Tạo lại từ ảnh mẫu của OpenCV:

```powershell
curl.exe -sL -o tests/fixtures/faces/a1.jpg https://raw.githubusercontent.com/opencv/opencv/4.x/samples/data/lena.jpg
curl.exe -sL -o tests/fixtures/faces/b1.jpg https://raw.githubusercontent.com/opencv/opencv/4.x/samples/data/messi5.jpg
.venv/Scripts/python.exe -c "import cv2,numpy as np;a=cv2.imread('tests/fixtures/faces/a1.jpg');h,w=a.shape[:2];m=cv2.getRotationMatrix2D((w/2,h/2),8,1.05);cv2.imwrite('tests/fixtures/faces/a2.jpg',cv2.convertScaleAbs(cv2.warpAffine(a,m,(w,h)),alpha=0.9,beta=15));cv2.imwrite('tests/fixtures/faces/blank.jpg',np.full((480,640,3),200,np.uint8))"
```

Thiếu mô hình hoặc ảnh mẫu thì các test đánh dấu `models` tự bỏ qua.
