import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_models.dart';

void main() {
  // 这是从本地认证中心抓到的**真实响应原文**，不是手写的理想样例。
  const raw = '{"code":0,"data":{"status":"pending","pc":'
      '{"ua":"Edge · Windows","ip":"127.0.0.1","geo":"本机",'
      '"created_at":"2026-10-11T05:34:21Z"}}}';

  test('QrPreview 能从真实响应里取到设备画像', () {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    final data = envelope['data'] as Map<String, dynamic>;
    final p = QrPreview.fromJson(data);

    expect(p.pcUa, 'Edge · Windows');
    expect(p.pcIp, '127.0.0.1');
    expect(p.pcGeo, '本机');
    expect(p.hasMeaningfulDeviceInfo, isTrue,
        reason: '画像有值却不"有意义"，确认按钮会被无端禁掉');
  });

  test('pc 缺失时不崩，且判定为无意义（该拒绝出确认按钮）', () {
    final p = QrPreview.fromJson({'status': 'pending'});
    expect(p.pcUa, isEmpty);
    expect(p.hasMeaningfulDeviceInfo, isFalse);
  });
}
