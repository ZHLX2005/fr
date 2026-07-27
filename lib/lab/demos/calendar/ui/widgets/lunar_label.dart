import 'package:flutter/material.dart';

import '../../../../../core/theme/typography.dart';
import '../../lunar_adapter.dart';

/// 农历月日小字（紧凑）
class LunarLabel extends StatelessWidget {
  final DateTime solar;
  const LunarLabel({super.key, required this.solar});

  @override
  Widget build(BuildContext context) {
    final l = LunarAdapter().fromSolar(solar);
    final text = l.isLeap ? '闰${l.month}月${l.day}' : '${l.month}月${l.day}';
    return Text(text, style: AppText.caption());
  }
}