/// Thông điệp tiếng Việt cho mã lý do khuôn mặt (đặc tả mục 9.5), dùng ở đăng ký và điểm danh.
const faceReasons = {
  'FACE_NOT_FOUND': 'Không thấy khuôn mặt trong khung hình',
  'MULTIPLE_FACES': 'Chỉ một người trong khung hình',
  'LOW_LIGHT': 'Thiếu sáng, hãy ra chỗ sáng hơn',
  'BLURRY': 'Ảnh bị mờ, hãy giữ máy chắc tay',
  'SPOOF_DETECTED': 'Không xác nhận được người thật',
  'INCONSISTENT_FACE': 'Ảnh không giống các ảnh còn lại',
  'ACTION_NOT_DETECTED': 'Chưa thấy bạn thực hiện hành động được yêu cầu',
  'FACE_MISMATCH': 'Khuôn mặt không khớp với tài khoản',
};

String faceReason(String code) => faceReasons[code] ?? 'Ảnh chưa đạt ($code)';
