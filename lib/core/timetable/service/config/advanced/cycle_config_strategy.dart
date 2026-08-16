import 'package:flutter/material.dart';
import '../../../domain/models.dart';
import '../../../../../../widgets/theme/zen_theme.dart';
import 'shared/zen_controls.dart';

/// 高级设置「周期配置」策略 —— 3 模式各自声明可调性（fr 30）。
///
/// 解决：通用模式应可自定义每周期天数(1-7)，学校模式固定 7 天，
/// 追剧模式由剧模型自动派生。此前页面用 `if (isSchoolMode)` 分支硬编码，
/// 通用/追剧被误锁 7 天。现由 [cycleStrategyFor] 按 config 路由，
/// 页面零模式分支。
abstract class CycleConfigStrategy {
  const CycleConfigStrategy();

  /// 每周期天数固定值：null = 可调（slider 1-7）；非 null = 该模式强制
  int? get fixedDaysPerCycle;

  /// 每天节数上限（追剧每剧独占 slot 允许到 64；学校/通用手动上限 6）
  int get maxSlotsPerDay;

  /// 是否允许手动配置周期相关数字（追剧 = false，由剧模型派生）
  bool get allowsManualConfig;

  /// 该模式周期配置区的提示文案（追剧模式显示）
  String? get hint;

  /// 保存时实际生效的 daysPerCycle
  int resolveDaysPerCycle(int userConfigured) =>
      fixedDaysPerCycle ?? userConfigured;

  /// 构建周期配置区 UI（页面只调本方法，不感知模式）
  Widget buildCycleSection({
    required int cycleCount,
    required int daysPerCycle,
    required int slotsPerDay,
    required ValueChanged<int> onCycleCountChanged,
    required ValueChanged<int> onDaysPerCycleChanged,
    required ValueChanged<int> onSlotsPerDayChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!allowsManualConfig) ...[
          Text(hint ?? '周期配置由模型自动派生', style: ZenText.label),
        ] else ...[
          ZenConfigSlider(
            label: '周期数',
            value: cycleCount.toDouble(),
            min: TimetableConfig.minCycles.toDouble(),
            max: TimetableConfig.maxCycles.toDouble(),
            divisions: TimetableConfig.maxCycles - TimetableConfig.minCycles,
            onChanged: (v) => onCycleCountChanged(v.round()),
          ),
          if (fixedDaysPerCycle != null)
            ZenFixedLabel(label: '每周期天数', value: '$fixedDaysPerCycle 天（固定）')
          else
            ZenConfigSlider(
              label: '每周期天数 (1-7)',
              value: daysPerCycle.toDouble(),
              min: TimetableConfig.minDaysPerCycle.toDouble(),
              max: TimetableConfig.maxDaysPerCycle.toDouble(),
              divisions:
                  TimetableConfig.maxDaysPerCycle -
                  TimetableConfig.minDaysPerCycle,
              onChanged: (v) => onDaysPerCycleChanged(v.round()),
            ),
          ZenConfigSlider(
            label: '每天节数 (1-$maxSlotsPerDay)',
            value: slotsPerDay.toDouble(),
            min: TimetableConfig.minSlotsPerDay.toDouble(),
            max: maxSlotsPerDay.toDouble(),
            divisions: maxSlotsPerDay - TimetableConfig.minSlotsPerDay,
            onChanged: (v) => onSlotsPerDayChanged(v.round()),
          ),
        ],
      ],
    );
  }
}

/// 学校模式：周一固定 7 天，天数不可调
class SchoolCycleStrategy extends CycleConfigStrategy {
  const SchoolCycleStrategy();

  @override
  int? get fixedDaysPerCycle => 7;

  @override
  int get maxSlotsPerDay => TimetableConfig.maxManualSlotsPerDay;

  @override
  bool get allowsManualConfig => true;

  @override
  String? get hint => null;
}

/// 通用模式：周期数/每周期天数(1-7)/每天节数 全部可调
class GeneralCycleStrategy extends CycleConfigStrategy {
  const GeneralCycleStrategy();

  @override
  int? get fixedDaysPerCycle => null;

  @override
  int get maxSlotsPerDay => TimetableConfig.maxManualSlotsPerDay;

  @override
  bool get allowsManualConfig => true;

  @override
  String? get hint => null;
}

/// 追剧模式：行列周期由剧模型自动派生，不提供手动配置
class AnimeCycleStrategy extends CycleConfigStrategy {
  const AnimeCycleStrategy();

  @override
  int? get fixedDaysPerCycle => 7; // 生成器恒 7 天

  @override
  int get maxSlotsPerDay => TimetableConfig.maxSlotsPerDay;

  @override
  bool get allowsManualConfig => false;

  @override
  String? get hint => '追剧模式的行列周期由剧模型自动派生（起点对齐周一 · 每天行数=剧数 · 总周数=最长覆盖）';
}

/// 按 config 路由周期配置策略（新增模式在此登记）
CycleConfigStrategy cycleStrategyFor(TimetableConfig config) {
  if (config.isAnimeMode) return const AnimeCycleStrategy();
  if (config.isSchoolMode) return const SchoolCycleStrategy();
  return const GeneralCycleStrategy();
}
