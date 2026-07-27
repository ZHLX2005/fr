# MateusNavarro77 metronome — Bloc 状态管理与 Tap Tempo 算法

> 来源仓库: `.claude/repo/metronome-MateusNavarro77/lib/blocs/metronome/`

## 1. 事件/状态/Bloc 三件套定义

事件 (`lib/blocs/metronome/metronome_event.dart`):

```dart
// 来源: lib/blocs/metronome/metronome_event.dart:1-39
sealed class MetronomeEvent {
  const MetronomeEvent();
}
class MetronomePaused extends MetronomeEvent {}
class MetronomePlayed extends MetronomeEvent {}
class MetronomeBpmChanged extends MetronomeEvent {
  final int bpm;
  MetronomeBpmChanged({required this.bpm});
}
class MetronomeTicked extends MetronomeEvent {
  final Tick tick;
  MetronomeTicked({required this.tick});
}
class MetronomeBpmIncremented extends MetronomeEvent {}
class MetronomeBpmDecremented extends MetronomeEvent {}
class MetronomeAccentFirstBeatToggled extends MetronomeEvent {}
class MetronomeBeatsPerBarChanged extends MetronomeEvent {
  final int beatsPerBar;
  MetronomeBeatsPerBarChanged({required this.beatsPerBar});
}
class MetronomeTapped extends MetronomeEvent {}
```

使用 `sealed class` 模式 — Dart 3 模式匹配友好,event 子类穷举,编译期保证。

状态 (`lib/blocs/metronome/metronome_state.dart`):

```dart
// 来源: lib/blocs/metronome/metronome_state.dart:1-33
final class MetronomeState {
  final int bpm;
  final Tick? tick;
  final bool isRunning;
  final bool accentOnFirstBeat;
  final int beatsPerBar;

  const MetronomeState({
    required this.bpm,
    this.tick,
    required this.isRunning,
    required this.accentOnFirstBeat,
    required this.beatsPerBar,
  });

  MetronomeState copyWith({
    int? bpm, Tick? tick, bool? isRunning,
    bool? accentOnFirstBeat, int? beatsPerBar,
  }) {
    return MetronomeState(
      bpm: bpm ?? this.bpm,
      tick: tick ?? this.tick,
      isRunning: isRunning ?? this.isRunning,
      accentOnFirstBeat: accentOnFirstBeat ?? this.accentOnFirstBeat,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
    );
  }
}
```

`tick` 是可选 + 每次都重置 — 让 UI 可以在 tick 变化时重新构建。

## 2. Bloc 构造与初始状态

`lib/blocs/metronome/metronome_bloc.dart:16-25`:

```dart
MetronomeBloc({required Metronome metronome})
  : _metronome = metronome,
    super(
      MetronomeState(
        bpm: metronome.bpm,
        isRunning: metronome.isRunning,
        accentOnFirstBeat: false,
        beatsPerBar: metronome.beatsPerBar,
      ),
    ) {
```

从 domain 接口读取初始 BPM 与 beatsPerBar,`accentOnFirstBeat` 默认 `false`。

## 3. Tick 流订阅

```dart
// 来源: lib/blocs/metronome/metronome_bloc.dart:26-31
_tickStreamSub = _metronome.tickStream().listen((tick) {
  add(MetronomeTicked(tick: tick));
});
on<MetronomeTicked>((event, emit) {
  emit(state.copyWith(tick: event.tick));
});
```

设计要点:
- Native 回调 → `StreamController<Tick>` → `listen` → `Bloc.add(MetronomeTicked)` → 状态更新 → UI 重建
- 通过 `Bloc` 事件系统间接传递 tick,而不是直接调用 `setState`,保证状态来源单一

## 4. Tap Tempo 算法 — 滑动窗口

五次敲击节拍 + 时间窗,`lib/blocs/metronome/metronome_bloc.dart:36-61`:

```dart
// 来源: lib/blocs/metronome/metronome_bloc.dart:36-61
on<MetronomeTapped>((event, emit) {
  final now = DateTime.now();
  if (_tapTimes.isNotEmpty &&
      now.difference(_tapTimes.last).inSeconds >= 2) {
    _tapTimes.clear();
  }
  _tapTimes.add(now);

  if (_tapTimes.length > 5) {
    _tapTimes.removeAt(0);
  }

  if (_tapTimes.length == 5) {
    final totalDuration =
        _tapTimes.last.difference(_tapTimes.first).inMilliseconds;
    final averageIntervalMs = totalDuration / 4;
    final calculatedBpm = (60000 / averageIntervalMs).round();

    final clampedBpm = calculatedBpm.clamp(kMinBpm, kMaxBpm);

    if (_isValidBpmRange(clampedBpm)) {
      _metronome.setBpm(clampedBpm);
      emit(state.copyWith(bpm: clampedBpm));
    }
  }
});
```

**算法说明**:
1. 每次 `MetronomeTapped` 记录一个 `DateTime.now()`
2. 如果上次与本次间隔 > 2 秒 → 清空重置(避免历史干扰)
3. 滑动窗口:队列上限 5 个时间戳
4. 仅当累积到 5 次敲击才计算 BPM
5. 算法:总跨度 `(last - first).inMilliseconds` / 4 段间隔 → 平均 ms → `60000 / avgMs` → 四舍五入
6. 应用 `clamp(kMinBpm, kMaxBpm)` 边界限制

`_isValidBpmRange`(`metronome_bloc.dart:103-105`):

```dart
bool _isValidBpmRange(int bpm) {
  return kMinBpm <= bpm && bpm <= kMaxBpm;
}
```

`kMinBpm = 10`,`kMaxBpm = 350`(`lib/shared/constants.dart:1-2`)。

## 5. Play/Pause 事件处理

```dart
// 来源: lib/blocs/metronome/metronome_bloc.dart:32-35
on<MetronomePlayed>((event, emit) async {
  emit(state.copyWith(isRunning: true));
  await _metronome.start();
});

// metronome_bloc.dart:62-65
on<MetronomePaused>((event, emit) {
  _metronome.stop();
  emit(state.copyWith(isRunning: _metronome.isRunning));
});
```

注意 Play 是先 `emit(state.copyWith(isRunning: true))` 再 `await _metronome.start()`,把"UI 立即响应"与"音频引擎启动"两个动作解耦(后者可能稍耗时)。

Pause 则使用 `Metronome.isRunning` 的实际返回值(避免状态与实际不一致)。

## 6. BPM 控制三事件

```dart
// 来源: lib/blocs/metronome/metronome_bloc.dart:66-86
on<MetronomeBpmChanged>((event, emit) {
  if (_isValidBpmRange(event.bpm)) {
    _metronome.setBpm(event.bpm);
    emit(state.copyWith(bpm: event.bpm));
  }
});
on<MetronomeBpmIncremented>((event, emit) {
  final nextBpm = _metronome.bpm + 1;
  if (_isValidBpmRange(nextBpm)) {
    _metronome.setBpm(nextBpm);
    emit(state.copyWith(bpm: nextBpm));
  }
});
on<MetronomeBpmDecremented>((event, emit) {
  final nextBpm = _metronome.bpm - 1;
  if (_isValidBpmRange(nextBpm)) {
    _metronome.setBpm(nextBpm);
    emit(state.copyWith(bpm: nextBpm));
  }
});
```

三种入口(滑块/加减按钮/Tap Tempo),内部统一走 `_metronome.setBpm()`,UI 通过 `BlocBuilder` 实时刷新。

## 7. 资源清理

```dart
// 来源: lib/blocs/metronome/metronome_bloc.dart:97-101
@override
Future<void> close() {
  _tickStreamSub.cancel();
  return super.close();
}
```

Bloc 销毁时取消 Tick 订阅,防止内存泄漏。

## 8. UI 与 Bloc 的接线 — `HomePage`

`lib/view/pages/home_page.dart:23-44`:

```dart
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late StreamSubscription<MetronomeState> sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      sub = context
          .read<MetronomeBloc>()
          .stream
          .distinct((previous, next) => previous.isRunning == next.isRunning)
          .listen((event) {
            debugPrint('isRunning: ${event.isRunning}');
            if (event.isRunning) {
              WakelockPlus.enable();
            } else {
              WakelockPlus.disable();
            }
          });
    });
  }
```

**特征**:
- `WidgetsBindingObserver` 监听 app lifecycle
- `distinct` 仅在 `isRunning` 变化时回调,避免重复开关 wakelock
- 后台态自动暂停 `home_page.dart:53-59`:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  if (state == AppLifecycleState.paused) {
    context.read<MetronomeBloc>().add(MetronomePaused());
  }
}
```

`MeasureBar` 的 `BlocBuilder` 用 `buildWhen` 精确控制重建时机(`home_page.dart:75-87`):

```dart
BlocBuilder<MetronomeBloc, MetronomeState>(
  buildWhen: (previous, current) =>
      previous.tick?.barIndex != current.tick?.barIndex ||
      previous.beatsPerBar != current.beatsPerBar,
  builder: (context, state) {
    return MeasureBar(
      notesPerMeasure: state.beatsPerBar,
      currentIndex: state.tick?.barIndex,
    );
  },
),
```

只在节拍序号或每拍数变化时重建,降低重建次数。

## 9. 节拍指示器组件

`lib/view/widgets/measure_bar.dart:21-57`:

```dart
return Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: List.generate(notesPerMeasure, (index) {
    final isActive = currentIndex != null && currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: isActive ? _dotSize + 2 : _dotSize,
        width:  isActive ? _dotSize + 2 : _dotSize,
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          boxShadow: isActive
              ? [BoxShadow(color: colorScheme.primary.withValues(alpha: 0.6),
                            blurRadius: 14, spreadRadius: 2)]
              : null,
        ),
      ),
    );
  }),
);
```

设计要点:
- `AnimatedContainer`(120ms 过渡)平滑切换视觉态
- 当前拍圆点带 neon glow `BoxShadow`(blurRadius 14, spreadRadius 2)
- 大小变化:激活 +2 像素

## 10. 关键设计要点

| 设计点 | 实现 |
|--------|------|
| 状态来源 | Domain 接口 (`Metronome`) 所有 mutation 集中入口 |
| Tap Tempo | 滑动窗口 5 次敲击,2 秒超时重置 |
| BPM 边界 | `kMinBpm=10`, `kMaxBpm=350` 强校验 |
| UI 性能 | Bloc `buildWhen` 精确控制重建 |
| 生命周期 | `WidgetsBindingObserver` 自动暂停 |
| 屏幕常亮 | `WakelockPlus.enable()` 仅在播放时 |
