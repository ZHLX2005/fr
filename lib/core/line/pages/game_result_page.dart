import 'package:flutter/material.dart';
import '../models/game_result.dart';
import '../models/line_models.dart';
import 'line_demo_page.dart';
import 'song_select_page.dart';
import 'line_page.dart';

class GameResultPage extends StatefulWidget {
  final GameResult result;
  final ChartData chart;
  final String? audioPath;

  const GameResultPage({
    super.key,
    required this.result,
    required this.chart,
    this.audioPath,
  });

  @override
  State<GameResultPage> createState() => _GameResultPageState();
}

class _GameResultPageState extends State<GameResultPage>
    with TickerProviderStateMixin {
  late AnimationController _enterController;
  bool _isEntering = true;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _enterController.value = 1.0;
    _enterController.reverse().then((_) {
      if (mounted) setState(() => _isEntering = false);
    });
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  void _goToSongSelect() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SongSelectPage()),
    );
  }

  void _retry() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LineDemo(chart: widget.chart, audioPath: widget.audioPath)
            .buildPage(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // 顶栏：返回 + 重试
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios_new,
                            color: theme.colorScheme.primary, size: 22),
                        onPressed: _goToSongSelect,
                      ),
                      IconButton(
                        icon: Icon(Icons.replay,
                            color: theme.colorScheme.primary, size: 24),
                        onPressed: _retry,
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // 歌名
                Text(
                  result.songName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w200,
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // 等级字母
                _buildGradeLetter(w),
                const SizedBox(height: 8),

                // 准确率
                Text(
                  '${result.accuracy.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: 8),

                // 分数
                Text(
                  '${result.score}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w100,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontFeatures: [const FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
                ),

                const Spacer(),

                // 分隔线
                Container(
                  width: w * 0.4,
                  height: 0.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 20),

                // 判定计数
                _buildJudgeCounts(theme),
                const SizedBox(height: 12),

                // 最高连击
                Text(
                  '最高连击 ${result.maxCombo}x',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(height: 16),

                // 新纪录 / 最高分
                if (result.isNewRecord)
                  Text(
                    '★ 新纪录!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: result.gradeColor(theme.colorScheme.primary).withValues(alpha: 0.7),
                      letterSpacing: 1,
                    ),
                  )
                else
                  Text(
                    '最高分: ${result.highScore}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),

                const Spacer(flex: 3),
              ],
            ),
          ),

          // 水入场动画
          if (_isEntering)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _enterController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: WaterExitPainter(
                      progress: _enterController.value,
                      color: theme.colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGradeLetter(double w) {
    final result = widget.result;
    final grade = result.grade;

    if (grade == 'P') {
      return ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFFff6b9d), Color(0xFFc44dff), Color(0xFF4dc9ff)],
        ).createShader(bounds),
        child: Text(
          grade,
          style: TextStyle(
            fontSize: 96 * w / 750,
            fontWeight: FontWeight.w100,
            color: Colors.white,
            height: 1,
          ),
        ),
      );
    }

    if (grade == 'S') {
      return ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFFffd700), Color(0xFFff8c00)],
        ).createShader(bounds),
        child: Text(
          grade,
          style: TextStyle(
            fontSize: 96 * w / 750,
            fontWeight: FontWeight.w100,
            color: Colors.white,
            height: 1,
          ),
        ),
      );
    }

    return Text(
      grade,
      style: TextStyle(
        fontSize: 96 * w / 750,
        fontWeight: FontWeight.w100,
        color: result.gradeColor(const Color(0xFF4fc3f7)),
        height: 1,
      ),
    );
  }

  Widget _buildJudgeCounts(ThemeData theme) {
    final r = widget.result;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w300,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );
    final numStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      fontFeatures: [const FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _countItem('${r.perfectCount}', 'Perfect',
                  const Color(0xFF4fc3f7), style, numStyle),
              const SizedBox(width: 24),
              _countItem('${r.greatCount}', 'Great',
                  const Color(0xFF81c784), style, numStyle),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _countItem('${r.goodCount}', 'Good',
                  const Color(0xFFffb74d), style, numStyle),
              const SizedBox(width: 24),
              _countItem('${r.missCount}', 'Miss',
                  const Color(0xFFe57373), style, numStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countItem(String num, String label, Color numColor,
      TextStyle style, TextStyle numStyle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(num, style: numStyle.copyWith(color: numColor)),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
  }
}
