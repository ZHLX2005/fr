// 撞色色卡页面

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'color.dart';

/// 撞色色卡入口页 — 下滑列表
class ColorPalettePage extends StatelessWidget {
  const ColorPalettePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pairs = ColorPaletteRepository.buildPairs(ColorPaletteRepository.swatches);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      body: SafeArea(
        child: Column(
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '撞色色卡',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${pairs.length} 组',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            // 下滑列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: pairs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PaletteCard(
                      pair: pairs[index],
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _PairDetailPage(
                              allPairs: pairs,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 列表卡片 ====================

/// 单个色卡：左色块 | 右色块，下方通行渐变条
class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.pair, required this.onTap});

  final ColorPairModel pair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);
    final aFg = ColorUtils.bestOnColor(a);
    final bFg = ColorUtils.bestOnColor(b);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // 上半：左色块 | 右色块
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    // 左色块
                    Expanded(
                      child: Container(
                        color: a,
                        child: Stack(
                          children: [
                            // 左下角：主色信息
                            Positioned(
                              left: 14,
                              bottom: 14,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pair.a.name,
                                    style: TextStyle(
                                      color: aFg,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    pair.a.hex.toUpperCase(),
                                    style: TextStyle(
                                      color: aFg.withValues(alpha: 0.7),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 右下角：对方搭配色块
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: _AccentChip(color: b, label: pair.b.name, fg: bFg),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 右色块
                    Expanded(
                      child: Container(
                        color: b,
                        child: Stack(
                          children: [
                            // 右下角：主色信息
                            Positioned(
                              right: 14,
                              bottom: 14,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    pair.b.name,
                                    style: TextStyle(
                                      color: bFg,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    pair.b.hex.toUpperCase(),
                                    style: TextStyle(
                                      color: bFg.withValues(alpha: 0.7),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 左下角：对方搭配色块
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: _AccentChip(color: a, label: pair.a.name, fg: aFg),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 下半：通行渐变
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        ColorUtils.highlight(a, t: 0.3),
                        ColorUtils.mix(a, b, 0.5),
                        ColorUtils.highlight(b, t: 0.3),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 搭配色小色块 — 显示对方颜色，字体颜色也是对方颜色
class _AccentChip extends StatelessWidget {
  const _AccentChip({required this.color, required this.label, required this.fg});

  final Color color;
  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fg.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 9,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

// ==================== 详情页 ====================

class _PairDetailPage extends StatefulWidget {
  const _PairDetailPage({
    required this.allPairs,
    required this.initialIndex,
  });

  final List<ColorPairModel> allPairs;
  final int initialIndex;

  @override
  State<_PairDetailPage> createState() => _PairDetailPageState();
}

class _PairDetailPageState extends State<_PairDetailPage> {
  late final PageController _pc;

  @override
  void initState() {
    super.initState();
    _pc = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.allPairs.length,
        itemBuilder: (context, index) {
          return _FullscreenPair(pair: widget.allPairs[index]);
        },
      ),
    );
  }
}

/// 全屏色卡：左色块 | 右色块
/// 下方通行渐变横跨整宽
/// 左侧嵌对方小色块（用对方颜色+对方字色）
/// 右侧嵌对方小色块（用对方颜色+对方字色）
class _FullscreenPair extends StatelessWidget {
  const _FullscreenPair({required this.pair});

  final ColorPairModel pair;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);
    final aFg = ColorUtils.bestOnColor(a);
    final bFg = ColorUtils.bestOnColor(b);

    return Stack(
      children: [
        Column(
          children: [
            // 上半：左色块 | 右色块
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // 左色块
                  Expanded(
                    child: Container(
                      color: a,
                      child: Stack(
                        children: [
                          // 返回按钮（用左色）
                          Positioned(
                            top: 0,
                            left: 0,
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: _BackButton(color: a, iconColor: aFg),
                              ),
                            ),
                          ),
                          // 左下角：主色信息
                          Positioned(
                            left: 20,
                            bottom: 20,
                            child: _ColorLabel(
                              name: pair.a.name,
                              hex: pair.a.hex,
                              fg: aFg,
                              onTap: () => _copy(context, pair.a.hex),
                            ),
                          ),
                          // 右侧：嵌对方搭配色块
                          Positioned(
                            right: 16,
                            top: 80,
                            child: _AccentBlock(
                              color: b,
                              label: pair.b.name,
                              fg: bFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 右色块
                  Expanded(
                    child: Container(
                      color: b,
                      child: Stack(
                        children: [
                          // 右下角：主色信息
                          Positioned(
                            right: 20,
                            bottom: 20,
                            child: _ColorLabel(
                              name: pair.b.name,
                              hex: pair.b.hex,
                              fg: bFg,
                              onTap: () => _copy(context, pair.b.hex),
                            ),
                          ),
                          // 左侧：嵌对方搭配色块
                          Positioned(
                            left: 16,
                            top: 80,
                            child: _AccentBlock(
                              color: a,
                              label: pair.a.name,
                              fg: aFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 下半：通行渐变横跨整宽
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      ColorUtils.highlight(a, t: 0.3),
                      ColorUtils.mix(a, b, 0.5),
                      ColorUtils.highlight(b, t: 0.3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _copy(BuildContext context, String hex) {
    Clipboard.setData(ClipboardData(text: hex.toUpperCase()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $hex'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ColorLabel extends StatelessWidget {
  const _ColorLabel({
    required this.name,
    required this.hex,
    required this.fg,
    required this.onTap,
  });

  final String name;
  final String hex;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              color: fg,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hex.toUpperCase(),
                style: TextStyle(
                  color: fg.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.copy, size: 14, color: fg.withValues(alpha: 0.6)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 搭配色大色块 — 显示对方颜色，字体用对方颜色的对比色
class _AccentBlock extends StatelessWidget {
  const _AccentBlock({required this.color, required this.label, required this.fg});

  final Color color;
  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fg.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              height: 1.1,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.color, required this.iconColor});

  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: iconColor.withValues(alpha: 0.18)),
          ),
          child: Icon(Icons.arrow_back, color: iconColor.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}
