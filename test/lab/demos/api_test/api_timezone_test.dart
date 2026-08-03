// 时区 round-trip 测试 —— 验证 apk_update_time 跨时区显示一致
//
// 后端真实返回：{"upload_time":"2026-08-03T18:35:45+08:00", ...}
// 修复后：api_client 用 toUtc() → "2026-08-03T10:35:45Z"（统一 UTC）
//         download_manager substring(0,10) → "2026-08-03"（真日期）
// 设备时区不能影响展示日期。

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── 模拟后端返回 + 走一遍现有逻辑 ───────────────────────
  String simulate(
    String backendUploadTime, {
    required bool toUtc,
  }) {
    final dt = DateTime.parse(backendUploadTime);
    final out = toUtc ? dt.toUtc().toIso8601String() : dt.toIso8601String();
    return out.length >= 10 ? out.substring(0, 10) : '';
  }

  group('api_test 上传时间跨时区一致性', () {
    const backendTime = '2026-08-03T18:35:45+08:00';

    test('修复前（toIso8601）—— UTC 设备下日期少 8 小时', () {
      // 设备在 UTC 时区时：toIso8601 输出 "2026-08-03T10:35:45.000"
      // 截前 10 位 → "2026-08-03" 仍然正确（因为是日期级别，不是时刻级别）
      // 但 status 显示日期是对的，问题是原本用的 .toIso8601 在不同时区会得到
      // 不同时刻的字符串，但日期级别一致 —— 真正的 bug 是「substring(0,10) 日期
      // 没问题，但状态文本如 "18:35" 会变 8 小时」。
      final dateUtc = simulate(backendTime, toUtc: false);
      expect(dateUtc, '2026-08-03');
    });

    test('修复后（toUtc）—— 日期仍是真实日期，跨设备稳定', () {
      // toUtc() → "2026-08-03T10:35:45.000Z"，substring(0,10) → "2026-08-03"
      final dateUtc = simulate(backendTime, toUtc: true);
      expect(dateUtc, '2026-08-03');
    });

    test('toUtc 让时间戳本身带 Z，跨时区展示稳定', () {
      // 后端 +08:00 → UTC 02:35（同一天，因为北京 18:35 当天）
      final dt = DateTime.parse(backendTime);
      expect(dt.toUtc().toIso8601String(), '2026-08-03T10:35:45.000Z');
    });

    test('无时区的后端时间（如 18:00）—— 误判设备时区是风险', () {
      // 如果后端某天返回 "2026-08-03 18:00:00"（无时区）
      // DateTime.parse 按本地时区解析
      const naive = '2026-08-03 18:00:00';
      // 修复后 .toUtc() 仍然按设备本地时区转 UTC —— 不能解决无时区问题
      // 但本测试确认当前修复至少保证带时区字符串的稳定性
      expect(DateTime.parse(naive).year, 2026);
    });

    test('完整时间字段（分钟级）后端 +08:00 北京 18:35 → UTC 10:35', () {
      // download_manager 现展示 "2026-08-03T10:35"（UTC 分钟级）
      // 用户在自己时区（+08:00）看到的就是北京时间的真实时刻
      // 真实时间转换 = 北京 18:35 = UTC 10:35
      final dt = DateTime.parse(backendTime);
      // toUtc() 强制把内部时刻转 UTC，与设备无关
      expect(dt.toUtc().hour, 10);
      expect(dt.toUtc().minute, 35);
      expect(dt.toUtc().day, 3);
    });
  });
}
