// 通用关系计算器 —— demo 注册 + 页面壳（方案 A：单模块多文件，主文件 <400 行）。
//
// 变量系统模型：A 的 B = C，C 的 D = E … 无限嵌套、链式传递。
// 引擎不感知领域（亲戚/公司团队等级/宠物…），内置亲戚称呼预设。

import 'package:flutter/material.dart';
import '../../widgets/context_colors.dart';

import '../../core/theme/component/zen/zen_theme.dart';
import '../lab_container.dart';
import 'relation_calc/calc_view.dart';
import 'relation_calc/const_relation_calc.dart';
import 'relation_calc/kinship_preset.dart';
import 'relation_calc/manage_view.dart';
import 'relation_calc/preset_view.dart';
import 'relation_calc/relation_calc_models.dart';
import 'relation_calc/relation_calc_store.dart';

/// Demo 注册。
class RelationCalcDemo extends DemoPage {
  @override
  String get title => RelationCalcConsts.demoTitle;

  @override
  String get slug => RelationCalcConsts.demoSlug;

  @override
  String get description => RelationCalcConsts.demoDescription;

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const RelationCalcPage();

}

void registerRelationCalcDemo() {
  demoRegistry.register(RelationCalcDemo());
}

/// 主页面：计算 / 管理 / 预设 三 Tab。
///
/// 持库：启动加载整库快照，空库自动导入亲戚预设；
/// 子视图（计算/管理）通过 [RelationGraphData] 快照 + 变更回调协作，
/// 管理视图改动后回调 [onDataChanged] 重建引擎。
class RelationCalcPage extends StatefulWidget {
  const RelationCalcPage({super.key});

  @override
  State<RelationCalcPage> createState() => _RelationCalcPageState();
}

class _RelationCalcPageState extends State<RelationCalcPage> {
  RelationGraphData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store = RelationCalcStore.instance;
    var data = await store.load();
    if (data.entities.isEmpty && data.rules.isEmpty) {
      // 首次进入：自动导入亲戚预设。
      data = kinshipPresetData();
      await store.save(data);
    }
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _onDataChanged(RelationGraphData data) async {
    await RelationCalcStore.instance.save(data);
    if (!mounted) return;
    setState(() => _data = data);
  }

  Future<void> _resetToPreset() async {
    final preset = kinshipPresetData();
    await RelationCalcStore.instance.save(preset);
    if (!mounted) return;
    setState(() => _data = preset);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.accent),
      );
    }
    final data = _data!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: context.colors.surface,
        appBar: AppBar(
          backgroundColor: context.colors.surface,
          elevation: 0,
          title: Text(RelationCalcConsts.demoTitle,
              style: ZenText.title),
          bottom: TabBar(
            labelColor: context.colors.accent,
            unselectedLabelColor: context.colors.textMuted,
            indicatorColor: context.colors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: RelationCalcUiText.calcTab),
              Tab(text: RelationCalcUiText.manageTab),
              Tab(text: RelationCalcUiText.presetTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            CalcView(data: data),
            ManageView(data: data, onDataChanged: _onDataChanged),
            PresetView(onReset: _resetToPreset),
          ],
        ),
      ),
    );
  }
}
