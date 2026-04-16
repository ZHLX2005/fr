import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';

/// 撞色色卡 Demo
class ColorPaletteDemo extends DemoPage {
  @override
  String get title => '撞色色卡';

  @override
  String get description => '两两一组展示配色方案，左右滑切换沉浸全屏';

  @override
  Widget buildPage(BuildContext context) {
    final pairs = PaletteRepository.buildPairs(PaletteRepository.swatches);
    return _HomePage(pairs: pairs);
  }
}

// ==================== HomePage ====================

class _HomePage extends StatefulWidget {
  const _HomePage({required this.pairs});

  final List<ColorPairModel> pairs;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late final ValueNotifier<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = ValueNotifier<int>(0);
  }

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ValueListenableBuilder<int>(
              valueListenable: _selected,
              builder: (context, idx, _) {
                final pair = widget.pairs[idx];
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 极简预览条
                    SizedBox(
                      height: 140,
                      child: _PairPreviewStrip(pair: pair),
                    ),
                    const SizedBox(height: 18),
                    // 圆点选择器
                    _PairDots(
                      count: widget.pairs.length,
                      index: idx,
                      onTap: (i) => _selected.value = i,
                    ),
                    const SizedBox(height: 24),
                    // 进入全屏按钮
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _PairDetailPage(
                              allPairs: widget.pairs,
                              initialIndex: idx,
                            ),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A1D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '进入全屏色卡',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                );
              },
            ),
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

class _FullscreenPair extends StatelessWidget {
  const _FullscreenPair({required this.pair});

  final ColorPairModel pair;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);

    return Stack(
      children: [
        // 左右大色块
        Row(
          children: [
            Expanded(
              child: _ColorHalfFullscreen(
                mainName: pair.a.name,
                mainHex: pair.a.hex,
                main: a,
                accent: b,
                accentLabel: pair.b.name,
                accentAlign: Alignment.bottomRight,
              ),
            ),
            Expanded(
              child: _ColorHalfFullscreen(
                mainName: pair.b.name,
                mainHex: pair.b.hex,
                main: b,
                accent: a,
                accentLabel: pair.a.name,
                accentAlign: Alignment.bottomLeft,
              ),
            ),
          ],
        ),
        // 返回按钮
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _GlassIconButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        // 中间+锚点
        Align(
          alignment: Alignment.center,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: const Center(
              child: Text(
                '+',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorHalfFullscreen extends StatelessWidget {
  const _ColorHalfFullscreen({
    required this.mainName,
    required this.mainHex,
    required this.main,
    required this.accent,
    required this.accentLabel,
    required this.accentAlign,
  });

  final String mainName;
  final String mainHex;
  final Color main;
  final Color accent;
  final String accentLabel;
  final Alignment accentAlign;

  @override
  Widget build(BuildContext context) {
    final fg = ColorUtils.bestOnColor(main);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ColorUtils.highlight(main, t: 0.12), main],
        ),
      ),
      child: Stack(
        children: [
          // 少文字：颜色名 + hex
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: TextStyle(color: fg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mainName,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.90),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: mainHex.toUpperCase()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制 $mainHex'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Text(
                        mainHex.toUpperCase(),
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 嵌入搭配色小色块
          Align(
            alignment: accentAlign,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _InsetAccentBlock(color: accent, label: accentLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsetAccentBlock extends StatelessWidget {
  const _InsetAccentBlock({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = ColorUtils.bestOnColor(color);
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
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

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, color: Colors.black.withValues(alpha: 0.75)),
        ),
      ),
    );
  }
}

// ==================== 极简选择器 ====================

class _PairDots extends StatelessWidget {
  const _PairDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return GestureDetector(
          onTap: () => onTap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: active ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active
                  ? Colors.black.withValues(alpha: 0.78)
                  : Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _PairPreviewStrip extends StatelessWidget {
  const _PairPreviewStrip({required this.pair});

  final ColorPairModel pair;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(child: Container(color: a)),
              Expanded(child: Container(color: b)),
            ],
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: const Center(
                child: Text(
                  '+',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
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
