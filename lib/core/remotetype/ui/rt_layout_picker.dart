// lib/core/remotetype/ui/rt_layout_picker.dart
//
// 布局切换面板（只切换，不编排）。
//
// 竖屏页头与横屏左上角胶囊共用这一份：列出该朝向可用的布局，点一下即切。
// 编排（改名 / 删除 / 新建 / 恢复出厂 / 模块摆放）不在这里——那属于设置页
// （见 settings/rt_settings_page.dart）。画布与写字页是同一张布局表的
// 两种渲染形态（kind=canvas / kind=writer），所以切换面板对两者通用。

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../data/rt_prefs.dart';

/// 打开布局切换面板。
///
/// [layouts] 当前布局集，[orientation] 当前朝向（只列该朝向可用的），
/// [activeId] 当前激活项（打勾），[onPick] 选中回调（面板先自行关闭）。
Future<void> showRtLayoutPicker(
  BuildContext context, {
  required RtCanvasLayouts layouts,
  required String orientation,
  required String activeId,
  required ValueChanged<String> onPick,
}) {
  final usable = layouts.list
      .where((p) => rtCanvasLayoutUsableIn(orientation, p))
      .toList(growable: false);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final c = ctx.colors;
      final cs = c.scheme;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                '切换布局',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            for (final p in usable)
              ListTile(
                leading: Icon(_iconOf(p.kind)),
                title: Text(p.name),
                // 固定死的默认布局不做编排——标出来，免得用户去找编辑入口。
                subtitle: p.editable
                    ? null
                    : Text(
                        '固定布局',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                trailing: p.id == activeId
                    ? Icon(Icons.check, color: cs.primary)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onPick(p.id);
                },
              ),
          ],
        ),
      );
    },
  );
}

/// 布局形态图标：写字页 = 键盘，画布 = 面板。
IconData _iconOf(RtLayoutKind kind) =>
    kind == RtLayoutKind.writer
    ? Icons.keyboard_alt_outlined
    : Icons.dashboard_customize_outlined;
