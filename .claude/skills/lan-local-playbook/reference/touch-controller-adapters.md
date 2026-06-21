# TouchController 适配参考

三种 TouchController 工厂在不同模式下的适配。

## 工厂接口

```dart
// mode_factory.dart
abstract class TouchControllerFactory {
  TouchController create();
}
```

## 三种实现

| 模式 | 工厂类 | 行为 |
|------|--------|------|
| Local | `LocalTouchControllerFactory` | 标准 TouchController |
| LAN Host | `LanHostTouchControllerFactory(boardSize)` | y 坐标镜像 |
| LAN Client | `LanClientTouchControllerFactory` | 标准 TouchController |

## Local 模式（标准）

```dart
class LocalTouchControllerFactory implements TouchControllerFactory {
  const LocalTouchControllerFactory();

  TouchController create() => TouchController();
}
```

棋盘不翻转，触摸坐标直接映射。

## LAN Host（y 镜像）

Host 端棋盘 `flipY=true`（整体翻转），触摸需要镜像：

```dart
class LanHostTouchController extends TouchController {
  final double boardSize;

  LanHostTouchController({required this.boardSize});

  Offset _mirror(Offset p) => Offset(p.dx, boardSize - p.dy);

  void handleTouchBegan(Offset localPosition, double cellSize, double distance, ...) {
    super.handleTouchBegan(_mirror(localPosition), cellSize, distance, ...);
  }

  void handleTouchMoved(Offset localPosition, double cellSize, double distance, ...) {
    super.handleTouchMoved(_mirror(localPosition), cellSize, distance, ...);
  }

  void handleTouchEnded(Offset localPosition, double cellSize, double distance, ...) {
    super.handleTouchEnded(_mirror(localPosition), cellSize, distance, ...);
  }
}

class LanHostTouchControllerFactory implements TouchControllerFactory {
  final double boardSize;
  const LanHostTouchControllerFactory({required this.boardSize});

  TouchController create() => LanHostTouchController(boardSize: boardSize);
}
```

**设计理由**：Host 端 `flipY=true` 后，用户触摸"视觉下方"时，引擎里对应的是 top player（因为 top player 从 y=0 出发）。镜像后把屏幕坐标反转回 engine 坐标系，保证 cellId 映射正确。

## LAN Client（标准）

Client 端棋盘不翻转（`flipY=false`），使用标准 TouchController：

```dart
class LanClientTouchControllerFactory implements TouchControllerFactory {
  const LanClientTouchControllerFactory();

  TouchController create() => TouchController();
}
```

## 使用入口

```dart
// Host 游戏页 — 创建带镜像的控制器
final touchController = LanHostTouchControllerFactory(
  boardSize: boardSize,
).create();

// Client 游戏页 / 本地页 — 标准控制器
final touchController = TouchController();
```
