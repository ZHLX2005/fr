import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';

/// 贪吃蛇游戏 Demo
class SnakeGameDemo extends DemoPage {
  @override
  String get title => '贪吃蛇';

  @override
  String get description => '经典贪吃蛇游戏';

  @override
  Widget buildPage(BuildContext context) {
    return const _SnakeGamePage();
  }
}

enum Direction { up, down, left, right }

class _SnakeGamePage extends StatefulWidget {
  const _SnakeGamePage();

  @override
  State<_SnakeGamePage> createState() => _SnakeGamePageState();
}

class _SnakeGamePageState extends State<_SnakeGamePage> {
  static const int _noOfRow = 20;
  static const int _noOfColumn = 12;
  List<int> _borderList = [];
  List<int> _snakePosition = [];
  int _snakeHead = 0;
  int _score = 0;
  late int _foodPosition;
  late FocusNode _focusNode;
  late Direction _direction;
  Timer? _gameTimer;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _startGame();
  }

  void _startGame() {
    _gameTimer?.cancel();
    setState(() {
      _score = 0;
      _makeBorder();
      _generateFood();
      _direction = Direction.right;
      _snakePosition = [14, 13, 12];
      _snakeHead = _snakePosition.first;
    });

    _gameTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      _updateSnake();
      if (_checkCollision()) {
        timer.cancel();
      }
    });
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('游戏结束'),
        content: Text(
          '最终得分: $_score',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.green,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startGame();
            },
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
  }

  bool _checkCollision() {
    if (_borderList.contains(_snakeHead)) return true;
    if (_snakePosition.sublist(1).contains(_snakeHead)) return true;
    return false;
  }

  void _generateFood() {
    // 使用循环而非递归，避免栈溢出
    int attempts = 0;
    do {
      _foodPosition = Random().nextInt(_noOfRow * _noOfColumn);
      attempts++;
    } while ((_borderList.contains(_foodPosition) ||
            _snakePosition.contains(_foodPosition)) &&
        attempts < 100);
  }

  void _updateSnake() {
    // 先计算新的头部位置
    int newHead;
    switch (_direction) {
      case Direction.up:
        newHead = _snakeHead - _noOfColumn;
        break;
      case Direction.down:
        newHead = _snakeHead + _noOfColumn;
        break;
      case Direction.right:
        newHead = _snakeHead + 1;
        break;
      case Direction.left:
        newHead = _snakeHead - 1;
        break;
    }

    // 检查是否吃到食物（在移动之前检查）
    bool ateFood = (newHead == _foodPosition);

    setState(() {
      _snakePosition.insert(0, newHead);

      if (ateFood) {
        _score++;
        // 先生成新食物，再移除尾巴（蛇变长）
        _generateFood();
      } else {
        _snakePosition.removeLast();
      }
      _snakeHead = _snakePosition.first;
    });

    if (_checkCollision()) {
      _gameTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showGameOverDialog();
        }
      });
    }
  }

  void _handleKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.keyW:
          if (_direction != Direction.down) _direction = Direction.up;
          break;
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.keyS:
          if (_direction != Direction.up) _direction = Direction.down;
          break;
        case LogicalKeyboardKey.arrowLeft:
        case LogicalKeyboardKey.keyA:
          if (_direction != Direction.right) _direction = Direction.left;
          break;
        case LogicalKeyboardKey.arrowRight:
        case LogicalKeyboardKey.keyD:
          if (_direction != Direction.left) _direction = Direction.right;
          break;
      }
    }
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: _handleKey,
        autofocus: true,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '贪吃蛇',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '得分: $_score',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _startGame,
                        tooltip: '重新开始',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 游戏区域和方向控制
            Expanded(
              child: Column(
                children: [
                  // 游戏区域 - 自适应尺寸
                  Expanded(
                    flex: 3,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 计算每个格子的大小，确保正方形且适应容器
                        final availableWidth =
                            constraints.maxWidth - 32; // 减去左右margin
                        final availableHeight =
                            constraints.maxHeight - 32; // 减去上下margin
                        final cellSize =
                            (availableWidth / _noOfColumn <
                                availableHeight / _noOfRow)
                            ? availableWidth / _noOfColumn
                            : availableHeight / _noOfRow;
                        final actualCellSize = cellSize.clamp(
                          8.0,
                          20.0,
                        ); // 限制大小范围

                        return Container(
                          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: actualCellSize * _noOfColumn,
                              height: actualCellSize * _noOfRow,
                              child: GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _noOfRow * _noOfColumn,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: _noOfColumn,
                                    ),
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: EdgeInsets.all(
                                      actualCellSize * 0.05,
                                    ),
                                    color: _boxFillColor(index),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 方向控制按钮 - 放大版本
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 向上按钮
                          _DirectionButton(
                            icon: Icons.arrow_upward,
                            size: 72,
                            onTap: () {
                              if (_direction != Direction.down) {
                                _direction = Direction.up;
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          // 下一行：左、向下、右
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _DirectionButton(
                                icon: Icons.arrow_back,
                                size: 72,
                                onTap: () {
                                  if (_direction != Direction.right) {
                                    _direction = Direction.left;
                                  }
                                },
                              ),
                              _DirectionButton(
                                icon: Icons.arrow_downward,
                                size: 72,
                                onTap: () {
                                  if (_direction != Direction.up) {
                                    _direction = Direction.down;
                                  }
                                },
                              ),
                              _DirectionButton(
                                icon: Icons.arrow_forward,
                                size: 72,
                                onTap: () {
                                  if (_direction != Direction.left) {
                                    _direction = Direction.right;
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _boxFillColor(int index) {
    if (_borderList.contains(index)) {
      return Colors.blue;
    } else {
      if (_snakePosition.contains(index)) {
        if (_snakeHead == index) {
          return Colors.green;
        } else {
          return Colors.green.shade300;
        }
      } else {
        if (index == _foodPosition) {
          return Colors.red;
        }
      }
    }
    return Colors.grey.shade200;
  }

  void _makeBorder() {
    _borderList.clear();
    for (int i = 0; i < _noOfColumn; i++) {
      _borderList.add(i);
    }
    for (int i = 0; i < _noOfRow * _noOfColumn; i += _noOfColumn) {
      _borderList.add(i);
    }
    for (
      int i = _noOfColumn - 1;
      i < _noOfRow * _noOfColumn;
      i += _noOfColumn
    ) {
      _borderList.add(i);
    }
    for (
      int i = (_noOfRow * _noOfColumn) - _noOfColumn;
      i < _noOfRow * _noOfColumn;
      i++
    ) {
      _borderList.add(i);
    }
  }
}

/// 方向控制按钮 - 加大版
class _DirectionButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _DirectionButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue.shade600,
      borderRadius: BorderRadius.circular(size / 3),
      elevation: 4,
      shadowColor: Colors.blue.shade200,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 3),
        splashColor: Colors.blue.shade300,
        highlightColor: Colors.blue.shade400,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}

void registerSnakeGameDemo() {
  demoRegistry.register(SnakeGameDemo());
}
