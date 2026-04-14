import 'dart:math';
import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 2048 游戏 Demo
class Game2048Demo extends DemoPage {
  @override
  String get title => '2048';

  @override
  String get description => '经典数字益智游戏';

  @override
  Widget buildPage(BuildContext context) {
    return const _Game2048Page();
  }
}

class _Game2048Page extends StatefulWidget {
  const _Game2048Page();

  @override
  State<_Game2048Page> createState() => _Game2048PageState();
}

class _Game2048PageState extends State<_Game2048Page> {
  List<List<int>> _board = [];
  int _score = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  bool _won = false;

  static const int size = 4;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  void _initGame() {
    _board = List.generate(size, (_) => List.filled(size, 0));
    _score = 0;
    _gameOver = false;
    _won = false;
    _addRandomTile();
    _addRandomTile();
  }

  void _addRandomTile() {
    List<(int, int)> empty = [];
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        if (_board[i][j] == 0) {
          empty.add((i, j));
        }
      }
    }
    if (empty.isEmpty) return;

    final (r, c) = empty[Random().nextInt(empty.length)];
    _board[r][c] = Random().nextInt(10) < 9 ? 2 : 4;
  }

  bool _moveLeft() {
    bool moved = false;
    for (int i = 0; i < size; i++) {
      List<int> row = _board[i].where((e) => e != 0).toList();
      List<int> newRow = [];

      for (int j = 0; j < row.length; j++) {
        if (j + 1 < row.length && row[j] == row[j + 1]) {
          newRow.add(row[j] * 2);
          _score += row[j] * 2;
          j++;
        } else {
          newRow.add(row[j]);
        }
      }

      while (newRow.length < size) {
        newRow.add(0);
      }

      for (int j = 0; j < size; j++) {
        if (_board[i][j] != newRow[j]) {
          moved = true;
          _board[i][j] = newRow[j];
        }
      }
    }
    return moved;
  }

  bool _moveRight() {
    bool moved = false;
    for (int i = 0; i < size; i++) {
      List<int> row = _board[i].where((e) => e != 0).toList();
      List<int> newRow = [];

      for (int j = row.length - 1; j >= 0; j--) {
        if (j - 1 >= 0 && row[j] == row[j - 1]) {
          newRow.insert(0, row[j] * 2);
          _score += row[j] * 2;
          j--;
        } else {
          newRow.insert(0, row[j]);
        }
      }

      while (newRow.length < size) {
        newRow.insert(0, 0);
      }

      for (int j = 0; j < size; j++) {
        if (_board[i][j] != newRow[j]) {
          moved = true;
          _board[i][j] = newRow[j];
        }
      }
    }
    return moved;
  }

  bool _moveUp() {
    bool moved = false;
    for (int j = 0; j < size; j++) {
      List<int> col = [];
      for (int i = 0; i < size; i++) {
        if (_board[i][j] != 0) col.add(_board[i][j]);
      }

      List<int> newCol = [];
      for (int i = 0; i < col.length; i++) {
        if (i + 1 < col.length && col[i] == col[i + 1]) {
          newCol.add(col[i] * 2);
          _score += col[i] * 2;
          i++;
        } else {
          newCol.add(col[i]);
        }
      }

      while (newCol.length < size) {
        newCol.add(0);
      }

      for (int i = 0; i < size; i++) {
        if (_board[i][j] != newCol[i]) {
          moved = true;
          _board[i][j] = newCol[i];
        }
      }
    }
    return moved;
  }

  bool _moveDown() {
    bool moved = false;
    for (int j = 0; j < size; j++) {
      List<int> col = [];
      for (int i = 0; i < size; i++) {
        if (_board[i][j] != 0) col.add(_board[i][j]);
      }

      List<int> newCol = [];
      for (int i = col.length - 1; i >= 0; i--) {
        if (i - 1 >= 0 && col[i] == col[i - 1]) {
          newCol.insert(0, col[i] * 2);
          _score += col[i] * 2;
          i--;
        } else {
          newCol.insert(0, col[i]);
        }
      }

      while (newCol.length < size) {
        newCol.insert(0, 0);
      }

      for (int i = 0; i < size; i++) {
        if (_board[i][j] != newCol[i]) {
          moved = true;
          _board[i][j] = newCol[i];
        }
      }
    }
    return moved;
  }

  void _handleMove(String direction) {
    if (_gameOver || _won) return;

    bool moved = false;
    switch (direction) {
      case 'left':
        moved = _moveLeft();
        break;
      case 'right':
        moved = _moveRight();
        break;
      case 'up':
        moved = _moveUp();
        break;
      case 'down':
        moved = _moveDown();
        break;
    }

    if (moved) {
      setState(() {
        _addRandomTile();
        _checkWin();
        _checkGameOver();
      });
    }
  }

  void _checkWin() {
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        if (_board[i][j] == 2048) {
          _won = true;
        }
      }
    }
  }

  void _checkGameOver() {
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        if (_board[i][j] == 0) return;
        if (i + 1 < size && _board[i][j] == _board[i + 1][j]) return;
        if (j + 1 < size && _board[i][j] == _board[i][j + 1]) return;
      }
    }
    _gameOver = true;
  }

  Color _getTileColor(int value) {
    switch (value) {
      case 0:
        return const Color(0xFFCDC1B4);
      case 2:
        return const Color(0xFFEEE4DA);
      case 4:
        return const Color(0xFFEDE0C8);
      case 8:
        return const Color(0xFFF2B179);
      case 16:
        return const Color(0xFFF59563);
      case 32:
        return const Color(0xFFF67C5F);
      case 64:
        return const Color(0xFFF65E3B);
      case 128:
        return const Color(0xFFEDCF72);
      case 256:
        return const Color(0xFFEDCC61);
      case 512:
        return const Color(0xFFEDC850);
      case 1024:
        return const Color(0xFFEDC53F);
      case 2048:
        return const Color(0xFFEDC22E);
      default:
        return const Color(0xFF3C3A32);
    }
  }

  Color _getTextColor(int value) {
    return value <= 4 ? const Color(0xFF776E65) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8EF),
      body: SafeArea(
        child: Column(
          children: [
            // 头部
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '2048',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF776E65),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildScoreBox('SCORE', _score),
                      const SizedBox(height: 4),
                      _buildScoreBox('BEST', _bestScore),
                    ],
                  ),
                ],
              ),
            ),
            // 游戏说明
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '合并数字，达到 2048!',
                    style: TextStyle(fontSize: 14, color: Color(0xFF776E65)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _bestScore = max(_bestScore, _score);
                        _initGame();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8F7A66),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('新游戏'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 游戏面板
            Expanded(
              child: Center(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! > 0) {
                        _handleMove('right');
                      } else {
                        _handleMove('left');
                      }
                    }
                  },
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! > 0) {
                        _handleMove('down');
                      } else {
                        _handleMove('up');
                      }
                    }
                  },
                  child: Container(
                    width: MediaQuery.of(context).size.width - 48,
                    height: MediaQuery.of(context).size.width - 48,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFBBADA0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: size,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: size * size,
                      itemBuilder: (context, index) {
                        int row = index ~/ size;
                        int col = index % size;
                        int value = _board[row][col];
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          decoration: BoxDecoration(
                            color: _getTileColor(value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: value > 0
                                ? Text(
                                    '$value',
                                    style: TextStyle(
                                      fontSize: value < 100
                                          ? 32
                                          : (value < 1000 ? 28 : 20),
                                      fontWeight: FontWeight.bold,
                                      color: _getTextColor(value),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 游戏结束/胜利提示
            if (_gameOver || _won)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _won ? '🎉 你赢了!' : '💀 游戏结束',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBox(String label, int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFBBADA0),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFEEE4DA),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

void registerGame2048Demo() {
  demoRegistry.register(Game2048Demo());
}
