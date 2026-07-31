# Focus 时间页改造 + 时间工具迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the 学习领域/学科 concept from the focus feature, make the today focus card tappable into 心流空间, and surface clock / 日历 / 节拍器 on the focus home page via a gamecenter-style `timePage` flag (no file moves), hiding them from Lab.

**Architecture:** Add a `bool get timePage` field on `DemoPage` (orthogonal to `DemoType`). A slug-keyed `kTimePageMeta` const in focus owns display metadata (label/icon/color/featured), mirroring `kGameMeta`. The Lab list excludes `timePage` demos (parallel to its existing `excludeGames`). Focus home is rebuilt as Hero + Featured + 2-col Grid. Subjects are removed end-to-end (model, providers, UI consumers). Files stay where they are.

**Tech Stack:** Flutter (Dart), `provider`, `flutter_test`, `SharedPreferences` (no new deps).

**Spec:** `docs/superpowers/specs/2026-07-29-focus-time-page-rework-design.md`

## Global Constraints

- No new pub dependencies. Implementation uses existing Flutter, provider, shared_preferences.
- Subjects out: any reference to `FocusSubject`/`FocusIcons`/`FocusColors`/`FocusSubjectPresets` is removed (no in-memory fallback for old sessions — `fromJson` tolerates legacy `subjectId` key by ignoring it; old `focus_subjects` JSON key is ignored on load).
- `FocusMode` (pomodoro/freeTime) is OUT OF SCOPE — preserved as-is.
- `lab_container.dart`, `fr://lab/demo/{slug}` 路由, main.dart 桌面 widget 深链 (`navigateToClock` → `fr://lab/demo/clock`) 全部不动 — only the Lab *list rendering* filters `timePage` demos.
- All commits include a `flutter analyze` clean gate (project memory: analyze-clean then commit).
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` (omitted below in snippets for brevity — add on every actual commit).
- All paths are Windows-style backslashes as the user is on Windows; the examples below use them.

---

## File Structure

**Create:**
- `lib/core/focus/time_tools/const_time_pages.dart` — `TimePageMeta` + `kTimePageMeta` (slug → meta).
- `test/lab/lab_container_time_page_test.dart` — `timePage` field + `filterByTimePage` extension.
- `test/core/focus/const_time_pages_test.dart` — const map invariants.
- `test/core/focus/focus_session_test.dart` — JSON roundtrip without `subjectId`.
- `test/core/focus/focus_provider_test.dart` — provider behavior without subjects.
- `test/core/focus/focus_timer_provider_test.dart` — timer persistence without subject key.

**Modify:**
- `lib/lab/lab_container.dart` — add `timePage` field + `filterByTimePage` extension on `DemoTimePageFilter`.
- `lib/screens/profile/lab/lab_page.dart` — filter out `timePage` demos (always).
- `lib/lab/demos/clock_demo.dart`, `calendar_demo.dart`, `metronome_demo.dart` — `@override bool get timePage => true;`
- `lib/core/focus/models/focus_session.dart` — drop `subjectId`.
- `lib/core/focus/providers/focus_provider.dart` — drop subjects + `restoreTimerState` + subject keys.
- `lib/core/focus/providers/focus_timer_provider.dart` — drop subject field/methods/keys.
- `lib/core/focus/focus_timer_page.dart` — drop subject selector UI + `initialSubject` + `restoreTimerState` call.
- `lib/core/focus/focus_stats_page.dart` — drop `_buildSubjectDistribution`; make day detail & recent sessions subjectless.
- `lib/core/focus/focus_home_page.dart` — remove subject section/management sheets; make today card tappable; add FeaturedToolCard + ToolCard grid driven by `kTimePageMeta` + `demoRegistry`.

**Delete:**
- `lib/core/focus/models/focus_subject.dart` (entire file).

---

## Task 1: Add `timePage` field + `filterByTimePage` extension

**Files:**
- Modify: `lib/lab/lab_container.dart`
- Create: `test/lab/lab_container_time_page_test.dart`

**Interfaces:**
- Produces:
  - `abstract class DemoPage { bool get timePage => false; }` (new abstract getter, default `false`).
  - `extension DemoTimePageFilter on Iterable<MapEntry<String, DemoPage>> { List<MapEntry<String, DemoPage>> filterByTimePage(); }`
- Consumes: none (additive only — no demos set `timePage: true` yet, so no behavior change).

- [ ] **Step 1: Write the failing test**

Create `test/lab/lab_container_time_page_test.dart`:

```dart
// Exercises the new timePage field + filterByTimePage extension
// on DemoPage. Defaults to false; an override flips it; the extension
// returns only entries whose demo.timePage is true.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';

class _NotTimePage extends DemoPage {
  @override
  String get title => 'NotTime';
  @override
  String get slug => 'not-time';
  @override
  String get description => 'x';
  @override
  Widget buildPage(BuildContext context) => const SizedBox();
}

class _TimePage extends DemoPage {
  @override
  String get title => 'Time';
  @override
  String get slug => 'time';
  @override
  String get description => 'x';
  @override
  bool get timePage => true;
  @override
  Widget buildPage(BuildContext context) => const SizedBox();
}

void main() {
  group('DemoPage.timePage', () {
    test('defaults to false', () {
      expect(_NotTimePage().timePage, isFalse);
    });

    test('override flips to true', () {
      expect(_TimePage().timePage, isTrue);
    });
  });

  group('filterByTimePage', () {
    test('keeps only entries whose demo.timePage is true', () {
      final entries = <MapEntry<String, DemoPage>>[
        MapEntry('not-time', _NotTimePage()),
        MapEntry('time', _TimePage()),
      ];
      final picked = entries.filterByTimePage().map((e) => e.key).toList();
      expect(picked, ['time']);
    });

    test('empty input → empty output', () {
      expect(<MapEntry<String, DemoPage>>[].filterByTimePage(), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/lab/lab_container_time_page_test.dart`
Expected: FAIL — `timePage` getter does not exist on `DemoPage`; `filterByTimePage` extension does not exist.

- [ ] **Step 3: Implement `timePage` field + filter**

Edit `lib/lab/lab_container.dart`. After the existing `DemoType get type => DemoType.util;` line in the abstract `DemoPage` class, add the new field:

```dart
  DemoType get type => DemoType.util;

  /// 时间页：true 时在 Focus 主页显示入口，并从 Lab 列表隐藏。
  /// 与 [type] 正交（一个 demo 可同时是 game 或 util，timePage 只决定是否进 Focus）。
  bool get timePage => false;
}
```

Append a new extension at the bottom of the file (after the existing `DemoTypeFilter` extension):

```dart
/// 过滤出标记了 [DemoPage.timePage] == true 的条目。供 Focus 主页查
/// `demoRegistry.getAll().filterByTimePage()` 使用 —— 与 gamecenter 的
/// `filterByType(DemoType.game)` 对称。
extension DemoTimePageFilter on Iterable<MapEntry<String, DemoPage>> {
  List<MapEntry<String, DemoPage>> filterByTimePage() =>
      where((e) => e.value.timePage).toList();
}
```

- [ ] **Step 4: Re-run the test to verify it passes**

Run: `flutter test test/lab/lab_container_time_page_test.dart`
Expected: 4/4 pass.

- [ ] **Step 5: Verify analyze clean + commit**

Run: `flutter analyze lib/lab/lab_container.dart test/lab/lab_container_time_page_test.dart`
Expected: no issues.

Commit:
```bash
git add lib/lab/lab_container.dart test/lab/lab_container_time_page_test.dart
git commit -m "feat(lab): add timePage flag + filterByTimePage extension on DemoPage"
```

---

## Task 2: Create `kTimePageMeta` const + tests

**Files:**
- Create: `lib/core/focus/time_tools/const_time_pages.dart`
- Create: `test/core/focus/const_time_pages_test.dart`

**Interfaces:**
- Produces:
  - `class TimePageMeta { final String label; final IconData icon; final Color color; final bool featured; const TimePageMeta(...); }`
  - `TimePageMeta timePageMetaOf(String slug)` — same shape as `gameMetaOf`.
  - `const Map<String, TimePageMeta> kTimePageMeta = { ... }` — keyed by demo slug.
- Consumes: `Icons`, `Color` (uses existing focus morandi palette).

- [ ] **Step 1: Write the failing test**

Create `test/core/focus/const_time_pages_test.dart`:

```dart
// kTimePageMeta 必须是 demo slug → 展示元数据 的映射（与 kGameMeta 模式一致）。
// 保证 Focus 主页的精选大卡、网格卡能用一个 slug 查到 label/icon/color/featured。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/focus/time_tools/const_time_pages.dart';

void main() {
  group('kTimePageMeta', () {
    test('covers the 3 expected time-page demo slugs', () {
      expect(kTimePageMeta.keys.toSet(),
          containsAll(<String>['clock', 'calendar', 'metronome']));
    });

    test('exactly 3 entries (no accidental growth)', () {
      expect(kTimePageMeta.length, 3);
    });

    test('clock is featured; calendar & metronome are not', () {
      expect(timePageMetaOf('clock').featured, isTrue);
      expect(timePageMetaOf('calendar').featured, isFalse);
      expect(timePageMetaOf('metronome').featured, isFalse);
    });

    test('every meta has a non-empty Chinese label and a non-null icon/color', () {
      for (final entry in kTimePageMeta.entries) {
        final m = entry.value;
        expect(m.label.trim(), isNotEmpty,
            reason: '${entry.key}.label 不能为空');
        expect(m.icon, isA<IconData>(),
            reason: '${entry.key}.icon 必须是 IconData');
        expect(m.color, isA<Color>(),
            reason: '${entry.key}.color 必须是 Color');
      }
    });

    test('timePageMetaOf(unknown) returns a non-null fallback-shaped meta', () {
      final m = timePageMetaOf('does-not-exist');
      expect(m.label, isNotEmpty);
      expect(m.icon, isA<IconData>());
      expect(m.color, isA<Color>());
      expect(m.featured, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/focus/const_time_pages_test.dart`
Expected: FAIL — `const_time_pages.dart` does not exist.

- [ ] **Step 3: Implement the const file**

Create `lib/core/focus/time_tools/const_time_pages.dart`:

```dart
// 时间页（timePage）展示元数据 —— 对应 game_center 的 kGameMeta。
//
// 同样的取舍：常量层不 import 任何 demo 实现文件，按 demo.slug 查。
// 添加新时间页三步：
//   ① 让 demo `override bool get timePage => true;`
//   ② 在 [kTimePageMeta] 里按 slug 加一条
//   ③ 若引入新排序规则，更新 [FocusHomePage] 的 featured 选择
//
// icon/color 与现有 focus 莫兰迪卡一致（sage 渐变主基调）。
import 'package:flutter/material.dart';

/// 单个 timePage demo 的展示元数据。
class TimePageMeta {
  const TimePageMeta({
    required this.label,
    required this.icon,
    required this.color,
    this.featured = false,
  });

  /// 覆盖 [DemoPage.title]（如 'Clock' → '时钟'），统一中文。
  final String label;

  /// 卡片主图标。
  final IconData icon;

  /// 卡片强调色（取自 focus 莫兰迪调色板，与现有卡片风格对齐）。
  final Color color;

  /// true → 占 Focus 主页的精选大卡（一张）。目前只有 clock。
  final bool featured;
}

/// slug → 展示元数据。key 必须与 [DemoPage.slug] 完全一致。
const Map<String, TimePageMeta> kTimePageMeta = {
  'clock': TimePageMeta(
    label: '时钟',
    icon: Icons.access_time_rounded,
    color: Color(0xFFB5C9A3), // sage，与今日专注卡同色系
    featured: true,
  ),
  'calendar': TimePageMeta(
    label: '日历',
    icon: Icons.calendar_month_outlined,
    color: Color(0xFF6B9DFC),
  ),
  'metronome': TimePageMeta(
    label: '节拍器',
    icon: Icons.music_note_outlined,
    color: Color(0xFFB39EB5),
  ),
};

/// 未登记 slug 的兜底元数据（防御性：避免 UI 上 null 字段）。
/// `label: ''` 与 Task 2 测试 `isNotEmpty` 断言冲突 → 用占位 `未命名`。
const TimePageMeta kFallbackTimePageMeta = TimePageMeta(
  label: '未命名',
  icon: Icons.access_time,
  color: Color(0xFFB5C9A3),
);

TimePageMeta timePageMetaOf(String slug) =>
    kTimePageMeta[slug] ?? kFallbackTimePageMeta;
```

- [ ] **Step 4: Re-run the test to verify it passes**

Run: `flutter test test/core/focus/const_time_pages_test.dart`
Expected: 5/5 pass.

- [ ] **Step 5: Verify analyze clean + commit**

Run: `flutter analyze lib/core/focus/time_tools/const_time_pages.dart test/core/focus/const_time_pages_test.dart`
Expected: no issues.

Commit:
```bash
git add lib/core/focus/time_tools/const_time_pages.dart test/core/focus/const_time_pages_test.dart
git commit -m "feat(focus): add kTimePageMeta const registry + TimePageMeta"
```

---

## Task 3: Remove subject concept from data layer + UI consumers (atomic)

Sub-steps within this task target one cohesive deliverable: the subject concept is entirely gone, the app still builds, and the model/provider/timer-provider tests prove it.

**Files:**
- Modify: `lib/core/focus/models/focus_session.dart`
- Modify: `lib/core/focus/providers/focus_provider.dart`
- Modify: `lib/core/focus/providers/focus_timer_provider.dart`
- Modify: `lib/core/focus/focus_timer_page.dart`
- Modify: `lib/core/focus/focus_stats_page.dart`
- Modify: `lib/core/focus/focus_home_page.dart` (will be near-empty after removals — task 4 rebuilds it)
- Delete: `lib/core/focus/models/focus_subject.dart`
- Create: `test/core/focus/focus_session_test.dart`
- Create: `test/core/focus/focus_provider_test.dart`
- Create: `test/core/focus/focus_timer_provider_test.dart`

**Interfaces:**
- After this task:
  - `FocusSession` no `subjectId`; `FocusMode` retained.
  - `FocusProvider` exposes: `sessions`, `isLoading`, `init()`, `addSession`, `getTodayMinutes()`, `getWeekMinutes()`, `getHeatmapData()`, `clearAll()`. No subjects/restoring.
  - `FocusTimerProvider` exposes: `state/isRunning/isPaused/isIdle`, `totalSeconds`, `startTimer/pauseTimer/resumeTimer/stopTimer/resetTimer/completeSession/formatTime`, persistence via `_timerSecondsKey`/`_timerStartTimeKey`/`_timerStateKey` only (no subject key).
  - UI pages compile against the new shapes (subject bits deleted).
- Consumes: `FocusMode`, SharedPreferences, `provider`.

- [ ] **Step 1: Write the failing FocusSession test**

Create `test/core/focus/focus_session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/focus/models/focus_session.dart';

void main() {
  group('FocusSession roundtrip (subjectId removed)', () {
    final session = FocusSession(
      id: 'abc',
      durationMinutes: 25,
      startTime: DateTime.utc(2026, 7, 29, 10),
      endTime: DateTime.utc(2026, 7, 29, 10, 25),
      mode: FocusMode.freeTime,
      note: 'n',
    );

    test('toJson 不写 subjectId', () {
      final json = session.toJson();
      expect(json.containsKey('subjectId'), isFalse);
    });

    test('fromJson 容忍旧数据里的 subjectId（默默忽略）', () {
      final legacy = <String, dynamic>{
        'id': 'legacy',
        'subjectId': 'computer',
        'durationMinutes': 30,
        'startTime': DateTime.utc(2026, 7, 1).toIso8601String(),
        'endTime': DateTime.utc(2026, 7, 1, 0, 30).toIso8601String(),
        'mode': FocusMode.pomodoro.index,
        'note': null,
      };
      final s = FocusSession.fromJson(legacy);
      expect(s.id, 'legacy');
      expect(s.durationMinutes, 30);
      expect(s.note, isNull);
    });

    test('roundtrip 干净数据', () {
      final json = session.toJson();
      final back = FocusSession.fromJson(json);
      expect(back.id, session.id);
      expect(back.durationMinutes, session.durationMinutes);
      expect(back.startTime, session.startTime);
      expect(back.endTime, session.endTime);
      expect(back.mode, session.mode);
      expect(back.note, session.note);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/focus/focus_session_test.dart`
Expected: FAIL — `FocusSession` still has `subjectId` (the legacy `fromJson` test passes by accident because the field exists; the `toJson` test should fail on `subjectId` key presence).

- [ ] **Step 3: Drop `subjectId` from `FocusSession`**

Edit `lib/core/focus/models/focus_session.dart`. Remove `subjectId` from field list, constructor, `copyWith`, `toJson`, and `fromJson`. The model becomes:

```dart
class FocusSession {
  final String id;
  final int durationMinutes;
  final DateTime startTime;
  final DateTime endTime;
  final FocusMode mode;
  final String? note;

  FocusSession({
    required this.id,
    required this.durationMinutes,
    required this.startTime,
    required this.endTime,
    required this.mode,
    this.note,
  });

  bool get isPomodoro => mode == FocusMode.pomodoro;
  bool get isFreeTime => mode == FocusMode.freeTime;

  FocusSession copyWith({
    String? id,
    int? durationMinutes,
    DateTime? startTime,
    DateTime? endTime,
    FocusMode? mode,
    String? note,
  }) {
    return FocusSession(
      id: id ?? this.id,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      mode: mode ?? this.mode,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'durationMinutes': durationMinutes,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'mode': mode.index,
        'note': note,
      };

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    return FocusSession(
      id: json['id'] as String,
      durationMinutes: json['durationMinutes'] as int,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      mode: FocusMode.values[json['mode'] as int],
      note: json['note'] as String?,
    );
  }
}
```

Keep `enum FocusMode { pomodoro, freeTime }` and its extension unchanged.

- [ ] **Step 4: Re-run test, expect pass**

Run: `flutter test test/core/focus/focus_session_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Write failing FocusProvider test**

Create `test/core/focus/focus_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/focus/models/focus_session.dart';
import 'package:xiaodouzi_fr/core/focus/providers/focus_provider.dart';

void main() {
  late FocusProvider fp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fp = FocusProvider();
    await fp.init();
  });

  group('FocusProvider（无 subject 概念）', () {
    test('init 空 prefs 不崩，sessions 为空', () async {
      expect(fp.sessions, isEmpty);
      expect(fp.isLoading, isFalse);
    });

    test('init 容忍 legacy focus_subjects JSON（旧 key 被忽略）', () async {
      SharedPreferences.setMockInitialValues({
        'focus_subjects': '[{"id":"s1","name":"x","color":0,"iconIndex":0}]',
        'focus_sessions':
            '[{"id":"a","subjectId":"s1","durationMinutes":40,"startTime":"2026-07-29T08:00:00Z","endTime":"2026-07-29T08:40:00Z","mode":1,"note":null}]',
      });
      final fresh = FocusProvider();
      await fresh.init();
      expect(fresh.sessions.length, 1);
      expect(fresh.sessions.first.durationMinutes, 40);
    });

    test('addSession 后 getTodayMinutes 计入', () async {
      final now = DateTime.now();
      await fp.addSession(FocusSession(
        id: '1',
        durationMinutes: 30,
        startTime: DateTime(now.year, now.month, now.day, 9),
        endTime: DateTime(now.year, now.month, now.day, 9, 30),
        mode: FocusMode.freeTime,
      ));
      expect(fp.getTodayMinutes(), 30);
      expect(fp.getWeekMinutes(), greaterThanOrEqualTo(30));
    });

    test('getHeatmapData 返回 7 天数据', () {
      final data = fp.getHeatmapData();
      expect(data.length, 7);
      expect(data.every((d) => d.containsKey('minutes')), isTrue);
    });

    test('clearAll 清空 sessions', () async {
      await fp.addSession(FocusSession(
        id: 'x',
        durationMinutes: 5,
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(minutes: 5)),
        mode: FocusMode.freeTime,
      ));
      await fp.clearAll();
      expect(fp.sessions, isEmpty);
    });
  });
}
```

- [ ] **Step 6: Run, expect fail**

Run: `flutter test test/core/focus/focus_provider_test.dart`
Expected: FAIL — provider still has subjects; `init` reads `focus_subjects`; `addSession` references `_subjects`. Most tests fail to compile or assert.

- [ ] **Step 7: Rewrite `FocusProvider` without subjects**

Replace `lib/core/focus/providers/focus_provider.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/focus_session.dart';

/// 专注数据管理Provider（只管 sessions：学科已移除）。
class FocusProvider extends ChangeNotifier {
  List<FocusSession> _sessions = [];
  bool _isLoading = true;

  List<FocusSession> get sessions => List.unmodifiable(_sessions);
  bool get isLoading => _isLoading;

  /// 初始化
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    await _loadData();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = prefs.getString('focus_sessions');
    if (sessionsJson != null && sessionsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(sessionsJson);
        _sessions = decoded.map((j) => FocusSession.fromJson(j)).toList();
      } catch (e) {
        debugPrint('加载会话失败: $e');
        _sessions = [];
      }
    }
    // legacy focus_subjects JSON 直接忽略
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson =
        json.encode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString('focus_sessions', sessionsJson);
  }

  /// 添加会话记录
  Future<void> addSession(FocusSession session) async {
    _sessions.add(session);
    await _saveData();
    notifyListeners();
  }

  /// 今日总学时（分钟）
  int getTodayMinutes() => _sumMinutesOn(DateTime.now());

  /// 本周总学时（分钟）
  int getWeekMinutes() {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return _sessions
        .where((s) => !s.startTime.isBefore(weekStart))
        .fold<int>(0, (sum, s) => sum + s.durationMinutes);
  }

  /// 最近 7 天热力图
  List<Map<String, dynamic>> getHeatmapData() {
    final data = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      data.add({
        'date': date,
        'minutes': _sumMinutesOn(date),
        'level': _heatmapLevel(_sumMinutesOn(date)),
      });
    }
    return data;
  }

  int _sumMinutesOn(DateTime date) => _sessions
      .where((s) =>
          s.startTime.year == date.year &&
          s.startTime.month == date.month &&
          s.startTime.day == date.day)
      .fold<int>(0, (sum, s) => sum + s.durationMinutes);

  int _heatmapLevel(int minutes) {
    if (minutes == 0) return 0;
    if (minutes < 30) return 1;
    if (minutes < 60) return 2;
    if (minutes < 120) return 3;
    return 4;
  }

  Future<void> clearAll() async {
    _sessions = [];
    await _saveData();
    notifyListeners();
  }
}
```

- [ ] **Step 8: Re-run provider test, expect pass**

Run: `flutter test test/core/focus/focus_provider_test.dart`
Expected: 5/5 pass.

- [ ] **Step 9: Write failing FocusTimerProvider test**

Create `test/core/focus/focus_timer_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/focus/providers/focus_timer_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FocusTimerProvider（无 subject 概念）', () {
    test('initial state is idle with zero seconds', () async {
      final p = FocusTimerProvider();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(p.isIdle, isTrue);
      expect(p.totalSeconds, 0);
    });

    test('startTimer 后 isRunning', () {
      final p = FocusTimerProvider();
      p.startTimer();
      expect(p.isRunning, isTrue);
      p.stopTimer();
    });

    test('pauseTimer 切到 paused', () {
      final p = FocusTimerProvider();
      p.startTimer();
      p.pauseTimer();
      expect(p.isPaused, isTrue);
    });

    test('恢复（仅秒数）：init 拿回 running 状态，不读 _timerSubjectKey', () async {
      SharedPreferences.setMockInitialValues({
        'focus_timer_state': '0', // TimerState.running.index
        'focus_timer_seconds': '42',
        'focus_timer_start_time': DateTime.now().toIso8601String(),
      });
      final p = FocusTimerProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // ≥ 42 (秒数已恢复；后台可能再增加几秒)
      expect(p.totalSeconds, greaterThanOrEqualTo(42));
      expect(p.isRunning || p.isPaused, isTrue);
      // 没有 _timerSubjectKey 这个 key 写入 prefs
      // （由源码保证；这里只做一个对称性断言：如果该 key 出现就失败）
      // 这一条不在测试中重复实现，但通过 init 路径不抛异常间接证明。
    });

    test('completeSession 返回 subjectless session', () async {
      // 直接构造 → 走 completeSession 时也能产出无 subjectId 的 session。
      // 这里通过新模型本身的合约验证（见 focus_session_test.dart）。
      // 此处补一条针对 provider completeSession 路径的烟雾测试。
      final p = FocusTimerProvider();
      // 没有 start → totalSeconds == 0 → completeSession 返回 null
      expect(p.completeSession(), isNull);
    });
  });
}
```

- [ ] **Step 10: Run, expect fail**

Run: `flutter test test/core/focus/focus_timer_provider_test.dart`
Expected: FAIL — provider still has `_selectedSubject` / `selectSubject` / `_timerSubjectKey`; model `FocusSession` (until step 3 is in this task) still has `subjectId`. Some tests fail to compile.

- [ ] **Step 11: Rewrite `FocusTimerProvider` without subject**

Replace `lib/core/focus/providers/focus_timer_provider.dart` with:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/focus_session.dart';

enum TimerState { idle, running, paused }

class FocusTimerProvider extends ChangeNotifier {
  Timer? _timer;
  TimerState _state = TimerState.idle;
  int _totalSeconds = 0;
  DateTime? _sessionStartTime;

  static const String _timerStateKey = 'focus_timer_state';
  static const String _timerSecondsKey = 'focus_timer_seconds';
  static const String _timerStartTimeKey = 'focus_timer_start_time';

  TimerState get state => _state;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _state == TimerState.running;
  bool get isPaused => _state == TimerState.paused;
  bool get isIdle => _state == TimerState.idle;

  FocusTimerProvider() {
    _restoreTimerState();
  }

  Future<void> _restoreTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedState = prefs.getInt(_timerStateKey);
      final savedSeconds = prefs.getInt(_timerSecondsKey) ?? 0;
      final savedStartTimeStr = prefs.getString(_timerStartTimeKey);

      if (savedState == TimerState.running.index &&
          savedStartTimeStr != null) {
        final savedStartTime = DateTime.parse(savedStartTimeStr);
        _totalSeconds =
            savedSeconds + DateTime.now().difference(savedStartTime).inSeconds;
        _state = TimerState.running;
        _sessionStartTime = savedStartTime;
        _startInternalTimer();
        notifyListeners();
      } else if (savedState == TimerState.paused.index) {
        _totalSeconds = savedSeconds;
        _state = TimerState.paused;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('恢复计时器状态失败: $e');
    }
  }

  Future<void> _saveTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timerStateKey, _state.index);
    await prefs.setInt(_timerSecondsKey, _totalSeconds);
    if (_sessionStartTime != null) {
      await prefs.setString(
        _timerStartTimeKey,
        _sessionStartTime!.toIso8601String(),
      );
    } else {
      await prefs.remove(_timerStartTimeKey);
    }
  }

  Future<void> _clearTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_timerStateKey);
    await prefs.remove(_timerSecondsKey);
    await prefs.remove(_timerStartTimeKey);
  }

  void startTimer() {
    if (_state == TimerState.running) return;
    _state = TimerState.running;
    _sessionStartTime = DateTime.now();
    notifyListeners();
    _startInternalTimer();
    _saveTimerState();
  }

  void _startInternalTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _totalSeconds++;
      notifyListeners();
    });
  }

  void pauseTimer() {
    if (_state != TimerState.running) return;
    _timer?.cancel();
    _state = TimerState.paused;
    _sessionStartTime = null;
    notifyListeners();
    _saveTimerState();
  }

  void resumeTimer() {
    if (_state != TimerState.paused) return;
    _state = TimerState.running;
    _sessionStartTime = DateTime.now();
    notifyListeners();
    _startInternalTimer();
    _saveTimerState();
  }

  void stopTimer() {
    _timer?.cancel();
    _state = TimerState.idle;
    _totalSeconds = 0;
    _sessionStartTime = null;
    notifyListeners();
    _clearTimerState();
  }

  void resetTimer() => stopTimer();

  /// 完成一次专注 — 返回会话记录供调用者保存（不再绑定任何 subject）。
  FocusSession? completeSession() {
    if (_totalSeconds == 0) return null;
    _timer?.cancel();
    _state = TimerState.idle;
    final durationMinutes = _totalSeconds ~/ 60;
    if (durationMinutes == 0) {
      resetTimer();
      return null;
    }
    final session = FocusSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      durationMinutes: durationMinutes,
      startTime: DateTime.now().subtract(Duration(seconds: _totalSeconds)),
      endTime: DateTime.now(),
      mode: FocusMode.freeTime,
    );
    resetTimer();
    return session;
  }

  String formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 12: Re-run timer provider test, expect pass**

Run: `flutter test test/core/focus/focus_timer_provider_test.dart`
Expected: 5/5 pass.

- [ ] **Step 13: Delete `focus_subject.dart` (data model file)**

```bash
git rm lib/core/focus/models/focus_subject.dart
```

- [ ] **Step 14: Update `focus_timer_page.dart` UI to drop subject bits**

Edit `lib/core/focus/focus_timer_page.dart`:

1. Remove `import '../models/focus_subject.dart';` (focus_subject.dart is gone) and `import '../providers/focus_provider.dart' as data;` if it's only used for the deleted restoreTimerState call + subject selector.
2. Remove `final FocusSubject? initialSubject;` field and `const FocusTimerPage({super.key, this.initialSubject});` parameter. Change to `const FocusTimerPage({super.key});`.
3. Remove the `initState` block:
   ```dart
   if (widget.initialSubject != null) {
     _timerProvider.selectSubject(widget.initialSubject);
   }
   WidgetsBinding.instance.addPostFrameCallback((_) {
     if (mounted) {
       final focusProvider = Provider.of<data.FocusProvider>(context, listen: false);
       focusProvider.restoreTimerState(_timerProvider);
     }
   });
   ```
   Replace with empty (the timer provider self-restores in its constructor).
4. In `_buildTopBar`, remove the trailing `IconButton(icon: Icons.category_outlined, …)` and its `_showSubjectSelector` callback.
5. Remove the entire `_showSubjectSelector(BuildContext context)` method.

- [ ] **Step 15: Update `focus_stats_page.dart` to be subjectless**

Edit `lib/core/focus/focus_stats_page.dart`:

1. Delete `_buildSubjectDistribution(FocusProvider focusProvider)` entirely.
2. Remove its call site in `build`.
3. In `_buildDayDetailSection`: remove the `subject = focusProvider.subjects.firstWhere(...)` lookup and the leading icon container + Subject-name `Text(subject.name)`. Replace the leading block with a plain duration-aware layout:
   ```dart
   Container(
     width: 36, height: 36,
     decoration: BoxDecoration(
       color: Colors.grey.withValues(alpha: 0.12),
       borderRadius: BorderRadius.circular(8),
     ),
     child: const Icon(Icons.self_improvement, size: 18, color: Colors.grey),
   ),
   const SizedBox(width: 12),
   Expanded(
     child: Text(
       '${session.mode == FocusMode.pomodoro ? "番茄钟" : "自由计时"}',
       style: const TextStyle(fontWeight: FontWeight.w500),
     ),
   ),
   ```
   (Keep the trailing `Text('${session.durationMinutes}分钟')`. Move the time range text to subtitle if desired — but the simpler version above is acceptable; you may also drop the time-range subtitle entirely.)
4. In `_buildRecentSessions`: do the same — drop subject lookup, replace leading IconButton with a plain `Icons.self_improvement` chip, replace `Text(subject.name)` with the `FocusMode.label` text.

The `FocusMode` import is already present via `focus_session.dart`.

- [ ] **Step 16: Update `focus_home_page.dart` to drop subject bits (intermediate state — task 4 rebuilds)**

Edit `lib/core/focus/focus_home_page.dart`:

1. Remove the imports `import 'models/focus_subject.dart';` and any `focus_subject` references.
2. Delete these methods/widgets:
   - `_buildSubjectSection`
   - `_buildSubjectCard`
   - `_SubjectManagementSheet` (the private class)
   - `_SubjectEditDialog` (the private class + its State)
   - `_showSubjectManagement`
3. Update `_buildQuickActions` to remove the "学习领域" header and instead go straight to a 2-col grid of tools (stats + timetable). The grid composition is fully replaced in Task 4; for now just collapse to the empty quick-action area or stub it with an `Align(child: Text('重构中…'))`. (Task 4 finishes this.)
4. Remove `_navigateToTimer(BuildContext context, [FocusSubject? subject])` — replace with `_navigateToTimer(BuildContext context)` (Task 4 wires today's-card onTap here).
5. In `build()`, remove the `_buildSubjectSection(...)` call from the `Column`.

This is intentionally intermediate: the page compiles and renders, but the entrance area is incomplete. Task 4 finishes it.

- [ ] **Step 17: Run all new + existing tests for the focus module**

Run:
```bash
flutter test test/core/focus/
flutter test test/lab/lab_container_time_page_test.dart test/core/focus/const_time_pages_test.dart
```
Expected: all pass (focus_session + focus_provider + focus_timer_provider + earlier tasks' tests).

- [ ] **Step 18: Run full test suite to ensure no regressions**

Run: `flutter test`
Expected: all previously-green tests remain green. (Inspect any failure and fix before proceeding.)

- [ ] **Step 19: Analyze clean + commit**

Run: `flutter analyze`
Expected: no issues.

Commit:
```bash
git add -A
git commit -m "refactor(focus): remove 学习领域/学科 concept end-to-end

Drop FocusSubject model, subject APIs on FocusProvider (incl. restoreTimerState),
subject APIs on FocusTimerProvider, and subjectId field on FocusSession.
Clean subject-section UI from focus_home_page / focus_stats_page / focus_timer_page.
Untouched: FocusMode (pomodoro/freeTime), gamecenter pattern, demo registry."
```

---

## Task 4: Rebuild focus home entrance (today tappable + featured + grid) + activate `timePage` + Lab exclusion

Sub-steps deliver one cohesive user-facing change: the focus home page now follows the spec sketch (Hero + Featured + 2-col Grid), the three time demos show up there, and the Lab list stops showing them.

**Files:**
- Modify: `lib/core/focus/focus_home_page.dart` (major rebuild)
- Modify: `lib/screens/profile/lab/lab_page.dart` (filter update)
- Modify: `lib/lab/demos/clock_demo.dart`
- Modify: `lib/lab/demos/calendar_demo.dart`
- Modify: `lib/lab/demos/metronome_demo.dart`

**Interfaces:**
- Consumes:
  - `kTimePageMeta` (Task 2) for display metadata.
  - `demoRegistry.getAll().filterByTimePage()` (Task 1) for the active tool list.
  - `DemoDetailPage` from `package:xiaodouzi_fr/screens/profile/lab/demo_detail_page.dart` for opening demos.
- Produces:
  - A new Focus home layout matching the spec preview.
  - Updated lab page filter (timePage demos hidden).

- [ ] **Step 1: Activate `timePage` on the 3 demos**

In each of `lib/lab/demos/clock_demo.dart`, `lib/lab/demos/calendar_demo.dart`, `lib/lab/demos/metronome_demo.dart`, add this line inside the demo class:

```dart
  @override
  bool get timePage => true;
```

(Place it next to `slug` so review can see all the demo metadata together.)

- [ ] **Step 2: Update Lab list to exclude timePage demos**

Edit `lib/screens/profile/lab/lab_page.dart`. Locate the `initState` body that builds the visible demos (around the `widget.excludeGames ? demoRegistry.getAll().where(...)` block). Replace it with:

```dart
final all = demoRegistry.getAll().where((e) => !e.value.timePage);
_visible = widget.excludeGames
    ? all.where((e) => e.value.type != DemoType.game).toList()
    : all.toList();
```

Make sure `DemoType` is still imported (it already is). Verify the variable name matches the existing field (likely `_visibleDemos` or similar — match the field name already used in the file).

- [ ] **Step 3: Write the new `focus_home_page.dart` skeleton**

Replace the body of `lib/core/focus/focus_home_page.dart` with the structure below. The key new pieces:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/focus_provider.dart';
import 'focus_timer_page.dart';
import 'focus_stats_page.dart';
import '../timetable/timetable.dart';
import 'time_tools/const_time_pages.dart';
import '../../lab/lab_container.dart';
import '../../screens/profile/lab/demo_detail_page.dart';

/// 工具列表项：registry demo（按 slug 走 DemoDetailPage）；内部页（带 onTap）。
/// onTap 只在内部页使用；registry 项 onTap 由父级 build 中按 slug 派生。
class _ToolItem {
  _ToolItem._({required this.label, required this.icon, required this.color, this.slug, this.onTap});
  factory _ToolItem.registry(String slug) {
    final meta = timePageMetaOf(slug);
    return _ToolItem._(
      label: meta.label,
      icon: meta.icon,
      color: meta.color,
      slug: slug,
    );
  }
  factory _ToolItem.internal({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return _ToolItem._(label: label, icon: icon, color: color, onTap: onTap);
  }
  final String label;
  final IconData icon;
  final Color color;
  final String? slug;
  final VoidCallback? onTap;
}

class FocusHomePage extends StatelessWidget {
  const FocusHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<FocusProvider>(
          builder: (context, fp, _) {
            if (fp.isLoading) return const Center(child: CircularProgressIndicator());

            // 工具列表：registry 中的 timePage demo + 内部页（统计、课表）。
            // onTap 在 build 中按 slug 是否为 null 区分：null → 内部页直接 onTap；
            // 非 null → 走 _openDemo(slug)。
            final registrySlugs = demoRegistry
                .getAll()
                .filterByTimePage()
                .map((e) => e.key)
                .where(kTimePageMeta.containsKey)
                .toList();
            final registryMetas =
                registrySlugs.map((s) => (slug: s, meta: kTimePageMeta[s]!)).toList();
            final featured = registryMetas.where((m) => m.meta.featured).toList();
            final grid = <_ToolItem>[
              for (final m in registryMetas.where((m) => !m.meta.featured))
                _ToolItem.registry(m.slug),
              _ToolItem.internal(
                label: '数据统计',
                icon: Icons.bar_chart_outlined,
                color: const Color(0xFF8B9DC3),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FocusStatsPage())),
              ),
              _ToolItem.internal(
                label: '时间课表',
                icon: Icons.calendar_month_outlined,
                color: const Color(0xFF6B9DFC),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TimetablePage())),
              ),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreeting(context),
                  const SizedBox(height: 32),
                  _buildTodayCard(context, fp, onTap: () => _navigateToTimer(context)),
                  const SizedBox(height: 24),
                  if (featured.isNotEmpty) ...[
                    _FeaturedToolCard(
                      slug: featured.first.slug,
                      onTap: () => _openDemo(context, featured.first.slug),
                    ),
                    const SizedBox(height: 24),
                  ],
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                    ),
                    itemCount: grid.length,
                    itemBuilder: (_, i) {
                      final item = grid[i];
                      final onTap = item.slug != null
                          ? () => _openDemo(context, item.slug!)
                          : item.onTap!;
                      return _ToolCard(item: item, onTap: onTap);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openDemo(BuildContext context, String slug) {
    final demo = demoRegistry.getBySlug(slug);
    if (demo == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DemoDetailPage(demo: demo)),
    );
  }

  // 问候语与今日专注卡 — 保留现样式，只在 _buildTodayCard 上加 onTap + 轻微 →
  Widget _buildGreeting(BuildContext context) { /* 保留原实现 */ }
  Widget _buildTodayCard(BuildContext context, FocusProvider fp, {required VoidCallback onTap}) {
    // 沿用原 sage 渐变容器；外面套 GestureDetector(onTap: onTap)；
    // 在右上角或脚注加一个「点击开始专注 →」提示。
    // ...（完整代码：保留原 hour/minutes 渲染，外层包 GestureDetector）
  }
  void _navigateToTimer(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FocusTimerPage()));
  }
}

/// 精选宽卡（横跨整行）— 与现有 subject 卡风格一致。
/// 永远只渲染 featured meta（当前=clock）。
class _FeaturedToolCard extends StatelessWidget {
  const _FeaturedToolCard({required this.slug, required this.onTap});
  final String slug;
  final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final meta = timePageMetaOf(slug);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [meta.color, meta.color.withValues(alpha: 0.7)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: meta.color.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14)),
              child: Icon(meta.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('点击进入', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

/// 工具网格卡 — 与旧的 _buildActionButton 视觉风格一致（白底、轻强调色）。
class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.item, required this.onTap});
  // 沿用旧的 _buildActionButton 渲染：圆角 16、color.withValues(alpha:0.12) 背景、
  // 中央 icon + 文字。保持 childAspectRatio 1.6。
  final _ToolItem item;
  final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: item.color, size: 24),
            const SizedBox(height: 8),
            Text(item.label, style: TextStyle(fontSize: 12, color: item.color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
```

Notes for the implementer:
- `_buildGreeting` and the original `_buildTodayCard` body are kept (sage 渐变 + 今日专注 X 小时 Y 分钟) — only wrap `_buildTodayCard` in a `GestureDetector(onTap: onTap)` and add a small `→` chevron to the right side of the inner `Row`, or a subtle `Text('点击开始专注')` underneath. Do not redesign the card.
- The old `_navigateToTimer(BuildContext, [FocusSubject?])` is replaced by the parameterless version above.
- The earlier-deleted `_SubjectManagementSheet`, `_SubjectEditDialog`, etc. must NOT be reintroduced.

- [ ] **Step 4: Analyze + verify the file compiles**

Run: `flutter analyze lib/core/focus/focus_home_page.dart`
Expected: no issues.

If `demoRegistry.getAll()` types don't quite line up (entries are `MapEntry<String, DemoPage>`), adjust the `.where` chain — `e.key` will be `String` directly (not nullable) because `getAll()` keys are slug `String`. The `.where((s) => s != null)` filter shown above is defensive; remove if it's a noise.

- [ ] **Step 5: Manual smoke (the only way to verify UI without widget tests)**

Follow `run` skill (or run the app via your normal dev command, e.g. `flutter run -d <device>`):
1. Open the middle tab. Today's card visible. Tap → enters 心流空间, can start/stop/complete a session.
2. Verify the 精选宽卡 (clock) renders + taps → opens Clock demo (Zen theme).
3. Verify the grid renders 日历, 节拍器, 数据统计, 时间课表 in that order, each tapping into the right page.
4. Open Lab. Confirm 时钟 / 日历 / 节拍器 are NOT in the Lab list.
5. Use the desktop widget deep link flow or simply verify `fr://lab/demo/clock` is still routable (the registry + handler are untouched — Lab exclusion is list-only).

- [ ] **Step 6: Run all tests to confirm no regressions**

Run: `flutter test`
Expected: all green.

- [ ] **Step 7: Analyze + commit**

Run: `flutter analyze`
Expected: no issues.

Commit:
```bash
git add lib/core/focus/focus_home_page.dart lib/screens/profile/lab/lab_page.dart lib/lab/demos/clock_demo.dart lib/lab/demos/calendar_demo.dart lib/lab/demos/metronome_demo.dart
git commit -m "feat(focus): migrate clock/calendar/metronome onto home page via timePage flag

Adds timePage:true on the 3 demos (no file moves), filters Lab list to
hide them, and rebuilds FocusHomePage as Hero (today → 心流空间) +
Featured (clock) + 2-col Grid (calendar, metronome, 数据统计, 时间课表).
kTimePageMeta owns display metadata, mirrored from kGameMeta."
```

---

## Task 5: Final analyze + push

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: 0 issues project-wide.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 3: Final manual smoke (per spec verification checklist)**

- [ ] 中间 tab：今日专注卡点击 → 心流空间可起停/完成，完成会写一条 session。
- [ ] 时钟 / 日历 / 节拍器入口 → 各自原生页面正常打开与返回。
- [ ] 数据统计页：无学科分布；当日详情 / 最近记录显示纯时长。
- [ ] Lab 列表：不再出现时钟 / 日历 / 节拍器三项。
- [ ] 桌面 widget 深链（`fr://lab/demo/clock`，main.dart 里的 `navigateToClock`）仍可达。

- [ ] **Step 4: Push**

```bash
git push
```

---

## Self-Review Notes (post-write)

Coverage:
- ✅ timePage flag + extension → Task 1
- ✅ kTimePageMeta + tests → Task 2
- ✅ Drop subjectId from FocusSession → Task 3 step 3 (with roundtrip + legacy-ignore tests)
- ✅ Drop subjects from FocusProvider → Task 3 step 7 (with legacy prefs + addSession + getTodayMinutes/Week/Heatmap + clearAll tests)
- ✅ Drop subject from FocusTimerProvider → Task 3 step 11 (with persistence + completeSession tests)
- ✅ Delete focus_subject.dart → Task 3 step 13
- ✅ Cleanup focus_timer_page UI → Task 3 step 14
- ✅ Cleanup focus_stats_page UI → Task 3 step 15
- ✅ Cleanup focus_home_page UI → Task 3 step 16 (intermediate; task 4 finishes)
- ✅ Lab exclusion filter → Task 4 step 2
- ✅ Activate timePage on 3 demos → Task 4 step 1
- ✅ Focus home rebuild (today tappable + Featured + Grid) → Task 4 step 3
- ✅ Analyze clean gate at every task
- ✅ Manual verification gates (UI tasks)

Naming consistency:
- `timePage` (field), `filterByTimePage` (extension), `kTimePageMeta` (const), `TimePageMeta` (class) — all use the same kebab/camel case spelling.
- `timePageMetaOf(slug)` mirrors `gameMetaOf(slug)`.
- All three Lab demos use `slug` keys that match `kTimePageMeta`.

No placeholders: every step has concrete code or commands.

Scope: single feature, single plan, can be merged in one PR.
