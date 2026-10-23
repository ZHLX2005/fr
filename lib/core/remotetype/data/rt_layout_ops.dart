// lib/core/remotetype/data/rt_layout_ops.dart
//
// 布局集的变更操作（纯函数）：页面与设置页共用同一套规则，避免
// 「两处各写一遍、改一处漏一处」。
//
// 规则要点：
//   · 内置布局不可删、不可改名（可改摆放、可恢复出厂）；
//   · 删掉的恰是某朝向的激活布局 → 该朝向回退（横屏回触控屏，竖屏显式
//     回写字——写死 id，不依赖列表顺序）；
//   · 删空集合 → 回内置全集（画布不能啥都不渲染）。

import '../canvas/template/rt_canvas_presets.dart';
import 'rt_prefs.dart';

/// 复制一份为新的空自定义布局（[orientation] 由用户选；不自动激活）。
RtCanvasLayouts rtLayoutsCopyToCustom(
  RtCanvasLayouts layouts,
  String orientation,
) {
  final newId = layouts.nextCustomId();
  final displayIndex = newId.startsWith('custom-')
      ? int.tryParse(newId.substring('custom-'.length)) ?? 1
      : 1;
  final entry = RtCanvasNamedLayout(
    id: newId,
    name: '自定义 $displayIndex',
    builtIn: false,
    orientation: orientation,
    data: const RtCanvasLayout(),
  );
  return layouts.withList([...layouts.list, entry]);
}

/// 删除一条自定义布局（内置不动）。删空集合 → 回内置全集。
RtCanvasLayouts rtLayoutsDeleteCustom(RtCanvasLayouts layouts, String id) {
  final target = layouts.list.firstWhere(
    (p) => p.id == id,
    orElse: () => const RtCanvasNamedLayout(
      id: '',
      name: '',
      builtIn: true,
      data: RtCanvasLayout(),
    ),
  );
  if (target.id.isEmpty || target.builtIn) return layouts;
  final filtered = layouts.list.where((p) => p.id != id).toList();
  final nextList = filtered.isEmpty
      ? List<RtCanvasNamedLayout>.from(kRtCanvasBuiltinPresets)
      : filtered;
  final wasActiveL = layouts.activeId == id;
  final wasActiveN = layouts.activeIdPortrait == id;
  return RtCanvasLayouts(
    list: nextList,
    activeId: wasActiveL
        ? (nextList.any((p) => p.id == kRtCanvasPresetTouchpad)
              ? kRtCanvasPresetTouchpad
              : (nextList.isNotEmpty ? nextList.first.id : ''))
        : (nextList.any((p) => p.id == layouts.activeId)
              ? layouts.activeId
              : kRtCanvasPresetTouchpad),
    activeIdPortrait: wasActiveN
        ? kRtCanvasPresetWriter
        : layouts.activeIdPortrait,
  );
}

/// 重命名自定义布局（内置名固定不改；id 不存在时原样返回）。
RtCanvasLayouts rtLayoutsRename(
  RtCanvasLayouts layouts,
  String id,
  String name,
) {
  final target = layouts.list.firstWhere(
    (p) => p.id == id,
    orElse: () => const RtCanvasNamedLayout(
      id: '',
      name: '',
      builtIn: true,
      data: RtCanvasLayout(),
    ),
  );
  if (target.id.isEmpty || target.builtIn) return layouts;
  return layouts.withRenamed(id, name);
}

/// 内置布局恢复出厂摆放（数据重置为代码预设；固定死的内置没有出厂摆
/// 动可言——写字页是 kind=writer，不参与画布摆放）。
RtCanvasLayouts rtLayoutsResetBuiltin(RtCanvasLayouts layouts, String id) {
  final factory = rtBuiltinPresetOf(id);
  if (factory == null) return layouts;
  return RtCanvasLayouts(
    list: [
      for (final p in layouts.list) p.id == id ? p.copyWith(data: factory.data) : p,
    ],
    activeId: layouts.activeId,
    activeIdPortrait: layouts.activeIdPortrait,
  );
}

/// 组内拖拽排序：只重排 [orientation] 可用条目的相对顺序，另一朝向专属
/// 条目相对位置不变。索引语义同 [ReorderableListView.onReorder]
/// （newIndex 在移除前口径，函数内自行校正）。
RtCanvasLayouts rtLayoutsReorder(
  RtCanvasLayouts layouts,
  String orientation,
  int oldIndex,
  int newIndex,
) {
  final group = [
    for (final p in layouts.list)
      if (rtCanvasLayoutUsableIn(orientation, p)) p,
  ];
  if (oldIndex < 0 || oldIndex >= group.length) return layouts;
  var insertAt = newIndex;
  if (insertAt > oldIndex) insertAt -= 1;
  if (insertAt < 0 || insertAt >= group.length) return layouts;
  if (oldIndex == insertAt) return layouts;

  final moved = group.removeAt(oldIndex);
  group.insert(insertAt, moved);
  final queue = List<RtCanvasNamedLayout>.of(group);
  final next = <RtCanvasNamedLayout>[];
  for (final p in layouts.list) {
    if (rtCanvasLayoutUsableIn(orientation, p)) {
      next.add(queue.removeAt(0));
    } else {
      next.add(p);
    }
  }
  return layouts.withList(next);
}
