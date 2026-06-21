# 本地模式完整参考

围追堵截项目中本地热座模式的 ViewModel + State + Event 模式。提取自 `lib/core/surround_game/local/`。

## 模式结构

```
Event → dispatch() → reduce(state, event) → newState → UI rebuild
                     ↑                              │
                     └── engine mutation ────────────┘
```

**三要素**：

| 角色 | 文件名 | 职责 |
|------|--------|------|
| State | `local_match_state.dart` | sealed class，枚举所有可能 UI 状态 |
| Event | `local_match_event.dart` | sealed class，枚举所有用户操作 |
| ViewModel | `local_view_model.dart` | `ValueNotifier<State>` + `reduce()` 纯函数 |

## 完整实现参考

### State

```dart
/// 本地模式状态 — sealed class
sealed class LocalMatchState {
  const LocalMatchState();
}

class LocalIdle extends LocalMatchState {
  const LocalIdle();
}

class LocalInGame extends LocalMatchState {
  const LocalInGame(this.gameState);
  final GameState gameState;
}

class LocalFinished extends LocalMatchState {
  const LocalFinished(this.finalState, this.result);
  final GameState finalState;
  final GameResult result;
}

enum GameResult { topWin, bottomWin, draw, abandoned }
```

### Event

```dart
sealed class LocalMatchEvent {
  const LocalMatchEvent();
}

class LocalStartPressed extends LocalMatchEvent {
  const LocalStartPressed();
}

class LocalMoveCommitted extends LocalMatchEvent {
  const LocalMoveCommitted({
    required this.targetCellId,
    this.wallX, this.wallY, this.wallOrientation,
  });
  final int targetCellId;
  final int? wallX, wallY;
  final WallOrientation? wallOrientation;
  bool get isWall => wallX != null && wallY != null && wallOrientation != null;
}

class LocalUndoRequested extends LocalMatchEvent {
  const LocalUndoRequested();
}

class LocalResetRequested extends LocalMatchEvent {
  const LocalResetRequested();
}

class LocalExitRequested extends LocalMatchEvent {
  const LocalExitRequested();
}
```

### ViewModel

```dart
final class LocalViewModel extends ValueNotifier<LocalMatchState> {
  LocalViewModel() : super(const LocalIdle());

  void dispatch(LocalMatchEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) {
      value = next; // 自动触发 ValueNotifier 通知
    }
  }

  LocalMatchState reduce(LocalMatchState s, LocalMatchEvent e) {
    return switch (e) {
      LocalStartPressed() when s is LocalIdle =>
        LocalInGame(QuoridorEngine.initialize()),

      LocalMoveCommitted() when s is LocalInGame =>
        _applyAndCheck(s, e),

      LocalUndoRequested() when s is LocalInGame =>
        _undo(s),

      LocalResetRequested() when s is LocalInGame ||
                                    s is LocalFinished =>
        LocalInGame(QuoridorEngine.initialize()),

      LocalExitRequested() => const LocalIdle(),

      _ => s,
    };
  }

  LocalMatchState _applyAndCheck(LocalInGame s, LocalMoveCommitted e) {
    final GameState? afterAction;
    if (e.isWall) {
      afterAction = QuoridorEngine.placeWall(
        s.gameState, e.wallX!, e.wallY!, e.wallOrientation!,
      );
    } else {
      afterAction = QuoridorEngine.movePiece(s.gameState, e.targetCellId);
    }
    if (afterAction == null) return s; // 非法操作

    final afterSwitch = QuoridorEngine.switchTurn(afterAction);
    if (afterSwitch.status != GameStatus.running) {
      return LocalFinished(afterSwitch, _resultFromStatus(afterSwitch.status));
    }
    return LocalInGame(afterSwitch);
  }

  LocalMatchState _undo(LocalInGame s) {
    final history = s.gameState.history;
    if (history.isEmpty) return s;
    final undone = QuoridorEngine.replayHistory(history, upTo: history.length - 1);
    return LocalInGame(undone);
  }

  static GameResult _resultFromStatus(GameStatus status) => switch (status) {
    GameStatus.topWin => GameResult.topWin,
    GameStatus.bottomWin => GameResult.bottomWin,
    GameStatus.draw => GameResult.draw,
    GameStatus.running => GameResult.abandoned,
  };
}
```

## UI 绑定

```dart
ValueListenableBuilder<LocalMatchState>(
  valueListenable: viewModel,
  builder: (ctx, state, _) {
    return switch (state) {
      LocalIdle() => StartScreen(onStart: () => viewModel.dispatch(const LocalStartPressed())),
      LocalInGame(:final gameState) => GameScreen(gameState: gameState),
      LocalFinished(:final finalState, :final result) => ResultScreen(finalState: finalState, result: result),
    };
  },
);
```

## 设计规则

1. **纯函数 reducer**：`reduce()` 不调 `setState`、不发网络、不读 `DateTime.now()`
2. **引擎返回 null** = 非法操作，reducer 返回原状态
3. **`identical(next, value)`** 避免不必要的通知
4. **ViewModel extends ValueNotifier** — 天然支持 `ValueListenableBuilder`
5. **ViewModel 在 `initState` 创建，`dispose` 释放** — 不要重复创建

## 新游戏适配清单

- [ ] 定义 `xxxMatchState` sealed class（idle / inGame / finished）
- [ ] 定义 `xxxMatchEvent` sealed class（start / move / undo / reset / exit）
- [ ] 实现 `xxxViewModel extends ValueNotifier<XxxMatchState>` + `reduce()` 纯函数
- [ ] 引擎方法返回 null 表示非法操作（不要抛异常）
- [ ] UI 用 `ValueListenableBuilder` 绑定
