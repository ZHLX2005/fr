# 录音机 Zen 化 + 真波形 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `lib/lab/demos/recorder/` 从 demo 视觉升级到专业录音软件观感 —— zen 主题 + 真波形 + 实时电平表,公共 API / 系统集成(android widget、fr:// 路由、autostart)全部不动。

**Architecture:** 在 `RecorderController` 上加一个 `ValueListenable<double> dbListenable`(订阅 `record` 6.x 的 `onAmplitudeChanged`,已确认 `Amplitude.current` 是 dBFS),UI 层新增 `WaveformView`(CustomPainter 画幅度包络)+ `LevelMeterView`(16 段电平条),并把 `RecorderPageScaffold` / `RecorderListPage` / `native_media_page` 录音区全部换成 `zen_theme` 已有组件。0 新增依赖。

**Tech Stack:** Flutter (CustomPainter, ValueListenable),`record: ^6.0.0`(`AudioRecorder.onAmplitudeChanged` → `Stream<Amplitude>`,dBFS),`just_audio`,`permission_handler`,项目内置 `lib/widgets/theme/zen_theme.dart`。

---

## Global Constraints

(每一项任务的需求都隐式包含本节)

- **0 新增 pub 依赖**。所有能力来自 flutter sdk / 已有包(`record` / `just_audio` / `permission_handler`)/ 项目内 `zen_theme.dart`。
- **`Amplitude.current` 是 dBFS**(已从 `record_platform_interface-1.6.0/lib/src/types/amplitude.dart` 类注释 `/// dBFS amplitude` 确认)。**不要**再做 `20*log10` 换算,直接用 `current`,钳制到 `[-60, 0]`。
- **公开 API 不变**:`recorderPageKey`、`markRecorderAutoStart`、`recorderAutoStartPending`、`consumeRecorderAutoStart`、`RecorderController` 全部现有 getter/方法签名保留。只**新增** `dbListenable`。
- **Android widget / fr:// 路由 / handler / Lab 注册不动**。`recorder_handler.dart`、`recorder_demo.dart`、`RecorderWidgetProvider.kt`、`recorder_widget.xml` 不在本计划修改范围。
- **测试位置**:`test/lab/demos/recorder/`(新建目录,与 `test/lab/demos/clock` 平级)。
- **commit 消息**用 Conventional Commits 中文 body,结尾加 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- **不在 master 直接提交大改动前的中间产物**:每个 task 一个 commit,master 上推进即可(项目当前就在 master 上开发,见 git status)。

---

## File Structure

```
lib/widgets/theme/zen_theme.dart                    ← 修改:加 formatRecordDate(date) 工具函数(供 list 页 + native media 复用)
lib/lab/demos/recorder/
  recorder_controller.dart                          ← 修改:加 dbListenable + amplitude stream 订阅
  waveform_view.dart                                ← 新增:WaveformView + LevelMeterView + _WaveformPainter
  recorder_page.dart                                ← 修改:RecorderPageScaffold + 子组件全部 zen 化 + 接 waveform
  recorder_list_page.dart                           ← 修改:zenCard + ZenIconButton + ZenEmptyState + ZenConfirmDialog
  const_recorder.dart                               ← 不改(常量/UI 文本/枚举都不变)
  recorder_demo.dart                                ← 不改
lib/screens/profile/native_controller/
  native_media_page.dart                            ← 修改:录音区按钮 + 时长显示 zen 化

test/lab/demos/recorder/                            ← 新增目录
  waveform_painter_test.dart                        ← 新增:_WaveformPainter 几何测试
  recorder_controller_amplitude_test.dart           ← 新增:dbListenable 行为测试
```

**职责边界**:

- `waveform_view.dart` 只负责"把 dBFS 画出来",纯展示 widget,不依赖 `RecorderController`(只吃 `ValueListenable<double>`)。这样它能在 widgetbook / 测试里独立验证,也能被未来其他录音场景复用。
- `recorder_controller.dart` 只多一个 amplitude 通道,状态机/CRUD/播放逻辑不动。
- `recorder_page.dart` 仍是 UI 装配层,但子组件拆得更细(详见各 task)。

---

## Task 1: zen_theme 加 formatRecordDate 工具函数

录音列表页和 native_media 页都需要把 `DateTime` 格式化成 `YYYY-MM-DD HH:MM`,当前 `recorder_list_page.dart:199` 的 `_fmtDate` 是本地重复实现。提到 zen_theme 让全项目复用。

**Files:**
- Modify: `lib/widgets/theme/zen_theme.dart`(在 `formatTime` 函数后追加)
- Test: `test/widgets/theme/zen_theme_test.dart`(若不存在则新建)

**Interfaces:**
- Produces: `String formatRecordDate(DateTime d)` — 输入 `DateTime`,输出 `'YYYY-MM-DD HH:MM'`(零填充)。

- [ ] **Step 1: 写失败测试**

新建 `test/widgets/theme/zen_theme_test.dart`(若已存在则追加 group):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

void main() {
  group('formatRecordDate', () {
    test('零填充到 YYYY-MM-DD HH:MM', () {
      final d = DateTime(2026, 8, 3, 9, 5);
      expect(formatRecordDate(d), '2026-08-03 09:05');
    });

    test('双位数月份/日期/时分不变', () {
      final d = DateTime(2026, 12, 31, 23, 59);
      expect(formatRecordDate(d), '2026-12-31 23:59');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/theme/zen_theme_test.dart`
Expected: FAIL,`formatRecordDate` 未定义(或新 group 报 `method doesn't exist`)。

- [ ] **Step 3: 实现 formatRecordDate**

在 `lib/widgets/theme/zen_theme.dart` 的 `formatTime` 函数(约 line 365)之后追加:

```dart
/// 录音/记录列表用的日期格式:`YYYY-MM-DD HH:MM`(零填充)。
///
/// 比 `formatTime` 多了日期,给 recorder 列表页、native_media 测试页等
/// 需要展示"文件最后修改时间"的场景复用。
String formatRecordDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/theme/zen_theme_test.dart`
Expected: PASS,2 个 test 全绿。

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/theme/zen_theme.dart test/widgets/theme/zen_theme_test.dart
git commit -m "feat(zen): 加 formatRecordDate 日期格式化工具

recorder 列表页 / native_media 复用,消除本地 _fmtDate 重复实现。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: RecorderController 加 dbListenable + amplitude 订阅

给 controller 加一个 dBFS 通道,供 WaveformView / LevelMeterView 订阅。状态机和现有 API 完全不动。

**Files:**
- Modify: `lib/lab/demos/recorder/recorder_controller.dart`
- Test: `test/lab/demos/recorder/recorder_controller_amplitude_test.dart`(新建目录)

**Interfaces:**
- Consumes: `record` 包的 `AudioRecorder.onAmplitudeChanged(Duration) → Stream<Amplitude>`,`Amplitude.current`(dBFS,double)。
- Produces:
  - `final ValueNotifier<double> amplitudeDbListenable`(初始值 `-60.0`)
  - `ValueListenable<double> get dbListenable => amplitudeDbListenable;`
  - 内部 `StreamSubscription<Amplitude>? _amplitudeSub`

- [ ] **Step 1: 写失败测试**

新建 `test/lab/demos/recorder/recorder_controller_amplitude_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';

void main() {
  group('RecorderController dbListenable', () {
    test('初始 dBFS 为 -60(空闲态)', () {
      final c = RecorderController();
      expect(c.dbListenable.value, -60.0);
      c.dispose();
    });

    test('dispose 后 dbListenable 仍可安全读取不抛', () {
      final c = RecorderController();
      c.dispose();
      expect(() => c.dbListenable.value, returnsNormally);
    });

    test('amplitudeDbListenable 是同一个 ValueNotifier', () {
      // 暴露给测试:确认两个 getter 指向同一源
      final c = RecorderController();
      expect(identical(c.dbListenable, c.amplitudeDbListenable), isTrue);
      c.dispose();
    });
  });
}
```

> 说明:真实 amplitude stream 依赖平台麦克风,无法在 flutter_test 里端到端跑。这里只测"通道存在 + 初始值 + dispose 安全"。stream 真实订阅逻辑在 Task 2 实现里写好,留待真机/模拟器手测。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/lab/demos/recorder/recorder_controller_amplitude_test.dart`
Expected: FAIL,`dbListenable` / `amplitudeDbListenable` 未定义。

- [ ] **Step 3: 实现 dbListenable + amplitude 订阅**

修改 `lib/lab/demos/recorder/recorder_controller.dart`:

**(a) 顶部 import 区**(line 1-10)追加:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
```
(检查现有 import,`dart:async` 和 `dart:io` 已在;只补 `dart:math`。)

**(b) 在 `_tickNotifier` 字段附近(line ~351)追加**:

```dart
  // ─────────────────────────── amplitude (dBFS) ───────────────────────────

  /// 1Hz 抽样的当前 dBFS。范围 [-60, 0];空闲/暂停态 = -60。
  ///
  /// 来源:`AudioRecorder.onAmplitudeChanged`(record 6.x)。
  /// `Amplitude.current` 已是 dBFS(见 record_platform_interface
  /// amplitude.dart 类注释 `/// dBFS amplitude`),无需再 20*log10 换算。
  final ValueNotifier<double> amplitudeDbListenable =
      ValueNotifier<double>(-60.0);
  ValueListenable<double> get dbListenable => amplitudeDbListenable;

  StreamSubscription<Amplitude>? _amplitudeSub;

  /// dBFS 抽样间隔 —— 比 ticker(1s)密,保证波形平滑。
  static const Duration _amplitudeInterval = Duration(milliseconds: 200);
```

**(c) 在 `start()` 方法里,`_recorder.start(...)` 成功之后(`_state = RecorderState.recording;` 之前或之后均可)调用**:

```dart
      _startAmplitude();
```

**(d) 新增 `_startAmplitude` / `_stopAmplitude` 方法**(放在 ticker 区附近):

```dart
  void _startAmplitude() {
    _stopAmplitude();
    // onAmplitudeChanged 内部用 Timer.periodic 轮询平台,hasListener 才吐值。
    _amplitudeSub = _recorder
        .onAmplitudeChanged(_amplitudeInterval)
        .listen((amp) => _pushAmplitude(amp.current));
  }

  void _stopAmplitude() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _pushAmplitude(-60.0);
  }

  void _pushAmplitude(double db) {
    if (_disposed) return; // dispose 守门
    // 钳制到 [-60, 0],防止平台异常值(部分设备静音时返回 -inf / -1000)。
    final clamped = db.isNaN || db < -60.0
        ? -60.0
        : (db > 0.0 ? 0.0 : db);
    amplitudeDbListenable.value = clamped;
  }
```

**(e) 在 `pause()` 里**(`_state = RecorderState.paused;` 之后)加:

```dart
      _stopAmplitude(); // 暂停时波形静止,回到 -60 基线
```

**(f) 在 `resume()` 里**(`_state = RecorderState.recording;` 之后)加:

```dart
      _startAmplitude();
```

**(g) 在 `stop()` 里**(`_state = RecorderState.stopped;` 之后)加:

```dart
      _stopAmplitude();
```

**(h) 在 `discard()` 和 `commitSave()` 里**(回到 idle 前)各加:

```dart
      _stopAmplitude();
```

**(i) 在 `dispose()` 里**(line ~378,`_stopTicker();` 之后)加:

```dart
    _stopAmplitude();
    amplitudeDbListenable.dispose();
```

> 注意:已有 `_disposed = true;` 在 dispose 顶部,`_pushAmplitude` 会因 `_disposed` 守门而跳过;但 `amplitudeDbListenable.dispose()` 仍要显式调。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/lab/demos/recorder/recorder_controller_amplitude_test.dart`
Expected: PASS,3 个 test 全绿。

- [ ] **Step 5: 编译确认没引入语法错误**

Run: `flutter analyze lib/lab/demos/recorder/recorder_controller.dart`
Expected: 无 error(warning 可接受,但不应有新 error)。

- [ ] **Step 6: 提交**

```bash
git add lib/lab/demos/recorder/recorder_controller.dart test/lab/demos/recorder/recorder_controller_amplitude_test.dart
git commit -m "feat(recorder): controller 加 dbListenable (dBFS 通道)

订阅 record.onAmplitudeChanged,Amplitude.current 已是 dBFS。
开始/继续启动订阅,暂停/停止/放弃/保存 回到 -60 基线。
公开 API 仅新增 dbListenable,其余不动。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: WaveformView + LevelMeterView + _WaveformPainter

纯展示 widget,吃 `ValueListenable<double>`,用 CustomPainter 画幅度包络 + 电平条。

**Files:**
- Create: `lib/lab/demos/recorder/waveform_view.dart`
- Test: `test/lab/demos/recorder/waveform_painter_test.dart`

**Interfaces:**
- Consumes: `zen_theme.dart` 的 `ZenColors` / `ZenText`,`ValueListenable<double>`(来自 Task 2 的 `dbListenable`)。
- Produces:
  - `WaveformView({required ValueListenable<double> dbListenable, required bool active})`
  - `LevelMeterView({required ValueListenable<double> dbListenable, required bool active})`
  - `_WaveformPainter({required List<double> dbs, required Color baseColor, required Color hotColor, required Color centerLine})` —— painter 是 private,但测试需要它可被实例化 + `paint` 可被复现。测试用 `golden` 或 `size`/`shouldRepaint` 行为验证(见下)。

- [ ] **Step 1: 写失败测试 —— painter 几何**

新建 `test/lab/demos/recorder/waveform_painter_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/waveform_view.dart';

void main() {
  group('_WaveformPainter', () {
    test('shouldRepaint: dbs 引用不同 → 重绘', () {
      final a = _makePainter([-60, -30, 0]);
      final b = _makePainter([-60, -30, -10]); // 内容不同
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint: dbs 相同引用 → 不重绘', () {
      final dbs = <double>[-60, -30, 0];
      final a = _makePainter(dbs);
      final b = _makePainter(dbs); // 同一引用
      expect(a.shouldRepaint(b), isFalse);
    });

    test('dbToRatio: -60 → 0,0 → 1,中段线性', () {
      expect(dbToRatio(-60), 0.0);
      expect(dbToRatio(0), 1.0);
      expect(dbToRatio(-30), closeTo(0.5, 1e-9));
      // 钳制
      expect(dbToRatio(-100), 0.0);
      expect(dbToRatio(5), 1.0);
    });

    test('dbToRatio NaN → 0', () {
      expect(dbToRatio(double.nan), 0.0);
    });
  });
}

_WaveformPainter _makePainter(List<double> dbs) {
  return _WaveformPainter(
    dbs: dbs,
    baseColor: const Color(0xFF7A9A7E),
    hotColor: const Color(0xFFA0594A),
    centerLine: const Color(0xFFD9D5C8),
  );
}
```

> 说明:painter 的 `paint()` 用 Canvas 画,flutter_test 里需要 `paintImage`/`tester.binding` 才能渲染,过于重。这里只测**纯函数 `dbToRatio` + `shouldRepaint` 契约**,这是 painter 正确性的核心(坐标换算)。把 `dbToRatio` 做成顶层函数,测试可直接 import。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/lab/demos/recorder/waveform_painter_test.dart`
Expected: FAIL,`waveform_view.dart` 不存在 / `_WaveformPainter` / `dbToRatio` 未定义。

- [ ] **Step 3: 实现 waveform_view.dart**

新建 `lib/lab/demos/recorder/waveform_view.dart`:

```dart
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/theme/zen_theme.dart';

/// dBFS → [0,1] 显示比例。-60dB → 0,0dB → 1,线性,带 NaN/越界钳制。
///
/// 顶层函数:painter 和 LevelMeterView 共用,也方便单测。
double dbToRatio(double db) {
  if (db.isNaN || db.isInfinite) return 0.0;
  if (db <= -60.0) return 0.0;
  if (db >= 0.0) return 1.0;
  return (db + 60.0) / 60.0;
}

/// 实时幅度波形 —— 中央基线上下对称的条形包络。
///
/// 订阅 [dbListenable],内部维护环形缓冲(默认 200 帧 ≈ 200px @ 1px/列)。
/// 仅在录音中(`active=true`)时追加新帧;暂停/停止时保留最后一帧静止。
class WaveformView extends StatefulWidget {
  final ValueListenable<double> dbListenable;
  final bool active;

  /// 缓冲帧数(同时也是最大显示列数,1 帧 = 1 列)。
  final int maxBars;

  const WaveformView({
    super.key,
    required this.dbListenable,
    required this.active,
    this.maxBars = 200,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  late final ListQueue<double> _dbs;

  @override
  void initState() {
    super.initState();
    _dbs = ListQueue<double>(widget.maxBars);
    widget.dbListenable.addListener(_onDb);
  }

  @override
  void didUpdateWidget(covariant WaveformView old) {
    super.didUpdateWidget(old);
    if (old.dbListenable != widget.dbListenable) {
      old.dbListenable.removeListener(_onDb);
      widget.dbListenable.addListener(_onDb);
    }
  }

  void _onDb() {
    if (!widget.active) return; // 非录音态不追加,保留静态画面
    final v = widget.dbListenable.value;
    if (_dbs.length >= widget.maxBars) _dbs.removeFirst();
    _dbs.add(v);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.dbListenable.removeListener(_onDb);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        dbs: _dbs.toList(growable: false),
        baseColor: ZenColors.sage,
        hotColor: ZenColors.mutedRed,
        centerLine: ZenColors.hair,
      ),
      size: const Size.fromHeight(140),
      isComplex: true,
      willChange: true,
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> dbs;
  final Color baseColor;
  final Color hotColor;
  final Color centerLine;

  const _WaveformPainter({
    required this.dbs,
    required this.baseColor,
    required this.hotColor,
    required this.centerLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    final maxBarH = cy - 4; // 上下各留 4px

    // 基线
    final linePaint = Paint()
      ..color = centerLine
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, cy), Offset(w, cy), linePaint);

    if (dbs.isEmpty) return;

    final barPaint = Paint()..style = PaintingStyle.fill;
    final step = w / dbs.length;
    for (var i = 0; i < dbs.length; i++) {
      final ratio = dbToRatio(dbs[i]);
      // 0.7 次幂:让小信号也可见,大信号更突出(视觉冲击)
      final mag = math.pow(ratio, 0.7).toDouble() * maxBarH;
      // 过载(>−3dBFS,即 ratio > 0.95)染红警示
      barPaint.color = ratio > 0.95 ? hotColor : baseColor;
      final x = i * step + step / 2;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, cy), width: step * 0.7, height: mag * 2),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) {
    // 引用不同 → 内容可能变了 → 重绘。dbs 是 build 时新建的 toList,所以每次 setState 都会不同。
    return !identical(dbs, old.dbs) ||
        baseColor != old.baseColor ||
        hotColor != old.hotColor ||
        centerLine != old.centerLine;
  }
}

/// 水平电平条:16 段 + 当前 dBFS 数值。
///
/// 单声道只渲染一条;v1 mono 固定。stereo 扩展 hook:后续可加第二 listenable。
class LevelMeterView extends StatelessWidget {
  final ValueListenable<double> dbListenable;
  final bool active;

  const LevelMeterView({
    super.key,
    required this.dbListenable,
    required this.active,
  });

  static const int _segments = 16;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dbListenable,
      builder: (context, _) {
        final ratio = active ? dbToRatio(dbListenable.value) : 0.0;
        final litCount = (ratio * _segments).round();
        return Row(
          children: [
            Text('L', style: ZenText.monoDigitSmall),
            const SizedBox(width: 6),
            Expanded(child: _MeterStrip(litCount: litCount)),
            const SizedBox(width: 6),
            Text('R', style: ZenText.monoDigitSmall),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                '${dbListenable.value.toStringAsFixed(1)} dB',
                style: ZenText.monoDigitSmall,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MeterStrip extends StatelessWidget {
  final int litCount;
  const _MeterStrip({required this.litCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_MeterViewSegments.segments, (i) {
        final lit = i < litCount;
        // 0-9 sage,10-13 浅黄(用 secondary 代替,zen 无黄),14-15 mutedRed
        final color = i < 10
            ? ZenColors.sage
            : (i < 14 ? ZenColors.secondary : ZenColors.mutedRed);
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            height: 10,
            decoration: BoxDecoration(
              color: lit ? color : ZenColors.hair.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}

// 段数常量单点定义,供 LevelMeterView 和 _MeterStrip 共用。
class _MeterViewSegments {
  static const int segments = 16;
}
```

> 类型一致性自检:`_MeterStrip` 用 `_MeterViewSegments.segments`,而 `LevelMeterView._segments = 16`,两者都是 16。**修正:为了去掉这个别扭的中间类,直接把 `_MeterStrip` 改为接收 `segments` 参数,或者两者都用顶层常量。** 见 Step 3b 修正。

- [ ] **Step 3b: 修正段数常量(去掉 _MeterViewSegments 别扭类)**

把 `LevelMeterView` 里的 `_segments` 提为文件顶层常量,`_MeterStrip` 直接用它:

替换 `static const int _segments = 16;` 和 `class _MeterViewSegments {...}` 整段为:

```dart
const int _kMeterSegments = 16;
```

并把 `LevelMeterView` 内 `final litCount = (ratio * _segments).round();` 改为 `(ratio * _kMeterSegments).round();`,`_MeterStrip` 内 `List.generate(_MeterViewSegments.segments, ...)` 改为 `List.generate(_kMeterSegments, ...)`。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/lab/demos/recorder/waveform_painter_test.dart`
Expected: PASS,4 个 test 全绿。

- [ ] **Step 5: 编译确认**

Run: `flutter analyze lib/lab/demos/recorder/waveform_view.dart`
Expected: 无 error。

- [ ] **Step 6: 提交**

```bash
git add lib/lab/demos/recorder/waveform_view.dart test/lab/demos/recorder/waveform_painter_test.dart
git commit -m "feat(recorder): WaveformView + LevelMeterView (真波形/电平表)

CustomPainter 画 dBFS 包络 + 16 段水平电平条。
纯展示 widget,只吃 ValueListenable<double>,不依赖 controller。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: RecorderPageScaffold + 子组件 zen 化

把 `recorder_page.dart` 的视觉层全部换成 zen 主题,接上 WaveformView / LevelMeterView。这是最大的一块改动。

**Files:**
- Modify: `lib/lab/demos/recorder/recorder_page.dart`(全文件重写 UI 部分,保留 `recorderPageKey` / autostart 逻辑不动)

**Interfaces:**
- Consumes: Task 2 的 `dbListenable`,Task 3 的 `WaveformView` / `LevelMeterView`,Task 1 的 `formatTime`,`zen_theme` 全套。
- Produces: 不变(`RecorderDemoPage` / `RecorderPageScaffold` 公开 API 保留)。

- [ ] **Step 1: 准备 —— 通读现有 recorder_page.dart 全文**

Run: `flutter analyze lib/lab/demos/recorder/recorder_page.dart`(确认改前是干净的)

确认你要保留不动的部分:
- line 19-20:`recorderPageKey`
- line 24-44:`_pendingAutoStart` / `recorderAutoStartPending` / `markRecorderAutoStart` / `consumeRecorderAutoStart`
- line 50-116:`RecorderDemoPage` + `_RecorderDemoPageState`(autostart 消费逻辑)
- 这些**一个字都不改**。只重写 `RecorderPageScaffold`(line 124 起)和它的子组件(line 256 起)。

- [ ] **Step 2: 重写 import + RecorderPageScaffold**

把 `lib/lab/demos/recorder/recorder_page.dart` 顶部 import 区改为:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'recorder_controller.dart';
import 'const_recorder.dart';
import 'recorder_list_page.dart';
import 'waveform_view.dart';
import '../../../widgets/theme/zen_theme.dart';
```

(去掉了 `package:flutter/foundation.dart` —— 原本只为 `ValueListenable`,现在 zen_theme 已 re-export 或直接用 `flutter/material` 里的 `ValueListenableBuilder`,material 里就有 `ValueListenable`。若 analyze 报缺,补回。)

把 `RecorderPageScaffold`(原 line 124-251)整体替换为:

```dart
class RecorderPageScaffold extends StatelessWidget {
  final RecorderController controller;
  final Future<bool> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<String?> Function() onStop;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const RecorderPageScaffold({
    super.key,
    required this.controller,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return zenPageScaffold(
      title: '录音机',
      actions: [
        ZenIconButton(
          icon: Icons.library_music_outlined,
          color: ZenColors.ink,
          variant: ZenIconButtonVariant.outline,
          size: 40,
          iconSize: 20,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecorderListPage(controller: controller),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormatInfoSection(),
              const SizedBox(height: 16),
              _WaveformSection(controller: controller),
              const SizedBox(height: 12),
              _LevelSection(controller: controller),
              const SizedBox(height: 20),
              _ElapsedDisplay(listenable: controller.tickListenable),
              const SizedBox(height: 24),
              _ControlPanel(
                controller: controller,
                onStart: onStart,
                onPause: onPause,
                onResume: onResume,
                onStop: onStop,
                onSave: onSave,
                onDiscard: onDiscard,
              ),
              const SizedBox(height: 24),
              _LastRecordingCard(controller: controller),
              const SizedBox(height: 16),
              _PermissionBanner(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 重写子组件**

把原 line 256 起的所有子组件(`_ElapsedDisplay` / `_WaveformPlaceholder` / `_PermissionBanner` / `_ControlPanel` / `_RecordButton` / `_LastRecordingCard`)**整体替换**为下面的新版本:

```dart
// ─────────────────────────── 子组件 ───────────────────────────

/// 工程信息面板:编码 / 采样率 / 比特率 / 声道。只读展示。
class _FormatInfoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ZenSection(
      title: '工程信息',
      child: Text(
        'AAC LC · ${RecorderDefaults.sampleRate ~/ 1000}.1 kHz · '
        '${RecorderDefaults.bitRate ~/ 1000} kbps · '
        '${RecorderDefaults.numChannels == 1 ? "MONO" : "STEREO"}',
        style: ZenText.monoDigitSmall,
      ),
    );
  }
}

/// 波形 + 状态指示。
class _WaveformSection extends StatelessWidget {
  final RecorderController controller;
  const _WaveformSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isLive = controller.state == RecorderState.recording;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: zenCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ZenDot(active: isLive, color: ZenColors.mutedRed),
                  const SizedBox(width: 8),
                  Text(
                    isLive ? '正在录音' : _stateLabel(controller.state),
                    style: ZenText.label,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              WaveformView(
                dbListenable: controller.dbListenable,
                active: isLive,
              ),
            ],
          ),
        );
      },
    );
  }

  String _stateLabel(RecorderState s) => switch (s) {
        RecorderState.idle => '就绪',
        RecorderState.paused => '已暂停',
        RecorderState.stopped => '已停止',
        RecorderState.recording => '正在录音',
      };
}

/// 电平条。
class _LevelSection extends StatelessWidget {
  final RecorderController controller;
  const _LevelSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isLive = controller.state == RecorderState.recording;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: zenCard(),
          child: LevelMeterView(
            dbListenable: controller.dbListenable,
            active: isLive,
          ),
        );
      },
    );
  }
}

/// 时长大字号显示。
class _ElapsedDisplay extends StatelessWidget {
  final ValueListenable<Duration> listenable;
  const _ElapsedDisplay({required this.listenable});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: listenable,
      builder: (context, value, _) {
        return Center(
          child: Text(
            formatTime(value.inSeconds),
            style: ZenText.monoDigitLarge,
          ),
        );
      },
    );
  }
}

/// 控制面板 —— 按状态切 hero + outline 组合。
class _ControlPanel extends StatelessWidget {
  final RecorderController controller;
  final Future<bool> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<String?> Function() onStop;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const _ControlPanel({
    required this.controller,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        switch (state) {
          case RecorderState.idle:
            return _CenterControls([
              _HeroRecord(onTap: onStart, icon: Icons.fiber_manual_record),
            ]);
          case RecorderState.recording:
            return _CenterControls([
              _OutlineBtn(
                  icon: Icons.pause, label: '暂停', color: ZenColors.secondary, onTap: onPause),
              const SizedBox(width: 24),
              _HeroRecord(onTap: () async => onStop(), icon: Icons.stop),
            ]);
          case RecorderState.paused:
            return _CenterControls([
              _OutlineBtn(
                  icon: Icons.play_arrow, label: '继续', color: ZenColors.sage, onTap: onResume),
              const SizedBox(width: 24),
              _HeroRecord(onTap: () async => onStop(), icon: Icons.stop),
            ]);
          case RecorderState.stopped:
            return _CenterControls([
              _OutlineBtn(
                  icon: Icons.check, label: '保存', color: ZenColors.sage, onTap: () async => onSave()),
              const SizedBox(width: 24),
              _OutlineBtn(
                  icon: Icons.close, label: '放弃', color: ZenColors.mutedRed, onTap: () async => onDiscard()),
            ]);
        }
      },
    );
  }
}

class _CenterControls extends StatelessWidget {
  final List<Widget> children;
  const _CenterControls(this.children);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

/// hero 大圆录音键(磁带符号)。
class _HeroRecord extends StatelessWidget {
  final Future Function() onTap;
  final IconData icon;
  const _HeroRecord({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ZenIconButton(
      icon: icon,
      variant: ZenIconButtonVariant.hero,
      color: ZenColors.mutedRed,
      onTap: () async => await onTap(),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Future Function() onTap;
  const _OutlineBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async => await onTap(),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: ZenColors.hair),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: ZenText.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 最近一次录音卡片。
class _LastRecordingCard extends StatelessWidget {
  final RecorderController controller;
  const _LastRecordingCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final path = controller.lastSavedPath;
        if (path == null) {
          return Text(
            RecorderUiText.noRecordingHint,
            style: ZenText.label,
          );
        }
        final sizeKb = (controller.lastFileSize / 1024).toStringAsFixed(1);
        final name = path.split(Platform.pathSeparator).last;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: zenCard(),
          child: Row(
            children: [
              const Icon(Icons.audiotrack, color: ZenColors.sage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZenText.body),
                    Text('$sizeKb KB', style: ZenText.monoDigitSmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 权限横幅:未授权时展示,提供授权按钮。
class _PermissionBanner extends StatelessWidget {
  final RecorderController controller;
  const _PermissionBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.permissionStatus;
        if (status == RecorderPermissionStatus.granted ||
            status == RecorderPermissionStatus.unknown) {
          return const SizedBox.shrink();
        }
        final isPermanent = status == RecorderPermissionStatus.permanentlyDenied;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: zenCard(color: ZenColors.mutedRed.withValues(alpha: 0.06)),
          child: Row(
            children: [
              const Icon(Icons.mic_off, color: ZenColors.mutedRed, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isPermanent
                      ? RecorderUiText.permissionDeniedHint
                      : RecorderUiText.requestPermission,
                  style: ZenText.label.copyWith(color: ZenColors.mutedRed),
                ),
              ),
              OutlinedButton(
                style: zenButton(
                  foreground: ZenColors.mutedRed,
                  border: ZenColors.mutedRed,
                ),
                onPressed: () => controller.ensurePermission(),
                child: Text(isPermanent ? '打开设置' : '授权'),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: 删除已无用的 `_format` / `_RecordButton`**

确认旧 `recorder_page.dart` 里的:
- `_ElapsedDisplay._format(Duration)` —— 已被 `formatTime` 取代,**删除**。
- `class _RecordButton` —— 已被 `_OutlineBtn` / `_HeroRecord` 取代,**删除**。
- `class _WaveformPlaceholder` —— 已被 `_WaveformSection` 取代,**删除**。

若用整段替换法(Step 3 把 line 256 起全替换),这些已自然消失。若用 Edit 增量法,单独删。

- [ ] **Step 5: 编译 + 静态分析**

Run: `flutter analyze lib/lab/demos/recorder/`
Expected: 无 error。若报 `ValueListenable` 未导入,在顶部加 `import 'package:flutter/foundation.dart';`。

- [ ] **Step 6: 冒烟测试 —— 整页能渲染**

新建/追加 `test/lab/demos/recorder/recorder_page_smoke_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_page.dart';

void main() {
  testWidgets('RecorderPageScaffold idle 态能渲染,无异常', (tester) async {
    final controller = RecorderController();
    await tester.pumpWidget(
      MaterialApp(
        home: RecorderPageScaffold(
          controller: controller,
          onStart: controller.start,
          onPause: controller.pause,
          onResume: controller.resume,
          onStop: controller.stop,
          onSave: () {},
          onDiscard: () {},
        ),
      ),
    );
    expect(find.text('录音机'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    // hero 录音键存在(fiber_manual_record icon)
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    controller.dispose();
  });
}
```

Run: `flutter test test/lab/demos/recorder/recorder_page_smoke_test.dart`
Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add lib/lab/demos/recorder/recorder_page.dart test/lab/demos/recorder/recorder_page_smoke_test.dart
git commit -m "feat(recorder): 主页 zen 化 + 接入真波形/电平表

- zenPageScaffold + ZenSection/ZenDot/ZenIconButton
- 工程信息面板(AAC LC · 44.1k · 128k · MONO)
- 真波形 WaveformView + 水平电平表 LevelMeterView
- hero 大圆录音键 + outline 暂停/停止/保存/放弃
- 时长用 formatTime,删除本地 _format

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: RecorderListPage zen 化

把列表页也换成 zen 主题,并复用 Task 1 的 `formatRecordDate`。

**Files:**
- Modify: `lib/lab/demos/recorder/recorder_list_page.dart`

**Interfaces:**
- Consumes: Task 1 `formatRecordDate`,`zen_theme`(`zenPageScaffold` / `zenCard` / `ZenIconButton` / `ZenEmptyState` / `zenButton` / `ZenColors` / `ZenText`)。
- Produces: 不变(`RecorderListPage` 公开 API 保留)。

- [ ] **Step 1: 重写 import 区**

把 `lib/lab/demos/recorder/recorder_list_page.dart` 顶部改为:

```dart
import 'package:flutter/material.dart';

import 'const_recorder.dart';
import 'recorder_controller.dart';
import '../../../widgets/theme/zen_theme.dart';
```

(去掉 `dart:io` 和 `../../../core/design/emphasis_button.dart`,它们不再被用。)

- [ ] **Step 2: 重写 build() 用 zenPageScaffold**

替换 `build` 方法(原 line 122-153):

```dart
  @override
  Widget build(BuildContext context) {
    final files = _files;
    return zenPageScaffold(
      title: RecorderUiText.listTitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: ZenColors.secondary),
          tooltip: '刷新',
          onPressed: _load,
        ),
        const SizedBox(width: 8),
      ],
      body: switch (files) {
        null => const Center(child: CircularProgressIndicator(color: ZenColors.sage)),
        _ when files.isEmpty => ZenEmptyState(
            icon: Icons.mic_none,
            message: RecorderUiText.emptyList,
            actionLabel: '刷新',
            onAction: _load,
          ),
        _ => RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: files.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final f = files[index];
                return _RecordingTile(
                  file: f,
                  playing: widget.controller.playingPath == f.path,
                  onPlay: () => widget.controller.playFile(f.path),
                  onRename: () => _rename(f),
                  onDelete: () => _delete(f),
                );
              },
            ),
          ),
      },
    );
  }
```

- [ ] **Step 3: 删除 _EmptyState(被 ZenEmptyState 取代)**

删除原 `class _EmptyState`(line 157-181),它已被 `ZenEmptyState` 内联替换。

- [ ] **Step 4: 重写 _RecordingTile**

替换 `class _RecordingTile`(原 line 184-248):

```dart
class _RecordingTile extends StatelessWidget {
  final RecordingFile file;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _RecordingTile({
    required this.file,
    required this.playing,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: zenCard(),
      child: Row(
        children: [
          Icon(
            playing ? Icons.graphic_eq : Icons.audiotrack,
            color: playing ? ZenColors.mutedRed : ZenColors.sage,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZenText.body,
                ),
                Text(
                  '${file.sizeKb.toStringAsFixed(1)} KB · ${formatRecordDate(file.lastModified)}',
                  style: ZenText.monoDigitSmall,
                ),
              ],
            ),
          ),
          ZenIconButton(
            icon: playing ? Icons.stop_circle : Icons.play_circle,
            color: playing ? ZenColors.mutedRed : ZenColors.sage,
            variant: ZenIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: onPlay,
          ),
          const SizedBox(width: 4),
          ZenIconButton(
            icon: Icons.edit_outlined,
            color: ZenColors.secondary,
            variant: ZenIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: onRename,
          ),
          const SizedBox(width: 4),
          ZenIconButton(
            icon: Icons.delete_outline,
            color: ZenColors.mutedRed,
            variant: ZenIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}
```

注意:删除了原 `_fmtDate` 方法,改用 `formatRecordDate(file.lastModified)`。

- [ ] **Step 5: 重命名对话框用 zenButton**

替换 `_rename` 方法里的 `OutlinedButton`(原 line 72-79):

```dart
          OutlinedButton(
            style: zenButton(
              foreground: ZenColors.sage,
              border: ZenColors.sage,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(RecorderUiText.renameOk),
          ),
```

并把 import 里的 `../../../core/design/emphasis_button.dart` 删掉(Step 1 已做)。

- [ ] **Step 6: 删除对话框用 zenButton**

替换 `_delete` 方法里的 `OutlinedButton`(原 line 107-112):

```dart
          OutlinedButton(
            style: zenButton(
              foreground: ZenColors.mutedRed,
              border: ZenColors.mutedRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(RecorderUiText.deleteBtn),
          ),
```

- [ ] **Step 7: 编译 + 静态分析**

Run: `flutter analyze lib/lab/demos/recorder/recorder_list_page.dart`
Expected: 无 error。

- [ ] **Step 8: 冒烟测试**

新建 `test/lab/demos/recorder/recorder_list_page_smoke_test.dart`(`RecorderUiText` 是 const_recorder.dart 里的 public 常量类,可直接 import):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/const_recorder.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_list_page.dart';

void main() {
  testWidgets('RecorderListPage 空态渲染', (tester) async {
    final controller = RecorderController();
    await tester.pumpWidget(
      MaterialApp(home: RecorderListPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 注意:依赖沙盒 recordings/ 目录为空。CI 首跑通常为空;
    // 开发者本地若有历史录音,此断言会失败 —— 属预期,可临时跳过。
    expect(find.text(RecorderUiText.emptyList), findsOneWidget);
    controller.dispose();
  });
}
```

- [ ] **Step 9: 提交**

```bash
git add lib/lab/demos/recorder/recorder_list_page.dart test/lab/demos/recorder/recorder_list_page_smoke_test.dart
git commit -m "feat(recorder): 列表页 zen 化

zenPageScaffold + zenCard + ZenIconButton(tint) + ZenEmptyState。
日期用 formatRecordDate,删除本地 _fmtDate。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: native_media_page 录音区 zen 化

顺手把测试页的录音按钮区也升级到 zen,与录音机视觉一致。**不动** `AudioRecordingService`(职责不同)。

**Files:**
- Modify: `lib/screens/profile/native_controller/native_media_page.dart`

**Interfaces:**
- Consumes:`zen_theme`(`ZenIconButton` / `ZenText` / `zenCard` / `ZenColors`),现有 `AudioRecordingService` / `AudioPlayer` 不动。

- [ ] **Step 1: 加 zen_theme import**

在 `native_media_page.dart` 顶部 import 区(line 1-6)追加:

```dart
import '../../../widgets/theme/zen_theme.dart';
```

- [ ] **Step 2: 替换录音按钮组**

替换原 line 432-483 的录音测试 `Row` + 状态文字:

```dart
                    // 录音测试
                    Text('录音功能测试', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ZenIconButton(
                          icon: Icons.mic,
                          color: ZenColors.mutedRed,
                          variant: _isAudioRecording
                              ? ZenIconButtonVariant.tint
                              : ZenIconButtonVariant.outline,
                          onTap: _isAudioRecording ? null : _startRecording,
                        ),
                        const SizedBox(width: 12),
                        ZenIconButton(
                          icon: Icons.stop,
                          color: ZenColors.secondary,
                          variant: ZenIconButtonVariant.outline,
                          onTap: _isAudioRecording ? _stopRecording : null,
                        ),
                        const SizedBox(width: 12),
                        if (_isAudioRecording)
                          Expanded(
                            child: Text(
                              '录音中 ${_recordingDuration}s',
                              style: ZenText.monoDigitSmall,
                            ),
                          ),
                      ],
                    ),
```

- [ ] **Step 3: 替换录音预览卡片**

替换原 line 514-563 的"录音预览" `Card`,改用 `zenCard` + `ZenText`:

```dart
            if (_recordedAudioPath != null && _recordedAudioPath!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: zenCard(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('录音预览', style: ZenText.title),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ZenIconButton(
                          icon: _isPlaying ? Icons.pause_circle : Icons.play_circle,
                          color: ZenColors.sage,
                          variant: ZenIconButtonVariant.tint,
                          size: 48,
                          iconSize: 24,
                          onTap: () => _playAudio(_recordedAudioPath!),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('录音文件', style: ZenText.body),
                              Text('时长: ${_recordingDuration}s',
                                  style: ZenText.monoDigitSmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
```

- [ ] **Step 4: 编译 + 静态分析**

Run: `flutter analyze lib/screens/profile/native_controller/native_media_page.dart`
Expected: 无 error。

- [ ] **Step 5: 提交**

```bash
git add lib/screens/profile/native_controller/native_media_page.dart
git commit -m "feat(native-media): 录音测试区 zen 化

ZenIconButton + zenCard + ZenText,与录音机视觉一致。
AudioRecordingService 不动(职责不同)。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 全局回归 + 文档收尾

整体验证编译、测试、并把"录音机模块已完成 zen 化"这件事记到 MEMORY(可选)。

**Files:**
- 无新建文件,跑命令为主。

- [ ] **Step 1: 全模块静态分析**

Run: `flutter analyze lib/lab/demos/recorder/ lib/screens/profile/native_controller/native_media_page.dart lib/widgets/theme/zen_theme.dart`
Expected: 无 error(warning 可接受,但 `RecorderConsts` / `RecorderDefaults` 不应有未使用警告)。

- [ ] **Step 2: 跑全部新增/相关测试**

Run: `flutter test test/lab/demos/recorder/ test/widgets/theme/zen_theme_test.dart`
Expected: 全绿。

- [ ] **Step 3: 全项目测试冒烟(确保没破坏其他)**

Run: `flutter test`
Expected: 全绿(若项目有已知 unrelated 失败,记录但不修)。

- [ ] **Step 4: (可选)手动真机/模拟器验证清单**

在 Android 模拟器或真机上跑:
- [ ] Lab → 录音机 → 点 hero 红圆开始 → 波形随声音跳动 → 电平条填充
- [ ] 暂停 → 波形静止、电平归零、状态显示"已暂停"
- [ ] 继续 → 波形恢复跳动
- [ ] 停止 → 显示"已停止" + 保存/放弃按钮
- [ ] 保存 → 最近录音卡片更新
- [ ] 列表页 → 能看到 zen 卡片、播放/重命名/删除三按钮、日期格式正确
- [ ] 桌面 widget 点击 → autostart 进入录音页并自动开始(系统集成未破坏)
- [ ] native_media 测试页 → 录音按钮 zen 样式、能录能播

- [ ] **Step 5: (可选)更新 memory**

若用户希望,在 `MEMORY.md` 加一行指向录音机模块的备注。**默认不写**,因为这是代码可记录的事实。

- [ ] **Step 6: 最终提交(若有零散改动)**

若 Step 1-3 全绿且无未提交改动,跳过。否则:

```bash
git add -A
git commit -m "chore(recorder): zen 化回归修复

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## 完成标志

所有 task 的 checkbox 打勾 + `flutter test` 全绿 + `flutter analyze` 无 error + 真机/模拟器手测清单通过。
