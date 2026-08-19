#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""主题色彩比例审计脚本。

解析 lib/core/theme/semantic/colors.dart 的 8 套 ColorScheme，
按 60/30/10 配色法则 + 互补色搭配两个维度做客观评估：

  · 互补性：primary ↔ tertiary / error 的色相角差是否进入互补区间（150°~210°）
  · 单一性：primary/secondary/tertiary 三主角色相的家族扩散度（spread）
  · 60/30/10：
      60% 底色（surface）是否中性（低饱和）
      30% 主色（primary）是否有明确色相身份（中饱和）
      10% 强调色（tertiary）是否与主色拉开（互补或更高饱和）

用法：
  python scripts/theme_ratio_audit.py [path/to/colors.dart]
"""

import re
import sys
from pathlib import Path

# ----------------------------------------------------------------------
# 色空间
# ----------------------------------------------------------------------

def hex_to_rgb(h: str):
    """解析 Flutter ARGB 十六进制：取后 6 位为 RGB，前两位是 alpha。"""
    h = h.lstrip("#").removeprefix("0x")[-6:]
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def rgb_to_hsl(r: int, g: int, b: int):
    """返回 (hue 0-360, sat 0-1, light 0-1)。"""
    r, g, b = r / 255.0, g / 255.0, b / 255.0
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    d = mx - mn
    if d == 0:
        return (0.0, 0.0, l)
    s = d / (1 - abs(2 * l - 1)) if abs(2 * l - 1) < 1 else 0.0
    if mx == r:
        h = ((g - b) / d) % 6
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    h = h * 60
    if h < 0:
        h += 360
    return (h, s, l)


def ang_diff(a: float, b: float) -> float:
    """色环上的最小夹角（0~180）。"""
    d = abs(a - b) % 360
    return min(d, 360 - d)


# ----------------------------------------------------------------------
# 解析 colors.dart
# ----------------------------------------------------------------------

THEME_BLOCK = re.compile(
    r"static const ColorScheme (\w+) = ColorScheme\((.*?)\n  \);",
    re.DOTALL,
)
ROLE_ENTRY = re.compile(r"(\w+): Color\((0x[0-9A-Fa-f]{8})\)")


def parse_themes(src: str):
    themes = {}
    for name, body in THEME_BLOCK.findall(src):
        roles = {}
        for role, hexv in ROLE_ENTRY.findall(body):
            roles[role] = hex_to_rgb(hexv)
        themes[name] = roles
    return themes


# ----------------------------------------------------------------------
# 评分
# ----------------------------------------------------------------------

def complement_score(d: float) -> int:
    """色相角差 → 互补性得分（0-100）。"""
    if d >= 150:
        return 100
    if d >= 120:
        return 75
    if d >= 90:
        return 50
    if d >= 45:
        return 25
    return 0


def family_spread(hues) -> float:
    """一组色相的最大两两夹角（家族扩散度）。"""
    best = 0.0
    for i in range(len(hues)):
        for j in range(i + 1, len(hues)):
            best = max(best, ang_diff(hues[i], hues[j]))
    return best


def hue_name(hue: float) -> str:
    if hue is None:
        return "灰"
    if hue < 15 or hue >= 345:
        return "红"
    if hue < 45:
        return "橙"
    if hue < 70:
        return "黄"
    if hue < 150:
        return "绿"
    if hue < 200:
        return "青"
    if hue < 260:
        return "蓝"
    if hue < 330:
        return "紫"
    return "玫红"


def rgb_chroma(rgb) -> float:
    """RGB max-min / 255 —— 近白/近黑的真实"色彩度"（HSL 对极亮色会虚高）。"""
    return (max(rgb) - min(rgb)) / 255.0


def audit_theme(name: str, roles: dict):
    out = []
    need = ("primary", "secondary", "tertiary", "error", "surface")

    def hsl(role):
        rgb = roles.get(role)
        if rgb is None:
            return None
        return rgb_to_hsl(*rgb)

    P, S, T, E, surf = map(hsl, need)
    if P is None:
        return f"[{name}] 缺 primary，跳过"

    d_PT = ang_diff(P[0], T[0]) if T else None  # 装饰强调 tertiary
    d_PE = ang_diff(P[0], E[0]) if E else None  # 危险 error
    accent_d = d_PT if d_PT is not None else 0  # 标题判定只看 tertiary

    spread = family_spread(
        [h for h in (P[0], S[0] if S else None, T[0] if T else None) if h is not None]
    )

    # ---- 60/30/10 逐项 ----
    surf_chroma = rgb_chroma(roles["surface"]) if "surface" in roles else 1.0
    prim_chroma = rgb_chroma(roles["primary"])
    base_neutral = surf_chroma < 0.06  # 底色接近中性灰
    primary_identity = prim_chroma >= 0.10  # 主色有明确色相（非灰）
    accent_distinct = d_PT is not None and d_PT >= 45  # 强调色与主色拉开

    # ---- 汇总 ----
    comp = complement_score(accent_d)
    if accent_d is not None and accent_d >= 120:
        comp_verdict = "互补 ✓"
    elif accent_d is not None and accent_d >= 45:
        comp_verdict = "弱对比 △"
    else:
        comp_verdict = "同色系 ✗"

    if spread >= 90:
        spread_verdict = "丰富"
    elif spread >= 45:
        spread_verdict = "中等"
    else:
        spread_verdict = "单一 ✗"

    checks = [
        ("60% 底色中性", base_neutral),
        ("30% 主色有身份", primary_identity),
        ("10% 强调拉开", accent_distinct),
    ]

    def fmt(rgb):
        return "#%02X%02X%02X" % rgb

    def fmt_hsl(v):
        if v is None:
            return "—"
        h, s, l = v
        return f"hsl({h:03.0f}° {s*100:4.0f}% {l*100:4.0f}%)"

    out.append(f"[{name}]")
    out.append(
        f"  primary   {fmt(roles['primary'])}  {fmt_hsl(P)}  <{hue_name(P[0])}>"
    )
    if S:
        out.append(f"  secondary {fmt(roles['secondary'])}  {fmt_hsl(S)}  <{hue_name(S[0])}>")
    if T:
        out.append(f"  tertiary  {fmt(roles['tertiary'])}  {fmt_hsl(T)}  <{hue_name(T[0])}>")
    if E:
        out.append(f"  error     {fmt(roles['error'])}  {fmt_hsl(E)}  <{hue_name(E[0])}>")
    if surf:
        out.append(
            f"  surface   {fmt(roles['surface'])}  {fmt_hsl(surf)}  <{'中性' if surf[1] < 0.15 else hue_name(surf[0])}>"
        )

    out.append(
        f"  primary↔tertiary(强调)  {d_PT if d_PT is not None else '—':>6.0f}°"
        f"   primary↔error(危险) {d_PE if d_PE is not None else '—':>5.0f}°"
    )
    out.append(
        f"  强调色(tertiary)  {accent_d:5.0f}°  →  互补性得分 {comp:3d}/100  [{comp_verdict}]"
    )
    out.append(f"  三主角色相扩散    {spread:5.0f}°  →  {spread_verdict}")
    out.append(
        "  60/30/10:  "
        + "  ".join(f"{label} {'✓' if ok else '✗'}" for label, ok in checks)
    )
    return "\n".join(out)


def main():
    # Windows 控制台默认 GBK，强制 UTF-8 输出（支持 ↔/✓/✗ 等符号）
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    default = Path(__file__).resolve().parents[1] / "lib/core/theme/semantic/colors.dart"
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    src = src_path.read_text(encoding="utf-8")
    themes = parse_themes(src)

    if not themes:
        print(f"未在 {src_path} 解析到任何 ColorScheme")
        return 1

    # 保持声明顺序
    order = [
        n for n in re.findall(r"ColorScheme (\w+)", src) if n in themes
    ]

    print("=" * 64)
    print(f"主题色彩比例审计 · {src_path}")
    print("法则：60% 底色(中性) / 30% 主色(有身份) / 10% 强调(互补或更高饱和)")
    print("互补区间：色相角差 150°~210°；同色系 <45°")
    print("=" * 64)

    summary = []
    for name in order:
        print()
        print(audit_theme(name, themes[name]))
        P = themes[name].get("primary")
        T = themes[name].get("tertiary")
        if P and T:
            dpt = ang_diff(rgb_to_hsl(*P)[0], rgb_to_hsl(*T)[0])
            summary.append((name, dpt))
        else:
            summary.append((name, 0))

    print()
    print("=" * 64)
    print("汇总（强调色 tertiary 与主色 primary 的色相角差，由低到高）：")
    for name, d in sorted(summary, key=lambda x: x[1]):
        print(
            f"  {name:<12} tertiary Δhue = {d:5.0f}°  "
            f"{'✓ 互补' if d >= 120 else ('△ 弱对比' if d >= 45 else '✗ 同色系·单调')}"
        )
    print("=" * 64)
    return 0


if __name__ == "__main__":
    sys.exit(main())
