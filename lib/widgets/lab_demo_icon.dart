// Lab 演示图标 —— 用 `assets/lab-demo-icons/` 的 SVG 渲染，按当前主题色着色。
//
// 设计要点：
//
// 1. SVG 资产原始硬编码为「主色 #2B3445 + 强调色 #5B7CFA」。这里在加载后
//    字符串替换这两个色值到当前主题的 `colors.text` 与 `colors.accent`，
//    再喂给 [SvgPicture.string] 渲染——完成「随主题色切换」的要求。
//
// 2. SVG 字符串加载后缓存在静态 map（含 Future），同一资产多次构建只触发
//    一次 `rootBundle.loadString`，48 个 demo 卡片网格不会重复 IO。
//
// 3. `[LabDemoIcon.prewarm]` 提供显式预热入口，`main.dart` 启动时调用一次，
//    让用户进入 Lab 前 SVGs 都已就绪——开 Lab 看不到图标从无到有的闪烁。
//
// 4. `tintLightLevel / tintDarkLevel` 控背景盒的色调亮度（lab 卡片 / 详情弹窗
//    用了同一图标但底色不同，色彩饱和度需要微调）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/extensions/color_strategy_extension.dart';
import '../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../core/theme/colors/strategy/color_strategy/themes/default.dart';

/// SVG 静态色（来自设计稿）。替换为当前主题的 text / accent。
const String _kSvgInkHex = '#2B3445'; // 笔触 / 主轮廓
const String _kSvgAccentHex = '#5B7CFA'; // 强调点
const String _kSvgInkAltLower = '#2b3445'; // 大小写兜底（少见但保险）
const String _kSvgAccentAltLower = '#5b7cfa';

class LabDemoIcon extends StatefulWidget {
  const LabDemoIcon({
    super.key,
    required this.assetBaseName,
    this.size,
    this.inkColor,
    this.accentColor,
    this.semanticsLabel,
  });

  /// 不含后缀的 SVG 名（与 `assets/lab-demo-icons/{assetBaseName}.svg` 对齐）。
  /// 例如 `'01-clock'`、`'42-reversi'`。
  final String assetBaseName;

  /// 渲染尺寸。null = 让父 LayoutBuilder 决定。SVG viewBox 32×32 时直接用 width/height。
  final double? size;

  /// 覆盖主轮廓色。null = `context.colors.text`（随主题明暗自适应）。
  final Color? inkColor;

  /// 覆盖强调点色。null = `context.colors.accent`（随主题强调色切换）。
  /// 传与 [inkColor] 相同的色 = 双色 SVG 压成单色（底栏选中态着色等场景）。
  final Color? accentColor;

  /// 屏幕阅读器朗读的文字。SVG 文件不携带 `<title>`，所以需要外部传入。
  final String? semanticsLabel;

  @override
  State<LabDemoIcon> createState() => _LabDemoIconState();

  /// 预热一组资产（通常是 Lab 全部 48 个），让首次构建不需要等待 IO。
  static Future<void> prewarm(Iterable<String> assetBaseNames) async {
    await Future.wait(assetBaseNames.map((n) => _loadSvg(n)));
  }

  /// 单一预热入口，给一个 basename。
  static Future<void> prewarmOne(String assetBaseName) => _loadSvg(assetBaseName);
}

class _LabDemoIconState extends State<LabDemoIcon> {
  late Future<String> _source = _loadSvg(widget.assetBaseName);

  @override
  void didUpdateWidget(covariant LabDemoIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetBaseName != widget.assetBaseName) {
      _source = _loadSvg(widget.assetBaseName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strategy = _resolve(context);
    final fg = widget.inkColor ?? strategy.text;
    final accent = widget.accentColor ?? strategy.accent;
    final fgHex = _toHex(fg);
    final accentHex = _toHex(accent);

    return FutureBuilder<String>(
      future: _source,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          // 加载中：占一个同等尺寸的盒子，避免布局抖动
          return SizedBox(
            width: widget.size,
            height: widget.size,
          );
        }
        final colored = _colorize(
          snap.data!,
          inkHex: fgHex,
          accentHex: accentHex,
        );
        return Semantics(
          label: widget.semanticsLabel,
          image: true,
          child: SvgPicture.string(
            colored,
            width: widget.size,
            height: widget.size,
          ),
        );
      },
    );
  }
}

/// 单例缓存：asset basename → Future[String] 形式的字典，去重 → 一次性 loadString。
final Map<String, Future<String>> _svgCache = {};

Future<String> _loadSvg(String assetBaseName) {
  final cached = _svgCache[assetBaseName];
  if (cached != null) return cached;
  final path = 'assets/lab-demo-icons/$assetBaseName.svg';
  final future = rootBundle.loadString(path);
  _svgCache[assetBaseName] = future;
  return future;
}

/// 把设计稿硬编码的两种颜色替换成主题色。
String _colorize(String svg, {required String inkHex, required String accentHex}) {
  return svg
      .replaceAll(_kSvgInkHex, inkHex)
      .replaceAll(_kSvgInkAltLower, inkHex)
      .replaceAll(_kSvgAccentHex, accentHex)
      .replaceAll(_kSvgAccentAltLower, accentHex);
}

/// 色值替换的可测出口：输入原始 SVG 文本，输出替换后的文本。
/// `flutter test` 里断言换色正确性用它，不走渲染管线。
@visibleForTesting
String colorizeLabSvg(
  String svg, {
  required Color ink,
  required Color accent,
}) {
  return _colorize(
    svg,
    inkHex: _toHex(ink),
    accentHex: _toHex(accent),
  );
}

/// Flutter [Color] 转 `#RRGGBB` 大写 hex（带 #，可直接替换 SVG fill/stroke 值）。
String _toHex(Color c) {
  final r = (c.r * 255.0).round() & 0xff;
  final g = (c.g * 255.0).round() & 0xff;
  final b = (c.b * 255.0).round() & 0xff;
  final v = (r << 16) | (g << 8) | b;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

ColorStrategy _resolve(BuildContext context) {
  final ext = Theme.of(context).extension<ColorStrategyExtension>();
  if (ext != null) return ext.strategy;
  return DefaultColorStrategy.of(Theme.of(context).colorScheme);
}

/// 测试钩子：清空 SVG 缓存。仅 `flutter test` 用。
@visibleForTesting
void debugResetLabDemoIconCache() => _svgCache.clear();
