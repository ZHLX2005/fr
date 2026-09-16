// 全局圆环位置持久化。
//
// 存归一化比例（0..1）而不是绝对像素：转屏、换机型、改分辨率后
// 圆环仍落在同一个相对位置，不会跑到屏幕外。
//
// 读写失败一律静默回落 —— 位置丢了顶多回到默认角落，不该因为一个
// 装饰性状态把提交入口卡住。

import 'package:flutter/painting.dart' show Offset, Size;
import 'package:shared_preferences/shared_preferences.dart';

import 'const_global_ring.dart';

class RingPositionStore {
  const RingPositionStore();

  /// 读回上次位置（屏幕像素）。没有记录 / 读失败返回 null，由调用方用默认落位。
  Future<Offset?> load(Size screen) async {
    if (screen.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nx = prefs.getDouble(ConstGlobalRing.prefPosX);
      final ny = prefs.getDouble(ConstGlobalRing.prefPosY);
      if (nx == null || ny == null) return null;
      // 还原成像素；越界由调用方的 clamp 兜底
      return Offset(nx * screen.width, ny * screen.height);
    } catch (_) {
      return null;
    }
  }

  /// 写入当前位置（屏幕像素 → 归一化）。失败静默。
  Future<void> save(Offset pos, Size screen) async {
    if (screen.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(
        ConstGlobalRing.prefPosX,
        (pos.dx / screen.width).clamp(0.0, 1.0),
      );
      await prefs.setDouble(
        ConstGlobalRing.prefPosY,
        (pos.dy / screen.height).clamp(0.0, 1.0),
      );
    } catch (_) {}
  }
}
