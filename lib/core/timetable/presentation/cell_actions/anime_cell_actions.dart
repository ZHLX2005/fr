import 'package:flutter/material.dart';

import '../../../ui/atomic/base_dialog.dart';
import '../../service/config/timetable_anime_editor_page.dart';
import '../timetable_store.dart';
import 'cell_action_manager.dart';

/// 追剧模式 cell 策略：路由到剧模型编辑。
///
/// 课程由剧模型（AnimeSeriesDraft SSOT）自动派生，直接编辑 CourseItem
/// 会在下次剧变更的自动派生中被覆盖 —— 因此：
/// - cell 内课程能按剧名匹配到剧模型 → 打开剧编辑对话框
/// - 空 cell / 匹配不到 → 提示覆盖风险并引导去排期页，不提供直接编辑
class AnimeCellStrategy implements CellActionStrategy {
  @override
  Future<void> openEditor(CellActionContext ctx, CellTarget target) async {
    final state = ctx.ref.read(TimetableStore.provider);
    final store = ctx.ref.read(TimetableStore.provider.notifier);

    // 按 title 匹配剧模型（CourseItem.title 即剧名）
    final title = target.focusCourse?.title;
    var matched = false;
    if (title != null) {
      for (final s in state.animeSeries) {
        if (s.title == title) {
          matched = true;
          ctx.onSelectionChanged(null);
          final draft =
              await showAnimeSeriesEditDialog(ctx.context, initial: s);
          if (draft != null) {
            await store.updateAnimeSeries(draft);
          }
          break;
        }
      }
    }
    if (matched) return;

    // 空 cell / 匹配不到剧：不提供直接编辑（会被自动派生覆盖），引导去排期页
    ctx.onSelectionChanged(null);
    // 确认动作是 push 新路由，须等弹窗关闭后再执行 → 用返回值驱动；
    // onConfirm 为 BaseConfirmDialog 必传参数，此处留空。
    final go = await BaseConfirmDialog.show(
      context: ctx.context,
      title: '追剧模式',
      message: '课程由剧模型自动派生，直接编辑会被覆盖。\n请到追剧排期页添加或修改剧。',
      confirmLabel: '去排期页',
      onConfirm: () {},
    );
    if (go && ctx.context.mounted) {
      await Navigator.push(
        ctx.context,
        MaterialPageRoute(
          builder: (_) => const TimetableAnimeEditorPage(),
        ),
      );
    }
  }
}
