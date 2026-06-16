// 通用测试辅助工具
import 'package:uuid/uuid.dart';

/// 生成测试用唯一设备 ID
String genDeviceId([String prefix = 'test']) {
  return '$prefix-${const Uuid().v4().substring(0, 8)}';
}

/// 创建测试用 FrameworkConfig
// 注：实际 FrameworkConfig 在 Task 11 定义。本文件后续会扩展。
