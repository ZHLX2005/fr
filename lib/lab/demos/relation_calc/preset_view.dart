// 预设页 —— 亲戚称呼预设说明 + 重置入口。
//
// 重置：清空用户自定义数据，恢复内置预设（需确认）。

import 'package:flutter/material.dart';
import '../../../widgets/context_colors.dart';

import '../../../../core/theme/component/zen/zen_theme.dart';
import 'const_relation_calc.dart';

class PresetView extends StatelessWidget {
  const PresetView({super.key, required this.onReset});

  /// 重置回内置预设（页面壳负责持久化 + 刷新数据）。
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZenSection(
            title: RelationCalcUiText.presetInfoTitle,
            child: Text(RelationCalcUiText.presetInfoBody, style: ZenText.body),
          ),
          SizedBox(height: 12),
          ZenSection(
            title: '自定义领域',
            child: Text(
              '引擎不感知领域：除了亲戚称呼，你可以在「管理」页自定义任意关系'
              '（如公司团队：组长 的 上级 = 经理，经理 的 上级 = 总监），'
              '链式传递、无限嵌套。',
              style: ZenText.body,
            ),
          ),
          SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await ZenConfirmDialog.show(
                  context: context,
                  title: RelationCalcUiText.resetPreset,
                  message: RelationCalcUiText.resetPresetConfirm,
                  onConfirm: () {},
                  confirmLabel: RelationCalcUiText.resetPreset,
                );
                if (ok) onReset();
              },
              style: zenButtonTheme(context,
                foreground: context.colors.danger,
                border: context.colors.danger,
              ),
              icon: Icon(Icons.restart_alt, size: 18),
              label: Text(RelationCalcUiText.resetPreset),
            ),
          ),
        ],
      ),
    );
  }
}
