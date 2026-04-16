import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';

/// 撞色色卡 Demo
class ColorPaletteDemo extends DemoPage {
  @override
  String get title => '撞色色卡';

  @override
  String get description => '两两一组撞色配色，上下滑动浏览，点击进入全屏';

  @override
  Widget buildPage(BuildContext context) {
    final pairs = PaletteRepository.buildPairs(PaletteRepository.swatches);
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
                    // 颜色名（对方颜色）
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
                    // hex（对方颜色）
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
                    // 嵌入搭配色小色块
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

// ==================== 数据模型 ====================

class Cmyk {
  final int c, m, y, k;
  const Cmyk({required this.c, required this.m, required this.y, required this.k});
}

class Rgb {
  final int r, g, b;
  const Rgb({required this.r, required this.g, required this.b});
}

class ColorSwatchModel {
  final String name;
  final Cmyk cmyk;
  final Rgb rgb;
  final String hex;

  const ColorSwatchModel({
    required this.name,
    required this.cmyk,
    required this.rgb,
    required this.hex,
  });
}

class ColorPairModel {
  final ColorSwatchModel a;
  final ColorSwatchModel b;

  const ColorPairModel({required this.a, required this.b});
}

class PaletteRepository {
  static const List<ColorSwatchModel> swatches = [
    ColorSwatchModel(
      name: '炭黑色',
      cmyk: Cmyk(c: 85, m: 81, y: 76, k: 64),
      rgb: Rgb(r: 26, g: 26, b: 29),
      hex: '#1A1A1D',
    ),
    ColorSwatchModel(
      name: '甜酷粉',
      cmyk: Cmyk(c: 12, m: 88, y: 26, k: 0),
      rgb: Rgb(r: 230, g: 57, b: 124),
      hex: '#E6397C',
    ),
    ColorSwatchModel(
      name: '深海蓝',
      cmyk: Cmyk(c: 100, m: 93, y: 20, k: 0),
      rgb: Rgb(r: 18, g: 46, b: 138),
      hex: '#122E8A',
    ),
    ColorSwatchModel(
      name: '柔奶白',
      cmyk: Cmyk(c: 5, m: 7, y: 9, k: 0),
      rgb: Rgb(r: 245, g: 239, b: 234),
      hex: '#F5EFEA',
    ),
    ColorSwatchModel(
      name: '无白色',
      cmyk: Cmyk(c: 7, m: 17, y: 9, k: 0),
      rgb: Rgb(r: 241, g: 221, b: 223),
      hex: '#F1DDDF',
    ),
    ColorSwatchModel(
      name: '茶花红',
      cmyk: Cmyk(c: 10, m: 92, y: 63, k: 0),
      rgb: Rgb(r: 231, g: 45, b: 72),
      hex: '#E72D48',
    ),
    ColorSwatchModel(
      name: '鸦蓝色',
      cmyk: Cmyk(c: 99, m: 90, y: 51, k: 20),
      rgb: Rgb(r: 17, g: 48, b: 86),
      hex: '#113056',
    ),
    ColorSwatchModel(
      name: '清水蓝',
      cmyk: Cmyk(c: 47, m: 6, y: 20, k: 0),
      rgb: Rgb(r: 145, g: 207, b: 213),
      hex: '#91CFD5',
    ),
  ];

  static List<ColorPairModel> buildPairs(List<ColorSwatchModel> list) {
    final result = <ColorPairModel>[];
    for (var i = 0; i + 1 < list.length; i += 2) {
      result.add(ColorPairModel(a: list[i], b: list[i + 1]));
    }
    return result;
  }
}

// ==================== 工具类 ====================

class ColorUtils {
  static Color fromHex(String hex) {
    final cleaned = hex.replaceAll('#', '').toUpperCase();
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    if (cleaned.length == 8) {
      return Color(int.parse(cleaned, radix: 16));
    }
    throw ArgumentError('Invalid hex: $hex');
  }

  static Color bestOnColor(Color bg) {
    final l = bg.computeLuminance();
    return l > 0.55 ? Colors.black : Colors.white;
  }

  static Color highlight(Color c, {double t = 0.10}) {
    int mix(int a, int b, double t) =>
        (a + (b - a) * t).round().clamp(0, 255);
    return Color.fromARGB(
      (c.a * 255).round(),
      mix((c.r * 255).round(), 255, t),
      mix((c.g * 255).round(), 255, t),
      mix((c.b * 255).round(), 255, t),
    );
  }
}

void registerColorPaletteDemo() {
  demoRegistry.register(ColorPaletteDemo());
}
