// 撞色色卡页面

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'color.dart';

/// 撞色色卡入口页 — 下滑列表
class ColorPalettePage extends StatelessWidget {
  const ColorPalettePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pairs =
        ColorPaletteRepository.buildPairs(ColorPaletteRepository.swatches);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      body: SafeArea(
        child: Column(
          children: [
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

/// 单个色卡：左色块 | 右色块，下方通行渐变条 + 基本介绍
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
        height: 200,
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 下半：通行渐变 + 简介
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '${pair.a.name} + ${pair.b.name}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 14,
                      ),
                    ],
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
/// 无渐变，字色为对方颜色（形成撞色感）
class _FullscreenPair extends StatelessWidget {
  const _FullscreenPair({required this.pair});

  final ColorPairModel pair;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);
    // 字色直接用对方颜色（不是黑白），形成撞色
    final aOnB = b; // 右色块里的文字用a
    final bOnA = a; // 左色块里的文字用b

    // 两个色块通行铺满全屏，撞色演示内容叠在色块上方
    return Stack(
      fit: StackFit.expand,
      children: [
        // 底层：左色块 | 右色块 通行铺满整个屏幕
        Row(
          children: [
            Expanded(child: Container(color: a)),
            Expanded(child: Container(color: b)),
          ],
        ),
        // 内容层：叠在色块上方
        Column(
          children: [
            // 返回按钮区
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _BackButton(color: a, iconColor: ColorUtils.bestOnColor(a)),
                  ],
                ),
              ),
            ),
            // 色卡名称 + Hex 区
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左侧：A 色信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pair.a.name,
                          style: TextStyle(
                            color: bOnA,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _copy(context, pair.a.hex),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                pair.a.hex.toUpperCase(),
                                style: TextStyle(
                                  color: bOnA.withValues(alpha: 0.8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.copy,
                                  size: 14,
                                  color: bOnA.withValues(alpha: 0.6)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 右侧：B 色信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pair.b.name,
                          style: TextStyle(
                            color: aOnB,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _copy(context, pair.b.hex),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy,
                                  size: 14,
                                  color: aOnB.withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Text(
                                pair.b.hex.toUpperCase(),
                                style: TextStyle(
                                  color: aOnB.withValues(alpha: 0.8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 撞色演示区 — 叠在色块上，半透明底色保持撞色可读性
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      '撞色演示',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 对色小方块
                    Row(
                      children: [
                        _ColorSwatchChip(
                          color: a,
                          label: pair.a.name,
                          textColor: b,
                          hex: pair.a.hex,
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.add,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 16,
                        ),
                        const SizedBox(width: 12),
                        _ColorSwatchChip(
                          color: b,
                          label: pair.b.name,
                          textColor: a,
                          hex: pair.b.hex,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 撞色文字排版示例：A 底色 + B 文字
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: a,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pair.a.name,
                            style: TextStyle(
                              color: b,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '在 ${pair.a.name} 上使用 ${pair.b.name} 文字',
                            style: TextStyle(
                              color: b.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: b.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: b.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '示例文字 — ${pair.b.name}',
                              style: TextStyle(
                                color: b,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 撞色文字排版示例：B 底色 + A 文字
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: b,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pair.b.name,
                            style: TextStyle(
                              color: a,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '在 ${pair.b.name} 上使用 ${pair.a.name} 文字',
                            style: TextStyle(
                              color: a.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: a.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: a.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '示例文字 — ${pair.a.name}',
                              style: TextStyle(
                                color: a,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部安全区
            SafeArea(
              top: false,
              child: const SizedBox(height: 0),
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
          child: Icon(Icons.arrow_back,
              color: iconColor.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}

/// 对色小方块：底色 + 对方色文字
class _ColorSwatchChip extends StatelessWidget {
  const _ColorSwatchChip({
    required this.color,
    required this.label,
    required this.textColor,
    required this.hex,
  });

  final Color color;
  final String label;
  final Color textColor;
  final String hex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: textColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hex.toUpperCase(),
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.65),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.lens,
              color: textColor.withValues(alpha: 0.5),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}
