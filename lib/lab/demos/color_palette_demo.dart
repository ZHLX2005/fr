import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/color/color.dart';
import '../lab_container.dart';

/// 撞色色卡 Demo
class ColorPaletteDemo extends DemoPage {
  @override
  String get title => '撞色色卡';

  @override
  String get description => '两两一组撞色配色，上下滑动浏览，点击进入全屏';

  @override
  Widget buildPage(BuildContext context) {
    final pairs = ColorPaletteRepository.buildPairs(ColorPaletteRepository.swatches);
    return _HomePage(pairs: pairs);
  }
}

// ==================== 首页：垂直滚动卡片列表 ====================

class _HomePage extends StatelessWidget {
  const _HomePage({required this.pairs});

  final List<ColorPairModel> pairs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    '撞色色卡',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1D),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${pairs.length} 组',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: pairs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _PairCard(
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

// ==================== 首页色卡：左右对半方块 ====================

class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair, required this.onTap});

  final ColorPairModel pair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // 左右对半
              Row(
                children: [
                  Expanded(child: Container(color: a)),
                  Expanded(child: Container(color: b)),
                ],
              ),
              // 中间+分隔
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1D),
                      ),
                    ),
                  ),
                ),
              ),
              // 底部撞色标签
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        b.withValues(alpha: 0.85),
                        a.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        pair.a.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: b.computeLuminance() > 0.55
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                      Text(
                        pair.b.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: a.computeLuminance() > 0.55
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 右上hex
              Positioned(
                top: 10,
                right: 56 + 22,
                child: Text(
                  pair.a.hex.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: b.computeLuminance() > 0.55
                        ? Colors.black.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // 左上hex
              Positioned(
                top: 10,
                left: 56 + 22,
                child: Text(
                  pair.b.hex.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: a.computeLuminance() > 0.55
                        ? Colors.black.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
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

// ==================== 详情页：全屏撞色，文字用对方颜色 ====================

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
          return _FullscreenPair(
            pair: widget.allPairs[index],
            pairIndex: index,
            totalPairs: widget.allPairs.length,
          );
        },
      ),
    );
  }
}

class _FullscreenPair extends StatelessWidget {
  const _FullscreenPair({
    required this.pair,
    required this.pairIndex,
    required this.totalPairs,
  });

  final ColorPairModel pair;
  final int pairIndex;
  final int totalPairs;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);

    // 撞色核心：左侧背景a，文字用b；右侧背景b，文字用a
    final leftFg = b;
    final rightFg = a;

    return Stack(
      children: [
        // 左右大色块
        Row(
          children: [
            // 左：背景a，文字b
            Expanded(
              child: Container(
                color: a,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            ColorUtils.highlight(a, t: 0.15),
                            a,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 60,
                      left: 20,
                      child: Text(
                        pair.a.name,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: leftFg,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 80,
                      left: 20,
                      child: GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: pair.a.hex.toUpperCase()),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已复制 ${pair.a.hex}'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Text(
                              pair.a.hex.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: leftFg.withValues(alpha: 0.75),
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.copy, size: 14, color: leftFg.withValues(alpha: 0.5)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 60,
                      right: 20,
                      child: _AccentChip(
                        color: b,
                        label: pair.b.name,
                        textColor: a.computeLuminance() > 0.55
                            ? Colors.black
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 右：背景b，文字a
            Expanded(
              child: Container(
                color: b,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            ColorUtils.highlight(b, t: 0.15),
                            b,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 60,
                      right: 20,
                      child: Text(
                        pair.b.name,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: rightFg,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 80,
                      right: 20,
                      child: GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: pair.b.hex.toUpperCase()),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已复制 ${pair.b.hex}'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 14, color: rightFg.withValues(alpha: 0.5)),
                            const SizedBox(width: 6),
                            Text(
                              pair.b.hex.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: rightFg.withValues(alpha: 0.75),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 60,
                      left: 20,
                      child: _AccentChip(
                        color: a,
                        label: pair.a.name,
                        textColor: b.computeLuminance() > 0.55
                            ? Colors.black
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // 顶部：返回+页码
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _GlassIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: Text(
                      '${pairIndex + 1} / $totalPairs',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 中间+
        Align(
          alignment: Alignment.center,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1D),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccentChip extends StatelessWidget {
  const _AccentChip({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

void registerColorPaletteDemo() {
  demoRegistry.register(ColorPaletteDemo());
}
