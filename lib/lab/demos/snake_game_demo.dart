import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
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
  int _noOfRow = 20;
  int _noOfColumn = 12;
  List<int> _borderList = [];
  List<int> _snakePosition = [];
  int _snakeHead = 0;
  int _score = 0;
  late int _foodPosition;
  late FocusNode _focusNode;
  late Direction _direction;
  Timer? _gameTimer;
  bool _isGameOver = false;

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
      _isGameOver = false;
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
        setState(() {
          _isGameOver = true;
        });
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
    } while (
      (_borderList.contains(_foodPosition) || _snakePosition.contains(_foodPosition))
      && attempts < 100
    );
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

  void _handleSwipe(PointerScrollEvent event) {
    final dy = event.scrollDelta.dy;
    final dx = event.scrollDelta.dx;

    if (dy.abs() > dx.abs()) {
      // 垂直滑动
      if (dy < 0 && _direction != Direction.down) {
        _direction = Direction.up;
      } else if (dy > 0 && _direction != Direction.up) {
        _direction = Direction.down;
      }
    } else {
      // 水平滑动
      if (dx < 0 && _direction != Direction.right) {
        _direction = Direction.left;
      } else if (dx > 0 && _direction != Direction.left) {
        _direction = Direction.right;
      }
    }
  }

  void _handleSwipeFromGesture(DragEndDetails details) {
    // 这个方法保留用于可能的滑动手势
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  // 游戏区域
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _noOfRow * _noOfColumn,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _noOfColumn,
                          ),
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.all(0.5),
                              color: _boxFillColor(index),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // 方向控制按钮
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 向上按钮
                          _DirectionButton(
                            icon: Icons.arrow_upward,
                            onTap: () {
                              if (_direction != Direction.down) {
                                _direction = Direction.up;
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          // 下一行：左、向下、右
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _DirectionButton(
                                icon: Icons.arrow_back,
                                onTap: () {
                                  if (_direction != Direction.right) {
                                    _direction = Direction.left;
                                  }
                                },
                              ),
                              _DirectionButton(
                                icon: Icons.arrow_downward,
                                onTap: () {
                                  if (_direction != Direction.up) {
                                    _direction = Direction.down;
                                  }
                                },
                              ),
                              _DirectionButton(
                                icon: Icons.arrow_forward,
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
    for (int i = _noOfColumn - 1; i < _noOfRow * _noOfColumn; i += _noOfColumn) {
      _borderList.add(i);
    }
    for (int i = (_noOfRow * _noOfColumn) - _noOfColumn; i < _noOfRow * _noOfColumn; i++) {
      _borderList.add(i);
    }
  }
}

class _ControlHint extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ControlHint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

/// 方向控制按钮
class _DirectionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _DirectionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }
}

void registerSnakeGameDemo() {
  demoRegistry.register(SnakeGameDemo());
}
