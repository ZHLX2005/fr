// lib/core/xiangqi/widgets/xiangqi_piece_svg.dart
//
// 中国象棋棋子 —— **纯 SVG 绘制**（无图片素材 / 无字体依赖）。
//
// ## 为什么不用 <text>、也不用图片
//
//   · flutter_svg 2.x 的编译后端 vector_graphics **不支持 <text> 元素** ——
//     会被静默丢弃（不报错、不渲染），棋子会变成没有字的空圆盘。
//   · 图片素材（PNG/SVG 文件）违背「自己用 SVG 绘制棋子」的诉求，且要额外
//     打包资源 + 走皮肤系统。
//   ⇒ 汉字必须以**真实矢量路径**渲染：字形轮廓在构建期从 OFL 字体提取，
//     烘焙进 `xiangqi_piece_glyphs.dart`（见该文件头的许可声明）。
//
// ## 棋子构成
//
//   外圈圆盘（象牙底 + 主色描边） → 内圈细环 → 居中汉字 path。
//
// ## 性能
//
//   flutter_svg 的 `svg.cache` 是**全局**缓存（见 flutter_svg 2.3.0
//   `svg.cache`），按 SVG 字符串命中。因此：
//   · 同一 (棋种, 颜色) 的棋子共用**同一份字符串**（本文件做了记忆化）；
//   · 每种组合只解析一次，32 枚棋子不会重复编译。
//   · 选中 / 上手 / 被将军等**状态高亮不放进 SVG**（会改变字符串导致缓存失效），
//     而是由棋盘层用 Flutter 绘制的外圈承担。
//
// ## 与国际象棋 / 国际跳棋的差异
//
//   · 国际象棋棋子是 PNG 皮肤图（`ChessSkin` + `ChessPiece`），可换肤；
//     国际跳棋用 CustomPainter 画圆盘 + 王冠环。
//   · 中国象棋走「矢量字形」路线：字形是棋子最重要的识别信息，
//     圆盘 + 汉字的组合无法用简单几何图元表达，SVG path 是唯一合适载体。

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/piece.dart';
import 'xiangqi_piece_glyphs.dart';

/// 棋子配色（红 / 黑两套）。
///
/// 主题豁免（S 级模块棋具令牌，逐项）：中国象棋棋具识别色系统 ——
/// 红黑双方靠「圆盘底色 + 描边 + 字色」三重区分，对齐
/// surround_game / reversi 的 BoardThemeData 先例，不随主题漂移。
class XiangqiPieceColors {
  /// 配色方案标签（'light' / 'dark'）—— 参与 SVG 缓存 key。
  final String scheme;

  /// 圆盘底色
  final Color disc;

  /// 外圈 / 内圈描边色
  final Color ring;

  /// 汉字颜色
  final Color ink;

  /// 落子阴影色
  final Color shadow;

  const XiangqiPieceColors({
    required this.disc,
    required this.ring,
    required this.ink,
    required this.shadow,
    this.scheme = 'light',
  });

  /// 红方：暖象牙底 + 朱红描边与字
  static const XiangqiPieceColors red = XiangqiPieceColors(
    disc: Color(0xFFF8EBD0),
    ring: Color(0xFFB2312B),
    ink: Color(0xFFA8261F),
    shadow: Color(0x33B2312B),
  );

  /// 黑方：冷象牙底 + 墨黑描边与字
  static const XiangqiPieceColors black = XiangqiPieceColors(
    disc: Color(0xFFEDE8DC),
    ring: Color(0xFF2C2B30),
    ink: Color(0xFF232227),
    shadow: Color(0x332C2B30),
  );

  /// 红方（深色主题）：整体压暗，避免深色棋盘上出现"浅盘浮在暗底"的割裂感。
  static const XiangqiPieceColors redDark = XiangqiPieceColors(
    disc: Color(0xFFE0C79A),
    ring: Color(0xFFC0392B),
    ink: Color(0xFFA8261F),
    shadow: Color(0x33C0392B),
    scheme: 'dark',
  );

  /// 黑方（深色主题）：整体压暗。
  static const XiangqiPieceColors blackDark = XiangqiPieceColors(
    disc: Color(0xFFD2CCBE),
    ring: Color(0xFF3A3A42),
    ink: Color(0xFF232227),
    shadow: Color(0x333A3A42),
    scheme: 'dark',
  );

  /// 按颜色取配色（浅色主题）
  static XiangqiPieceColors of(XiangqiColor color) =>
      color == XiangqiColor.red ? red : black;

  /// 按颜色取配色（深色主题）
  static XiangqiPieceColors ofDark(XiangqiColor color) =>
      color == XiangqiColor.red ? redDark : blackDark;
}

/// 单个棋子的 SVG 绘制结果（字符串 + 尺寸无关）。
class XiangqiPieceArt {
  const XiangqiPieceArt._(this.svg);

  /// 完整 SVG 源码（viewBox 0 0 100 100）
  final String svg;

  /// 记忆化缓存：同一 (棋种, 颜色, 配色方案) 复用同一字符串 → 命中 flutter_svg 全局缓存。
  static final Map<String, String> _cache = <String, String>{};

  /// 取棋子 SVG（记忆化）。
  ///
  /// [colors] 决定描边 / 字色 —— 浅色与深色主题各一份，故缓存 key 含配色方案。
  static String svgFor(XiangqiPiece piece, {XiangqiPieceColors? colors}) {
    final c = colors ?? XiangqiPieceColors.of(piece.color);
    final key = '${piece.type.index}:${piece.color.index}:${c.scheme}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final built = _build(piece, c);
    _cache[key] = built;
    return built;
  }

  static String _build(XiangqiPiece piece, XiangqiPieceColors colors) {
    final glyph = kXiangqiGlyphPaths[piece.chineseName] ?? '';
    // 字形 path 在 100×100 画布里占 6..94；棋子内圈直径 77 → 缩到 0.72
    // 让汉字既填满内圈又留出边距（与实物棋子"字比圈略小"的比例一致）。
    const inkScale = 0.72;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<circle cx="50" cy="50" r="46" fill="${_hex(colors.disc)}" '
        'stroke="${_hex(colors.ring)}" stroke-width="3"/>'
        '<circle cx="50" cy="50" r="38.5" fill="none" '
        'stroke="${_hex(colors.ring)}" stroke-width="1.4" opacity="0.72"/>'
        '<g transform="translate(50 50) scale($inkScale) translate(-50 -50)">'
        '<path d="$glyph" fill="${_hex(colors.ink)}"/>'
        '</g>'
        '</svg>';
  }

  /// Color → `#RRGGBB`（flutter_svg 不接受 0xAARRGGBB 写法）
  static String _hex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
}

/// 单枚棋子 widget（SVG 圆盘 + 汉字）。
///
/// 只负责"棋子长什么样"：不含棋盘坐标 / 选中态 / 高亮（那些由棋盘层叠加），
/// 与 `ChessPiece`（只持有 image + size）的边界约定一致。
class XiangqiPieceSvg extends StatelessWidget {
  const XiangqiPieceSvg({
    super.key,
    required this.piece,
    required this.size,
    this.colors,
    this.showShadow = true,
  });

  /// 要渲染的棋子
  final XiangqiPiece piece;

  /// 渲染边长（px）
  final double size;

  /// 配色覆盖（由棋盘 palette 注入；null = 按棋子颜色取默认浅色主题配色）。
  ///
  /// 棋盘 palette 是**唯一真相源** —— 深色主题下棋盘与棋子必须一起变暗，
  /// 不能出现"深色棋盘 + 浅色棋子"的割裂。
  final XiangqiPieceColors? colors;

  /// 是否绘制落子阴影（SVG filter 不受支持 → 用 Flutter 叠一层模糊圆）
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? XiangqiPieceColors.of(piece.color);
    final art = SvgPicture.string(
      XiangqiPieceArt.svgFor(piece, colors: c),
      width: size,
      height: size,
      fit: BoxFit.contain,
      // 解析失败兜底：渲染一个纯色圆盘（绝不空白 / 绝不抛错）。
      errorBuilder: (_, _, _) => _FallbackDisc(colors: c, size: size),
    );

    if (!showShadow) return art;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 阴影：椭圆柔影（模拟棋子落在棋盘上的接触阴影）
        Positioned(
          left: size * 0.08,
          right: size * 0.08,
          top: size * 0.80,
          height: size * 0.14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.shadow,
              borderRadius: BorderRadius.circular(size),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: size * 0.18,
                  spreadRadius: size * 0.02,
                ),
              ],
            ),
          ),
        ),
        art,
      ],
    );
  }
}

/// SVG 解析失败时的兜底圆盘。
class _FallbackDisc extends StatelessWidget {
  const _FallbackDisc({required this.colors, required this.size});

  final XiangqiPieceColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.disc,
          border: Border.all(color: colors.ring, width: size * 0.03),
        ),
      ),
    );
  }
}
