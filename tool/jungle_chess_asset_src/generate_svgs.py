#!/usr/bin/env python3
"""斗兽棋 - 双杏仁眼版 (每条眼上下两弧)"""
import os
B = r"D:\DevProjects\my\github\fr\assets\animal"
os.makedirs(B, exist_ok=True)
b="#3B82F6"; r="#EF4444"; g="#6B7280"
S='<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><g fill="none" stroke="{}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">{}</g></svg>'

def w(n,p,c=b):
    with open(os.path.join(B,n),"w",encoding="utf-8") as f:
        f.write(S.format(c,p))
def p(c,paths):
    w(f"B{c}.svg",paths,b); w(f"R{c}.svg",paths,r)

# Eye helpers: L=左眼(36→48), R=右眼(52→64), 控制y偏移决定开合
# M36 46 Q42 {up} 48 46 Q42 {down} 36 46  = 左眼
# M52 46 Q58 {up} 64 46 Q58 {down} 52 46  = 右眼

# RAT - cheeky grin, smaller asymmetric eyes
p("R",'''
<ellipse cx="50" cy="50" rx="20" ry="18"/>
<path d="M30 34 Q20 16 38 20"/>
<path d="M66 34 Q76 28 72 40"/>
<circle cx="42" cy="46" r="4"/>
<circle cx="58" cy="46" r="4"/>
<path d="M44 52 Q42 56 40 56"/>
<path d="M36 52 L26 50 M36 54 L26 54"/>
<path d="M54 52 L64 50 M54 54 L64 54"/>
<path d="M50 64 Q52 74 62 72 Q68 70 66 66"/>
<path d="M44 58 Q50 62 56 58"/>
''')

# CAT - big almond eyes, curious
p("C",'''
<ellipse cx="50" cy="48" rx="24" ry="20"/>
<path d="M28 32 L20 12 L40 24"/>
<path d="M70 30 L80 14 L60 24"/>
<path d="M38 44 L44 48 L50 44"/>
<path d="M50 44 L56 48 L62 44"/>
<path d="M48 52 L50 50 L52 52 Z"/>
<path d="M50 52 Q46 56 44 54 M50 52 Q54 56 56 54"/>
<path d="M34 52 L22 50 M34 54 L22 54"/>
<path d="M64 52 L76 50 M64 54 L76 54"/>
''')

# DOG - happy squint, floppy ears
p("D",'''
<ellipse cx="50" cy="48" rx="24" ry="20" transform="rotate(4 50 48)"/>
<path d="M26 34 Q12 24 12 42 Q12 54 26 50"/>
<path d="M72 30 Q86 26 86 44 Q86 58 72 52"/>
<circle cx="40" cy="46" r="5.5"/>
<circle cx="60" cy="46" r="5.5"/>
<circle cx="42" cy="44" r="1.8"/>
<circle cx="62" cy="44" r="1.8"/>
<ellipse cx="50" cy="54" rx="5" ry="3"/>
<path d="M46 58 Q50 62 54 58"/>
<path d="M48 58 Q50 63 52 58"/>
''')

# WOLF - sleepy narrow eyes (flat)
p("W",'''
<ellipse cx="50" cy="50" rx="22" ry="22"/>
<path d="M28 34 L20 10 L40 24"/>
<path d="M70 32 L80 12 L58 24"/>
<path d="M38 47 L50 47"/>
<path d="M50 47 L62 47"/>
<path d="M44 56 L56 56"/>
<path d="M46 56 Q50 60 54 56"/>
<path d="M38 50 L28 48 M40 52 L28 52"/>
''')

# CHEETAH - cool flat eyes
p("H",'''
<ellipse cx="50" cy="50" rx="22" ry="20"/>
<path d="M28 34 Q20 28 20 36 Q20 42 28 40"/>
<path d="M72 32 Q80 28 78 38 Q76 44 68 40"/>
<circle cx="42" cy="46" r="4"/>
<circle cx="58" cy="46" r="4"/>
<path d="M44 54 L46 52 L48 54"/>
<circle cx="44" cy="38" r="2"/>
<circle cx="56" cy="36" r="2"/>
<circle cx="50" cy="34" r="1.5"/>
''')

# TIGER - biggest, most open eyes (innocent)
p("T",'''
<ellipse cx="50" cy="50" rx="26" ry="22"/>
<path d="M26 36 Q16 30 16 40 Q16 48 26 46"/>
<path d="M74 36 Q84 30 84 40 Q84 48 74 46"/>
<path d="M36 46 Q44 42 52 46 Q44 48 36 46"/>
<path d="M48 46 Q56 42 64 46 Q56 48 48 46"/>
<path d="M48 52 L50 50 L52 52"/>
<path d="M50 52 Q48 56 46 54 M50 52 Q52 56 54 54"/>
<path d="M44 32 L44 36 M50 30 L50 36 M56 32 L56 36"/>
<path d="M24 44 L32 42 M24 52 L32 50"/>
<path d="M76 44 L68 42 M76 52 L68 50"/>
''')

# LION - gentle medium eyes
p("L",'''
<ellipse cx="50" cy="50" rx="22" ry="18"/>
<path d="M28 36 Q14 20 20 10 Q30 6 36 18"/>
<path d="M42 14 Q50 4 58 14"/>
<path d="M64 18 Q72 8 78 16 Q82 26 68 36"/>
<path d="M20 44 Q6 42 4 52 Q4 62 16 60"/>
<path d="M80 44 Q94 42 96 52 Q96 62 84 60"/>
<path d="M28 64 Q22 76 30 80 Q38 82 42 70"/>
<path d="M72 64 Q78 76 70 80 Q62 82 58 70"/>
<circle cx="42" cy="46" r="4"/>
<circle cx="58" cy="46" r="4"/>
<path d="M48 52 L50 50 L52 52"/>
<path d="M50 52 Q48 55 46 54 M50 52 Q52 55 54 54"/>
''')

# ELEPHANT - calm medium eyes (ORIGINAL style + eyes)
p("E",'''
<ellipse cx="50" cy="48" rx="28" ry="22"/>
<path d="M66 36 Q86 34 84 54 Q82 70 64 60"/>
<path d="M42 48 Q34 56 34 68 Q34 78 40 78 Q46 78 44 72 Q42 68 44 62"/>
<circle cx="42" cy="44" r="4"/>
<circle cx="58" cy="44" r="4"/>
<path d="M46 54 Q44 60 40 62"/>
<path d="M34 36 Q16 38 18 52 Q20 62 32 56"/>
''')

# TERRAIN
w("trap.svg",'\n<polygon points="50,18 78,32 78,68 50,82 22,68 22,32"/>\n<line x1="36" y1="38" x2="64" y2="62"/>\n<line x1="64" y1="38" x2="36" y2="62"/>\n<circle cx="50" cy="50" r="7"/>',g)
w("den.svg",'\n<path d="M24 62 L24 88 L76 88 L76 62 Q50 18 24 62"/>\n<path d="M32 64 Q50 36 68 64"/>',g)

# HTML
A=[("鼠Rat","R",1),("猫Cat","C",2),("狗Dog","D",3),("狼Wolf","W",4),
   ("豹Cheetah","H",5),("虎Tiger","T",6),("狮Lion","L",7),("象Elephant","E",8)]
grd=""
for n,c,r in A:
    grd+=f'<div class="p"><div class="l">Lv.{r}</div><div class="rw"><div class="b"><img src="B{c}.svg"><span>B{c}</span></div><div class="rd"><img src="R{c}.svg"><span>R{c}</span></div></div><div class="nm">{n}</div></div>'
H=f'''<!DOCTYPE html><html lang="zh"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>斗兽棋 v5</title><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,"Noto Sans SC",sans-serif;background:#f8fafc;color:#1e293b;padding:32px}}
h1{{font-size:22px;font-weight:600;text-align:center}}
.sub{{color:#64748b;text-align:center;margin-bottom:20px;font-size:13px}}
.wrap{{max-width:960px;margin:0 auto}}
.g{{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:24px}}
.p{{background:#fff;border-radius:12px;padding:12px;box-shadow:0 1px 3px rgba(0,0,0,.08)}}
.l{{font-size:11px;color:#94a3b8}}
.rw{{display:flex;gap:8px;justify-content:center}}
.b,.rd{{flex:1;text-align:center;padding:10px 4px;border-radius:8px}}
.b{{background:#eff6ff}} .rd{{background:#fef2f2}}
.b img,.rd img{{width:72px;height:72px;display:block;margin:0 auto 4px}}
.b span,.rd span{{font-size:11px;font-family:monospace}}
.nm{{text-align:center;font-size:12px;margin-top:4px}}
.le{{display:flex;justify-content:center;gap:20px;margin:14px 0 10px;font-size:13px}}
.le .x{{padding:4px 12px;border-radius:4px}}
.le .b{{background:#eff6ff;color:#1d4ed8}} .le .rd{{background:#fef2f2;color:#dc2626}}
.te{{display:flex;gap:20px;justify-content:center;max-width:400px;margin:0 auto}}
.te .c{{flex:1;background:#f1f5f9;border-radius:8px;padding:12px;text-align:center}}
.te .c img{{width:56px;height:56px}}
.te .c span{{font-size:11px;font-family:monospace}}
@media(max-width:640px){{.g{{grid-template-columns:repeat(2,1fr)}}}}
</style></head><body><div class="wrap">
<h1>斗兽棋 - 动物头部 v5</h1>
<div class="sub">双杏仁眼(上下两弧) · 椭圆头 · 不对称 · 蓝#3B82F6 红#EF4444</div>
<div class="le"><span class="x b">蓝方 Blue</span><span class="x rd">红方 Red</span></div>
<div class="g">{grd}</div>
<div class="le">棋盘地形</div>
<div class="te"><div class="c"><img src="trap.svg"><span>trap 陷阱</span></div><div class="c"><img src="den.svg"><span>den 兽穴</span></div></div>
<div class="sub" style="margin-top:20px">assets/animal/</div>
</div></body></html>'''

with open(os.path.join(B,"preview.html"),"w",encoding="utf-8") as f:
    f.write(H)
print("[OK] preview.html\nDone!")
