# 录音机 Zen 化重构设计

- **日期**: 2026-08-03
- **范围**: `lib/lab/demos/recorder/` 全模块 + `native_media_page.dart` 录音测试区
- **目标**: 把当前 demo 级别的录音机提升到"专业录音软件"观感
- **作者**: Claude (brainstorming → spec)

---

## 1. 背景与动机

`@lib/lab/demos/recorder/` 已经是"完整系统集成":

```
Android 桌面 widget (1×1) ─deep link─→  MainActivity
                                            ↓
                                       fr://lab/demo/recorder?autostart=true
                                            ↓
                                  RecorderHandler (router)
                                            ↓
                              RecorderDemoPage (autostart 消费)
                                            ↓
                              RecorderController (ChangeNotifier)
                                            ↓
                                  AudioRecorder (record 6.x)
```

功能完整,但视觉上仍是 demo:

- `_WaveformPlaceholder` 是个死的红圈(`recorder_page.dart:291`),**没有真波形**
- `_ControlPanel` 把按钮塞进 `Wrap`,使用 `Colors.redAccent` / `Colors.orange` / `Colors.green` 等饱和原色
- `_PermissionBanner` 用橙色背景的硬卡片
- 时长显示字体(56pt 无 tabular)是 Material 默认 sans-serif
- `RecorderListPage` 用 `Card` + `IconButton`,与项目其他页面(clock / metronome / track)脱节
- 时间格式化在 `recorder_page.dart:277` 又写了一份 `_format`,而 `zen_theme.dart` 已经有 `formatDuration` / `formatTime`

**关键问题**: 项目已有完整的 `zen_theme` 设计系统,且其他模块(clocks / metronome / track / novel reader)都已迁入。录音机是少数仍停留在"原始 Material"的模块。

---

## 2. 目标与非目标

### 2.1 目标

1. **视觉质感**: 把录音机改造成 zen 风格,看起来像 Audacity Mobile / Hindenburg / 唱吧录音棚那种专业感
2. **真波形 + 真电平**: 接入 `record.onAmplitudeChanged` 的 dBFS,绘制实时包络和水平电平表
3. **复用现有 zen 组件**: 不发明新色 / 新组件,只用 `zen_theme.dart` 已有的 `ZenSection` / `ZenIconButton` / `ZenDot` / `ZenEmptyState` / `formatDuration` / `formatTime` / `zenCard` / `zenPageScaffold`
4. **顺手统一录音 UI**: `native_media_page.dart` 里的录音测试区也升级到 zen
5. **保持系统集成**: fr:// 路由、Android widget、`recorderPageKey` / `markRecorderAutoStart` 全部不动

### 2.2 非目标

- ❌ 不做剪辑 / 多轨 / 拼接(留给后续 spec)
- ❌ 不做采样率/比特率 UI 切换(目前固定 AAC LC / 44.1k / 128kbps / MONO)
- ❌ 不改 Android widget XML / Kotlin 代码
- ❌ 不改 Lab 注册 / 路由 / handler

---

## 3. 设计原则

- **设计系统优先**: 任何视觉决策必须先在 `zen_theme.dart` 里找,找不到再考虑新增(若新增,应回到 zen 主题统一)
- **小颗粒改动**: 一次 PR 只做"zen 化 + 真波形",不混入新功能
- **公共 API 不动**: Controller 公开方法签名、autostart 标志、widget key、URI scheme 全部保留
- **测试先行**: `WaveformPainter` 是新逻辑的核心,先写测试

---

## 4. 架构与组件

### 4.1 现状分层

```
const_recorder.dart          ← 常量 / UI 文本 / 状态枚举
recorder_controller.dart     ← ChangeNotifier 状态机
recorder_page.dart           ← RecorderDemoPage + RecorderPageScaffold + 子组件
recorder_list_page.dart      ← 列表 CRUD
recorder_demo.dart           ← Lab 卡片入口(导出 key + autostart 标志)
```

### 4.2 目标分层

```
const_recorder.dart          ← 不动
recorder_controller.dart     ← 加 amplitudeDbListenable + 内部 stream 订阅
recorder_page.dart           ← RecorderPageScaffold 用 zenPageScaffold,加 WaveformView / LevelMeterView
waveform_view.dart           ← 新增:真波形 + 电平表 (CustomPainter)
recorder_list_page.dart      ← zenCard + ZenIconButton + ZenConfirmDialog
native_media_page.dart       ← 测试页录音区 zen 化
audio_recording_service.dart ← 保留(职责与 RecorderController 不同),内部调用换成更现代的实现(可选)
```

**不新增 `services/` 目录下的新文件** —— WaveformView 是纯 UI,与 controller 解耦。

### 4.3 RecorderController 改动

新增字段:

```dart
/// 1Hz 抽样的当前 dBFS (范围 [-60, 0],空闲 = -60)
final ValueNotifier<double> amplitudeDbListenable = ValueNotifier(-60.0);
ValueListenable<double> get dbListenable => amplitudeDbListenable;

StreamSubscription<Amplitude>? _amplitudeSub;
```

改动点:

- `start()`: 在 `_recorder.start(...)` 之后订阅 `_recorder.onAmplitudeChanged(Duration(milliseconds: 200))`,把 amplitude 映射到 dBFS 并更新 notifier
- `pause()` / `stop()` / `discard()`: 取消订阅,notifier 重置为 -60
- `dispose()`: 取消订阅
- `_mapAmplitude(double current, double max)`: `20 * log10(current / max)`,钳制到 [-60, 0]

`record` 6.x 的 `Amplitude.current` 单位是分贝(已经是 dBFS)还是相对值需在实现时核实,如果是相对值则要换算。

### 4.4 WaveformView (新增)

`waveform_view.dart`:

```dart
class WaveformView extends StatefulWidget {
  final ValueListenable<double> dbListenable;
  final bool active;            // 是否正在录音
  final Duration elapsed;       // 用于 x 轴比例
  const WaveformView({...});
}

class _WaveformViewState extends State<WaveformView> {
  static const _maxBars = 200;   // 缓冲容量 ≈ 200 像素
  final Queue<double> _dbs = ListQueue(_maxBars);

  @override
  void initState() {
    super.initState();
    widget.dbListenable.addListener(_onDb);
  }

  void _onDb() {
    if (_dbs.length >= _maxBars) _dbs.removeFirst();
    _dbs.add(widget.dbListenable.value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: CustomPaint(
        painter: _WaveformPainter(
          dbs: _dbs.toList(),
          baseColor: ZenColors.sage,
          hotColor: ZenColors.mutedRed,
          centerLine: ZenColors.hair,
        ),
        size: Size.infinite,
      ),
    );
  }
}
```

`_WaveformPainter`:

- 高度 = `size.height`,中心基线 = `size.height / 2`
- 每像素一列(若缓冲 < 宽度,左对齐,右侧空白)
- dBFS → bar 高度: `((db + 60) / 60).clamp(0, 1) * (size.height / 2 - 4)`,平方一下让它更有视觉冲击(`pow(barHeight, 0.7)`)
- 中心线 `+0/-0` 用 `ZenColors.hair` 画 1px 横线
- 当前 bar 颜色:`-3 dBFS 以上 = mutedRed`,否则 `ZenColors.sage`
- 暂停态(用 `widget.active` 控制):保留最后一帧,不更新

### 4.5 LevelMeterView (新增,放在 waveform_view.dart)

水平电平条,放在 WaveformView 下面:

```dart
class LevelMeterView extends StatelessWidget {
  final ValueListenable<double> dbListenable;
  final bool active;
  const LevelMeterView({...});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dbListenable,
      builder: (context, _) {
        final db = dbListenable.value;
        final ratio = ((db + 60) / 60).clamp(0.0, 1.0);
        return Row(
          children: [
            const Text('L', style: ZenText.monoDigitSmall),
            const SizedBox(width: 6),
            Expanded(
              child: _MeterStrip(ratio: ratio),
            ),
            const SizedBox(width: 6),
            const Text('R', style: ZenText.monoDigitSmall),
            const SizedBox(width: 12),
            SizedBox(
              width: 60,
              child: Text(
                '${db.toStringAsFixed(1)} dB',
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
```

`_MeterStrip` 是 16 个 `ZenDot`(active=true 即填充),颜色按位置分段:0-10 sage,11-13 浅黄,14-15 mutedRed。当前活跃段由 `ratio * 16` 决定。

由于目前录音是 mono,L/R 渲染同一条;扩展性 hook 留好,后续 stereo 直接传两个 dbListenable。

### 4.6 RecorderPageScaffold 视觉重构

```
zenPageScaffold(
  title: '录音机',
  actions: [ZenIconButton(icon: library_music, onTap: → list)],
  body: SingleChildScrollView(
    Padding 24/16,
    Column [
      ZenSection(title: '工程信息', child: monoDigitSmall 显示 AAC LC · 44.1kHz · 128kbps · MONO),
      SizedBox 16,
      ZenCard (140 高) → WaveformView,
      SizedBox 12,
      ZenCard (44 高) → LevelMeterView,
      SizedBox 16,
      Center(monoDigitLarge 显示 00:23),
      SizedBox 24,
      Row(spacing: 24, mainAxisAlignment: center, [
        ZenIconButton.outline(icon: pause/stop/play_arrow, onTap, 48×48),
        SizedBox 24,
        ZenIconButton.hero(icon: fiber_manual_record/fiber_manual_record_outlined, onTap, 80×80),
      ]),
      if (state == paused) ... 显示「暂停中」状态 (ZenDot 灭 + monoDigitSmall),
      SizedBox 16,
      _LastRecordingCard → 改 zenCard + monoDigitSmall,
      SizedBox 16,
      _PermissionBanner → 改 ZenEmptyState(action: 授权),
    ],
  ),
)
```

具体颜色替换:

| 当前位置 | 替换 |
|---|---|
| `Colors.redAccent` | `ZenColors.mutedRed` |
| `Colors.orange` / `Colors.orange.shade50/300/900` | `ZenColors.mutedRed` 系列(浅 bg +10% alpha) |
| `Colors.green` | `ZenColors.sage` |
| `Colors.grey` | `ZenColors.secondary` |
| `Colors.grey.shade600` | `ZenColors.secondary` |
| `TextStyle(fontSize:56, FontWeight.w300)` | `ZenText.monoDigitLarge` 显式 color = `ZenColors.ink` |
| `_format(duration)` 本地实现 | `formatTime(duration.inSeconds)` |
| `_fmtDate(date)` 本地实现 | 保留(zen_theme 里没有 date formatter,新加进 zen_theme 供其他模块复用) |

**暂停段标记**: v1 不做。RecorderController 不暴露 `pauseMarkers`,UI 仅在 paused 状态用 `ZenDot(off)` + "暂停中" 文字表达。完整段标记留给后续 spec。

### 4.7 RecorderListPage 视觉重构

- `Scaffold` → `zenPageScaffold(title: '录音列表', actions: [↻])`
- `Card` → `Container(decoration: zenCard())`
- `ListTile.leading IconButton(play/edit/delete)` → `ZenIconButton.tint` 三连
- 空态 `_EmptyState` → `ZenEmptyState(Icons.mic_none, '还没有录音', actionLabel: '刷新', onAction: _load)`
- 删除/重命名对话框 → `ZenConfirmDialog` + TextField

### 4.8 native_media_page.dart 录音区升级

定位: 这是测试页的录音区,**保留 AudioRecordingService** 作为测试夹具(职责与 RecorderController 不同:它只关心"录一段、播一段",不关心落盘到 recordings/ 列表)。

改动:
- 录音按钮组改为 `ZenIconButton`(48×48): mic(开始) / stop(停止)
- 时长显示用 `ZenText.monoDigit`
- 测试结果用 `zenCard`
- 不画真波形(测试页不必要,且 AudioRecordingService 不暴露 amplitude)

---

## 5. 数据流

录音启动后:

```
AudioRecorder.onAmplitudeChanged (20Hz native)
  → RecorderController._onAmplitude(double amp)
  → _mapAmplitude(amp) → dBFS
  → amplitudeDbListenable.value = dBFS
  → WaveformView (订阅 notifier) → 更新 _dbs 队列 → setState
  → LevelMeterView (订阅 notifier) → AnimatedBuilder
```

`dbListenable` 是 `ValueListenable<double>`,`WaveformView` 内部用 `addListener`(因为它需要 history 缓冲),`LevelMeterView` 用 `AnimatedBuilder`(它只关心当前值)。

---

## 6. 错误处理

- `AudioRecorder.onAmplitudeChanged` stream 出错: `cancel + emit error`,不影响主状态机
- `dispose` 后 stream 仍吐值: `_safeNotifyAmplitude()` 守门,已 dispose 则丢弃
- 权限被拒: 改用 `ZenEmptyState`,action 按钮调 `controller.ensurePermission()`,文案沿用现有 i18n(`RecorderUiText.requestPermission` / `permissionDeniedHint`)
- 用户关闭麦克风硬件权限: 走 `errorNotifier`,SnackBar 文本不变

---

## 7. 测试

新增:

- `test/lab/demos/recorder/waveform_painter_test.dart`:
  - 给定 `dbs: [-60, -30, 0]` 三段缓冲,绘制出 3 列 bar
  - 验证第一列(基线)和第三列(全幅)的高度
  - 验证 -3 dBFS 以上的 bar 颜色为 `mutedRed`

- `test/lab/demos/recorder/level_meter_test.dart`:
  - 给定 `db: -10`,计算 `ratio = 0.833`,期望 active 段数 = 13

更新:

- `recorder_controller_test.dart`:
  - amplitude mock 注入:模拟 `Amplitude(-30, -30)` → dBFS = -30
  - 验证 `_safeNotifyAmplitude` 在 dispose 后是 noop

现有:

- `audio_recording_service_test.dart` 不动(职责不同)

---

## 8. 兼容性 / 不破坏现有 API

`RecorderController` 公开 API 不变:

```dart
// 这些全部保留
Future<bool> start()
Future<void> pause()
Future<void> resume()
Future<String?> stop()
Future<void> discard()
String? commitSave()
Future<List<RecordingFile>> listRecordings()
Future<String?> renameRecording(String, String)
Future<bool> deleteRecording(String)
Future<void> playFile(String)
Future<void> stopPlayback()

// 这些全部保留
ValueListenable<Duration> get tickListenable
ValueNotifier<String?> errorNotifier
RecorderState get state
Duration get elapsed
String? get currentFilePath
String? get lastSavedPath
int get lastFileSize
RecorderPermissionStatus get permissionStatus
String? get playingPath

// 新增
ValueListenable<double> get dbListenable
```

`recorder_page.dart` 公开的 `recorderPageKey` / `markRecorderAutoStart` / `recorderAutoStartPending` / `consumeRecorderAutoStart` 全部不动。

`recorder_demo.dart` 不动。Android widget 不动。

---

## 9. 实施顺序(供 writing-plans 拆任务)

1. **基础设施**: Controller 加 `dbListenable` + stream 订阅,加测试
2. **WaveformView / LevelMeterView**: 纯 widget,带 painter 测试
3. **RecorderPageScaffold**: 用 zen 重写,替换所有颜色,接 WaveformView / LevelMeterView
4. **RecorderListPage**: zenCard + ZenIconButton + ZenEmptyState
5. **native_media_page 录音区**: zen 化
6. **回归**: 编译,跑现有测试,手动跑 Android 模拟器看录音/暂停/保存/播放流程

---

## 10. 风险与权衡

| 风险 | 缓解 |
|---|---|
| `record` 6.x 的 `Amplitude` 单位不确定(dBFS 还是 raw) | 实现时先实测;若 raw 则换算 `20 * log10(amp / 1.0)` |
| 真波形 200Hz native stream → 20Hz 抽样,主线程 setState 频率 | 抽样间隔 200ms,只在 waveform view 内 setState,不通知 controller |
| Android emulator 没有麦克风 → 波形恒为 -60 | 接受(用户能看到电平表不跳动,能感知"没声音输入") |
| iOS / Web 当前不验证 | iOS record 插件同样支持 onAmplitudeChanged;Web 不支持(`audio_recording_service.dart` 注释了 web fallback),由调用方决定 |
| 列表页 zen 化会破坏 Material 默认 long-press / ripple | 用 `zenCard` 自带的 hair border + InkWell 自定义 ripple |

---

## 12. 依赖

**0 个新增依赖**。所需能力全部已在 `pubspec.yaml` 中:

| 能力 | 来源 | 现有版本 |
|---|---|---|
| 真波形绘制 | `flutter` 内置 `CustomPainter` + `Canvas` | sdk |
| 实时电平表 | `record` 自带 `onAmplitudeChanged` stream | `record: ^6.0.0` |
| dBFS 计算 | `dart:math` `log10` | sdk |
| 音频播放 | `just_audio` | `^0.9.40` |
| 麦克风权限 | `permission_handler` | `^11.4.0` |
| 主题/卡片/圆角 | `lib/widgets/theme/zen_theme.dart` | 项目内置 |

**明确不引入** 的包:

- ❌ `flutter_audio_visualizer` —— 与 zen 主题难以对齐
- ❌ `pcm_stream` —— 只需幅度包络,不需要原始 PCM 缓冲
- ❌ 任何频谱/FFT 包 —— v1 不画频谱图

**唯一待核实**: `record` 6.x 的 `Amplitude.current` 是 dBFS 还是 raw(0~1)。在 `_mapAmplitude` 实现时实测 5 分钟,不影响依赖列表。
