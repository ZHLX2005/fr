"""Extract CJK glyph outlines from an OFL-licensed font into SVG path data.

Outputs a Dart source file mapping each Chinese character to an SVG `d`
attribute scaled into a 0..100 viewBox (baseline-agnostic, centred).

Usage:
  uv run --with fonttools python tool/extract_xiangqi_glyphs.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONT_PATH = r"C:\Windows\Fonts\NotoSerifSC-VF.ttf"

# viewBox size (square). Glyph outlines are scaled to fit, centred.
VIEW = 100.0

# Chinese-chess piece glyphs: char -> piece role label (for the Dart doc comment)
CHARS = [
    ("帅", "red general"),
    ("将", "black general"),
    ("仕", "red advisor"),
    ("士", "black advisor"),
    ("相", "red elephant"),
    ("象", "black elephant"),
    ("马", "horse"),
    ("车", "chariot"),
    ("炮", "cannon"),
    ("兵", "red pawn"),
    ("卒", "black pawn"),
    # 楚河汉界 —— 棋盘中央河界题字
    ("楚", "river text"),
    ("河", "river text"),
    ("汉", "river text"),
    ("界", "river text"),
]

OUT = Path(__file__).resolve().parents[1] / "lib/core/xiangqi/widgets/xiangqi_piece_glyphs.dart"


def glyph_path(font: TTFont, char: str) -> str:
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    glyph_name = cmap.get(ord(char))
    if glyph_name is None:
        raise SystemExit(f"glyph missing for {char!r}")

    # Glyph bounds in font units.
    from fontTools.pens.boundsPen import BoundsPen

    bp = BoundsPen(glyph_set)
    glyph_set[glyph_name].draw(bp)
    if bp.bounds is None:
        raise SystemExit(f"empty glyph for {char!r}")
    x_min, y_min, x_max, y_max = bp.bounds
    gx = x_max - x_min
    gy = y_max - y_min
    if gx <= 0 or gy <= 0:
        raise SystemExit(f"degenerate bounds for {char!r}: {bp.bounds}")

    # Fit into the viewBox with padding, preserving aspect ratio, centred.
    pad = 6.0
    scale = min((VIEW - 2 * pad) / gx, (VIEW - 2 * pad) / gy)
    left = (VIEW - gx * scale) / 2.0
    top = (VIEW - gy * scale) / 2.0
    dx = left - x_min * scale
    # Font space is y-up, SVG is y-down → flip, then shift so the glyph's
    # top edge lands on `top` and its bottom edge on `top + gy*scale`.
    ty = scale * y_max + top

    transform = (scale, 0, 0, -scale, dx, ty)

    pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.2f}")
    tpen = TransformPen(pen, transform)
    glyph_set[glyph_name].draw(tpen)
    d = pen.getCommands()
    _assert_in_viewbox(d, char)
    return d


def _assert_in_viewbox(d: str, char: str) -> None:
    """Fail loudly if any coordinate escapes the 0..100 viewBox."""
    import re

    for x_str, y_str in re.findall(r"(-?[\d.]+)\s+(-?[\d.]+)", d):
        x, y = float(x_str), float(y_str)
        if not (-0.5 <= x <= VIEW + 0.5 and -0.5 <= y <= VIEW + 0.5):
            raise SystemExit(
                f"glyph {char!r} escapes viewBox at ({x:.2f}, {y:.2f})"
            )


def main() -> int:
    font = TTFont(FONT_PATH, fontNumber=0)
    entries = []
    for char, role in CHARS:
        d = glyph_path(font, char)
        entries.append((char, role, d))
        print(f"{char} ({role}): {len(d)} chars")

    lines = []
    lines.append("// lib/core/xiangqi/widgets/xiangqi_piece_glyphs.dart")
    lines.append("//")
    lines.append("// 中国象棋棋子字形 —— **SVG path 数据**（非字体、非图片）。")
    lines.append("//")
    lines.append("// ## 为什么是 path 而不是 <text>")
    lines.append("//")
    lines.append("// flutter_svg 2.x 的编译后端 vector_graphics **不支持 <text> 元素**")
    lines.append("// （会静默丢弃，不报错）。所以棋子上的汉字必须以真实矢量路径渲染，")
    lines.append("// 否则在真机上棋子会变成一个没有字的空圆盘。")
    lines.append("//")
    lines.append("// ## 数据来源与许可")
    lines.append("//")
    lines.append("// 字形轮廓取自 **Noto Serif SC**（`NotoSerifSC-VF.ttf`，SIL Open Font")
    lines.append("// License 1.1 —— 允许自由使用 / 修改 / 再分发，含以矢量轮廓形式嵌入应用）。")
    lines.append("// 生成脚本：`tool/extract_xiangqi_glyphs.py`（fontTools 取轮廓 → 归一化到")
    lines.append("// 0..100 viewBox → 居中）。许可全文见")
    lines.append("// https://scripts.sil.org/OFL —— 再分发本文件时须保留该声明。")
    lines.append("//")
    lines.append("// ## 坐标约定")
    lines.append("//")
    lines.append("// · viewBox = `0 0 100 100`，字形已水平翻转（字体 y 向上 → SVG y 向下）")
    lines.append("//   并在 6 单位内边距内等比缩放、居中。")
    lines.append("// · 棋子 widget 直接把该 path 填进 100×100 的 SVG 画布即可。")
    lines.append("//")
    lines.append("// 重新生成（改动字体或字形集合时）：")
    lines.append("// ```")
    lines.append("// uv run --with fonttools python tool/extract_xiangqi_glyphs.py")
    lines.append("// ```")
    lines.append("")
    lines.append("/// 单个汉字 → SVG `d` 路径数据（viewBox 0 0 100 100）。")
    lines.append("const Map<String, String> kXiangqiGlyphPaths = {")
    for char, role, d in entries:
        lines.append(f"  // {char} —— {role}")
        lines.append(f"  '{char}':")
        lines.append(f"      '{d}',")
    lines.append("};")
    lines.append("")
    lines.append("/// 字形 path 的 viewBox 尺寸（与 [kXiangqiGlyphPaths] 配套）。")
    lines.append("const double kXiangqiGlyphViewBox = 100.0;")
    lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nwritten: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
