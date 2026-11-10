import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// UUID sinh lần đầu và giữ trong secure storage. Không dùng mã phần cứng (đặc tả mục 9.5).
Future<String> deviceId() async {
  const s = FlutterSecureStorage();
  final existing = await s.read(key: 'device_id');
  if (existing != null) return existing;
  final id = const Uuid().v4();
  await s.write(key: 'device_id', value: id);
  return id;
}
