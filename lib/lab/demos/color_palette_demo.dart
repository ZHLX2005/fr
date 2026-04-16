import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';

/// 撞色色卡 Demo
class ColorPaletteDemo extends DemoPage {
  @override
  String get title => '撞色色卡';

  @override
  String get description => '两两一组展示配色方案，支持 CMYK/RGB/Hex 显示';

  @override
  Widget buildPage(BuildContext context) {
    return const _ColorPalettePage();
  }
}

class _ColorPalettePage extends StatefulWidget {
  const _ColorPalettePage();

  @override
  State<_ColorPalettePage> createState() => _ColorPalettePageState();
}

class _ColorPalettePageState extends State<_ColorPalettePage> {
  final List<ColorSwatchModel> _swatches = PaletteRepository.swatches;
  late final List<ColorPairModel> _pairs;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pairs = PaletteRepository.buildPairs(_swatches);
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制: $text'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pair = _pairs[_selectedIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F8),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部选择器
            Padding(
              padding: const EdgeInsets.all(16),
              child: _PairSelector(
                pairs: _pairs,
                selectedIndex: _selectedIndex,
                onChanged: (i) => setState(() => _selectedIndex = i),
              ),
            ),
            // 色卡主体
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PairCard(
                  pair: pair,
                  onCopy: _copyToClipboard,
                ),
              ),
            ),
            // 底部信息面板
            Padding(
              padding: const EdgeInsets.all(16),
              child: _InfoPanel(pair: pair, onCopy: _copyToClipboard),
            ),
          ],
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

  String get label => '${a.name} + ${b.name}';
}

// ==================== 仓库 ====================

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

  static Color highlight(Color c) {
    int mix(int a, int b, double t) =>
        (a + (b - a) * t).round().clamp(0, 255);
    const t = 0.10;
    return Color.fromARGB(
      c.alpha,
      mix(c.red, 255, t),
      mix(c.green, 255, t),
      mix(c.blue, 255, t),
    );
  }
}

// ==================== UI 组件 ====================

class PairCard extends StatelessWidget {
  const PairCard({
    super.key,
    required this.pair,
    required this.onCopy,
  });

  final ColorPairModel pair;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final a = ColorUtils.fromHex(pair.a.hex);
    final b = ColorUtils.fromHex(pair.b.hex);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(child: _ColorHalf(model: pair.a, baseColor: a, onCopy: onCopy)),
                Expanded(child: _ColorHalf(model: pair.b, baseColor: b, onCopy: onCopy)),
              ],
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                ),
                child: const Center(
                  child: Text(
                    '+',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorHalf extends StatelessWidget {
  const _ColorHalf({
    required this.model,
    required this.baseColor,
    required this.onCopy,
  });

  final ColorSwatchModel model;
  final Color baseColor;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final fg = ColorUtils.bestOnColor(baseColor);

    return GestureDetector(
      onTap: () => onCopy(model.hex, 'HEX'),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ColorUtils.highlight(baseColor),
              baseColor,
            ],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: DefaultTextStyle(
          style: TextStyle(color: fg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model.name,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              const Spacer(),
              _ColorValue(
                label: 'C${model.cmyk.c} M${model.cmyk.m} Y${model.cmyk.y} K${model.cmyk.k}',
                color: fg,
                onTap: () => onCopy(
                  'C${model.cmyk.c} M${model.cmyk.m} Y${model.cmyk.y} K${model.cmyk.k}',
                  'CMYK',
                ),
              ),
              const SizedBox(height: 6),
              _ColorValue(
                label: 'R${model.rgb.r} G${model.rgb.g} B${model.rgb.b}',
                color: fg,
                onTap: () => onCopy(
                  '${model.rgb.r}, ${model.rgb.g}, ${model.rgb.b}',
                  'RGB',
                ),
              ),
              const SizedBox(height: 6),
              _ColorValue(
                label: model.hex.toUpperCase(),
                color: fg,
                onTap: () => onCopy(model.hex.toUpperCase(), 'HEX'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorValue extends StatelessWidget {
  const _ColorValue({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.copy,
              size: 14,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairSelector extends StatelessWidget {
  const _PairSelector({
    required this.pairs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<ColorPairModel> pairs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: DropdownButton<int>(
        value: selectedIndex,
        underline: const SizedBox.shrink(),
        isExpanded: true,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.keyboard_arrow_down),
        items: List.generate(pairs.length, (i) {
          final pair = pairs[i];
          return DropdownMenuItem(
            value: i,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ColorUtils.fromHex(pair.a.hex),
                        ColorUtils.fromHex(pair.b.hex),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Text(pair.label),
              ],
            ),
          );
        }),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.pair, required this.onCopy});

  final ColorPairModel pair;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '配色详情',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ColorDetailCard(
                  label: 'A色',
                  model: pair.a,
                  onCopy: onCopy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ColorDetailCard(
                  label: 'B色',
                  model: pair.b,
                  onCopy: onCopy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDetailCard extends StatelessWidget {
  const _ColorDetailCard({
    required this.label,
    required this.model,
    required this.onCopy,
  });

  final String label;
  final ColorSwatchModel model;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: ColorUtils.fromHex(model.hex),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HEX: ${model.hex.toUpperCase()}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'RGB: ${model.rgb.r}, ${model.rgb.g}, ${model.rgb.b}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'CMYK: ${model.cmyk.c}, ${model.cmyk.m}, ${model.cmyk.y}, ${model.cmyk.k}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

void registerColorPaletteDemo() {
  demoRegistry.register(ColorPaletteDemo());
}
