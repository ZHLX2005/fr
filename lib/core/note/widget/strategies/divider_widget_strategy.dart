import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_widget_strategy.dart';

class DividerWidgetStrategy extends BlockWidgetStrategy {
  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    return const Divider(height: 1, thickness: 1);
  }
}
