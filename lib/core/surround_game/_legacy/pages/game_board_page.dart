import 'package:flutter/material.dart';
import '../../surround_game_constants.dart';
import '../../surround_game_service.dart';
import '../../_legacy/models/game_state.dart';
import '../../_legacy/widgets/game_board_widget.dart';
import '../../_legacy/widgets/direction_pad.dart';

/// 游戏棋盘页面
///
/// 本地双人模式：P1（蓝）用下方方向键，P2（红）用右侧方向键
class GameBoardPage extends StatefulWidget {
  final bool isHost;
  final GameState initialState;
  final String? hostIp;
  final int hostPort;

  const GameBoardPage({
    super.key,
    required this.isHost,
    required this.initialState,
    this.hostIp,
    this.hostPort = 53317,
  });

  @override
  State<GameBoardPage> createState() => _GameBoardPageState();
}

class _GameBoardPageState extends State<GameBoardPage> {
  final _service = surroundGameService;
  late GameState _state;
  bool _isGameOver = false;
  String? _winnerMessage;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;

    _service.gameStateStream.listen((newState) {
      if (!mounted) return;
      setState(() {
        _state = newState;
        if (newState.isGameOver) {
          _isGameOver = true;
          _winnerMessage = newState.winnerId == _service.myDeviceId
              ? '蓝方赢了!'
              : '红方赢了!';
          _showGameOverDialog();
        }
      });
    });
  }

  void _handleP1(Direction dir) {
    if (_isGameOver) return;
    if (widget.isHost) {
      _service.executeMove(hostDir: dir, clientDir: Direction.right);
    } else {
      _service.sendInputToHost(
        widget.hostIp ?? '',
        widget.hostPort,
        dir,
        _state.stepNumber + 1,
      );
    }
  }

  void _handleP2(Direction dir) {
    if (_isGameOver) return;
    _service.executeMove(
      hostDir: Direction.down,
      clientDir: dir,
    );
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_winnerMessage ?? '游戏结束'),
        content: Text(
          '比分: ${_state.hostScore} - ${_state.clientScore}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('返回大厅'),
          ),
        ],
      ),
    );
  }

  /// 退出确认（游戏未结束时）
  Future<bool> _confirmExit() async {
    if (_isGameOver) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出游戏'),
        content: Text('确定要退出吗？当前比分 ${_state.hostScore} - ${_state.clientScore}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _isGameOver,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmExit();
        if (ok && mounted) {
          _service.leaveRoom();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('蓝 ${_state.hostScore}', style: TextStyle(color: Colors.blue)),
            Text('  -  ', style: theme.textTheme.titleMedium),
            Text('${_state.clientScore} 红', style: TextStyle(color: Colors.red)),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isGameOver)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.amber.withValues(alpha: 0.3),
                child: Text(
                  _winnerMessage ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

            // 棋盘
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 72, 4),
                child: GameBoardWidget(state: _state, isHost: widget.isHost),
              ),
            ),

            // 双人方向控制区
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // === P1（蓝方） ===
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('P1 蓝', style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        )),
                        const SizedBox(height: 4),
                        DirectionPad(onDirection: _handleP1, size: 52),
                      ],
                    ),
                  ),

                  // === P2（红方） ===
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('P2 红', style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 13,
                        )),
                        const SizedBox(height: 4),
                        DirectionPad(onDirection: _handleP2, size: 52),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
    );
  }
}
