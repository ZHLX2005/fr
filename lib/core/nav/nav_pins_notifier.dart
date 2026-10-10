// 快捷导航钉选状态：容量（含 ⋯）+ 有序 pin id 列表。
//
// 首页 = pins[0]。可见底栏 = pins.take(capacity - 1)，其余进 ⋯。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nav_catalog.dart';

const _kCapacityKey = 'nav_bar_capacity';
const _kPinsKey = 'nav_pin_ids';

/// 出厂默认：AI pi · Time · 实验室浏览壳（若无游戏则仍可用）。
const kDefaultNavPins = <String>[
  'ai-pi',
  'core-time',
  'core-lab',
];

List<String> sanitizePinIds(List<String> raw) {
  final known = buildNavCatalog().map((e) => e.id).toSet();
  final seen = <String>{};
  final out = <String>[];
  for (final id in raw) {
    if (!known.contains(id)) continue;
    if (!seen.add(id)) continue;
    out.add(id);
  }
  return out.isEmpty ? List<String>.from(kDefaultNavPins) : out;
}

class NavPinsState {
  const NavPinsState({
    required this.capacity,
    required this.pinIds,
  });

  /// 底栏总格数，含末位 ⋯，仅允许 3 或 4。
  final int capacity;

  /// 有序钉选 id（含溢出）。
  final List<String> pinIds;

  int get visibleSlotCount => capacity - 1;

  List<String> get visibleIds =>
      pinIds.take(visibleSlotCount).toList(growable: false);

  List<String> get overflowIds =>
      pinIds.skip(visibleSlotCount).toList(growable: false);

  String get homeId => pinIds.isEmpty ? kDefaultNavPins.first : pinIds.first;

  NavPinsState copyWith({int? capacity, List<String>? pinIds}) {
    return NavPinsState(
      capacity: capacity ?? this.capacity,
      pinIds: pinIds ?? this.pinIds,
    );
  }
}

class NavPinsNotifier extends Notifier<NavPinsState> {
  @override
  NavPinsState build() {
    return const NavPinsState(capacity: 4, pinIds: kDefaultNavPins);
  }

  /// main() runApp 前调用一次。
  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final cap = prefs.getInt(_kCapacityKey);
    final pins = prefs.getStringList(_kPinsKey);
    final cleaned = sanitizePinIds(
      (pins == null || pins.isEmpty) ? kDefaultNavPins : pins,
    );
    state = NavPinsState(
      capacity: (cap == 3 || cap == 4) ? cap! : 4,
      pinIds: cleaned,
    );
    // 若消毒改写了列表，落盘一次
    if (pins == null ||
        pins.length != cleaned.length ||
        !_listEq(pins, cleaned)) {
      await prefs.setStringList(_kPinsKey, cleaned);
    }
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> setCapacity(int capacity) async {
    if (capacity != 3 && capacity != 4) return;
    if (state.capacity == capacity) return;
    state = state.copyWith(capacity: capacity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCapacityKey, capacity);
  }

  Future<void> setPins(List<String> pinIds) async {
    final next = sanitizePinIds(pinIds);
    state = state.copyWith(pinIds: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPinsKey, next);
  }

  Future<void> togglePin(String id) async {
    final cur = [...state.pinIds];
    if (cur.contains(id)) {
      if (cur.length <= 1) return;
      cur.remove(id);
    } else {
      cur.add(id);
    }
    await setPins(cur);
  }

  Future<void> reorderPins(int oldIndex, int newIndex) async {
    final cur = [...state.pinIds];
    if (oldIndex < 0 || oldIndex >= cur.length) return;
    if (newIndex < 0 || newIndex > cur.length) return;
    var to = newIndex;
    if (to > oldIndex) to -= 1;
    final item = cur.removeAt(oldIndex);
    cur.insert(to, item);
    await setPins(cur);
  }

  bool isPinned(String id) => state.pinIds.contains(id);
}

final navPinsProvider =
    NotifierProvider<NavPinsNotifier, NavPinsState>(NavPinsNotifier.new);
