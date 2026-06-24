// 堆叠色卡 demo — 色卡折叠展开 + 缩放景深层叠
//
// 严格对齐 v14b 设计稿，像素级还原：
// docs/superpowers/specs/game-center-header-preview-v14b-depth.html

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../lab_container.dart';

// =============== 常量（v14b＋增高） ===============
const Color _bg = Color(0xFFF5EFE2); // 暖米浅色背景
const Color _accent = Color(0xFF60a5fa);
const double _foldH = 140.0;  // 折叠卡高（v14b 60→90→*1.8=162）
const double _fullH = 756.0;  // 展开卡高（540→*1.4）
const double _step = 108.0;   // 折叠时 top 增量
const double _reveal = 50.0;  // 紧邻展开卡露出
const double _decay = 8.0;    // 每层露出递减
const Duration _anim = Duration(milliseconds: 550);
const Curve _curve = Cubic(0.32, 0.72, 0, 1); // v14b 主曲线

// 字体系列（Cormorant Garamond 细衬线 = v14b 字体）
TextStyle _cg({double? size, FontWeight? w, Color? c, FontStyle? f, double? ls}) =>
    GoogleFonts.cormorantGaramond(
      textStyle: TextStyle(fontSize: size, fontWeight: w, color: c, fontStyle: f, letterSpacing: ls),
    );

// =============== 色卡数据 ===============
class _Card {
  final String name, tab, sub;
  final Color color, paper;
  final double tabX; // Align x 坐标
  const _Card(this.name, this.tab, this.sub, this.color, this.paper, this.tabX);
}
const List<_Card> _cards = [
  _Card('贪吃蛇', 'Peonies', 'Snake · Arcade',  Color(0xFFD9A8A0), Color(0xFFF1D9D2), -0.40),
  _Card('2048',   'Cherry',  '2048 · Puzzle',   Color(0xFFB85240), Color(0xFFEFD5CD),  0.24),
  _Card('黑白棋', 'Carolina','Othello · Board', Color(0xFFA8B5B0), Color(0xFFDDE2DD), -0.04),
  _Card('丛林斗兽','Steel',   'Jungle · Board',  Color(0xFF5D6D7A), Color(0xFFCFD5DA), -0.48),
  _Card('Line',   'Beige',   'Line · Music',    Color(0xFFE6DCC4), Color(0xFFF0E9D8), -0.84),
];

// =============== Demo 类 ===============
class StackCardDemo extends DemoPage {
  @override String get title => '堆叠色卡';
  @override String get description => '色卡折叠展开 · 缩放景深';
  @override bool get preferFullScreen => true;
  @override Widget buildPage(BuildContext context) => const _Demo();
}
void registerStackCardDemo() => demoRegistry.register(StackCardDemo());

// =============== 页面 ===============
class _Demo extends StatefulWidget {
  const _Demo();
  @override State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  int _exp = 5; // 初始 Beige

  // ---- layout（移植 v14b） ----
  List<double> _tops() {
    final t = <double>[];
    var top = 0.0, eb = 0.0, pvb = 0.0;
    var behind = false, bc = 0;
    for (var i = 0; i < 5; i++) {
      final n = i + 1, isE = n == _exp, isB = _exp > 0 && n > _exp;
      if (isE) { t.add(top); eb = top + _fullH; top = eb; behind = false; }
      else if (isB) {
        if (!behind) { pvb = eb; behind = true; bc = 0; }
        final r = _reveal - bc * _decay;
        t.add(pvb - (_foldH - r));
        pvb += r; top = pvb; bc++;
      } else { t.add(top); top += _step; }
    }
    return t;
  }
  int _dep(int n) => _exp == 0 ? n - 1 : (n - _exp).abs();
  void _tap(int n) => setState(() => _exp = _exp == n ? 0 : n);

  // z-order（展开卡最后=最上；折叠按 depth 降序）
  List<int> _order() {
    final o = List.generate(5, (i) => i + 1);
    o.sort((a, b) {
      final aE = a == _exp, bE = b == _exp;
      if (aE != bE) return aE ? 1 : -1;
      return _dep(b).compareTo(_dep(a));
    });
    return o;
  }

  @override
  Widget build(BuildContext context) {
    final tp = _tops();
    var dh = 0.0;
    for (var n = 1; n <= 5; n++) {
      final b = tp[n - 1] + (n == _exp ? _fullH : _foldH);
      if (b > dh) dh = b;
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('堆叠色卡', style: _cg(size: 18, c: Colors.black87)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.unfold_less),
            tooltip: '全部折叠',
            onPressed: () => setState(() => _exp = 0),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 32, 12, 48),
          child: AnimatedContainer(
            duration: _anim, curve: _curve, height: dh,
            child: Stack(
              clipBehavior: Clip.none,
              children: [for (final n in _order()) _card(n, tp[n - 1])],
            ),
          ),
        ),
      ),
    );
  }

  // =============== 单张色卡 ===============
  Widget _card(int n, double top) {
    final d = _cards[n - 1];
    final isE = n == _exp, dep = _dep(n);
    final scale = isE ? 1.0 : 1 - dep * 0.05;
    final sy = isE ? -8.0 : dep * 4.0 + dep * dep;
    return AnimatedPositioned(
      top: top, left: 0, right: 0,
      duration: _anim, curve: _curve,
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8 - 24,
          child: GestureDetector(
            onTap: () => _tap(n),
            behavior: HitTestBehavior.opaque,
            child: AnimatedScale(
          scale: scale, alignment: Alignment.topCenter,
          duration: _anim, curve: _curve,
          child: AnimatedContainer(
            duration: _anim, curve: _curve,
            height: isE ? _fullH : _foldH,
            transform: Matrix4.translationValues(0, sy, 0),
            decoration: BoxDecoration(
              color: d.color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isE ? _shadowE() : _shadowD(dep),
            ),
            child: LayoutBuilder(builder: (ctx, constraints) {
              final cw = constraints.maxWidth;
              final tabLeft = isE ? (cw / 2 - 48) : (cw * (d.tabX + 1) / 2);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // inner
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _inner(d, isE),
                    ),
                  ),
                  // ::before 顶部亮线
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: _topEdge(),
                  ),
                  // tab 凸耳（宽度自然 = shrink，left 按 % 定位）
                  AnimatedPositioned(
                    top: -24, left: tabLeft,
                    duration: _anim, curve: _curve,
                    child: _tab(d, isE),
                  ),
                ],
              );
            }),
          ),
        ),
          ),
        ),
      ),
    );
  }

  // =============== ::before 顶部亮线 ===============
  Widget _topEdge() => Container(
    height: 2,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Colors.transparent, Color(0x73FFFFFF), Colors.transparent],
        stops: [0.0, 0.5, 1.0],
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
  );

  // =============== tab 凸耳 ===============
  Widget _tab(_Card d, bool isE) => AnimatedContainer(
    duration: _anim, curve: _curve,
    height: isE ? 28 : 30,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    constraints: isE ? const BoxConstraints(minWidth: 96) : null,
    decoration: BoxDecoration(
      color: d.color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      border: isE ? Border.all(color: _accent, width: 2) : null,
      boxShadow: const [
        BoxShadow(color: Color(0x66000000), blurRadius: 8, spreadRadius: -2, offset: Offset(0, 4)),
      ],
    ),
    foregroundDecoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
    ),
    child: Center(
      child: Text(
        d.tab,
        style: _cg(size: isE ? 13 : 15, w: FontWeight.w500, ls: 0.6,
          c: d.color.computeLuminance() > 0.55 ? Colors.black54 : Colors.white.withValues(alpha: 0.95)),
      ),
    ),
  );

  // =============== 展开内容 ===============
  Widget _inner(_Card d, bool isE) => AnimatedOpacity(
    opacity: isE ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 400),
    child: AnimatedSlide(
      offset: Offset(0, isE ? 0.0 : 0.05),
      duration: const Duration(milliseconds: 500), curve: _curve,
      child: Container(
        color: d.paper,
        padding: const EdgeInsets.only(top: 50, bottom: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(d.tab, style: _cg(size: 56, w: FontWeight.w600, c: Colors.black87)),
            const SizedBox(height: 12),
            Text(d.sub,
              style: TextStyle(
                fontSize: 11, letterSpacing: 3.2,
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Transform.rotate(
              angle: -3 * math.pi / 180,
              child: Text(d.name, style: _cg(size: 26, c: Colors.black54)),
            ),
          ],
        ),
      ),
    ),
  );

  // =============== 阴影 ===============
  List<BoxShadow> _shadowE() => const [
    BoxShadow(color: Color(0xB8000000), blurRadius: 72, spreadRadius: -14, offset: Offset(0, 34)),
  ];
  List<BoxShadow> _shadowD(int d) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4 + d * 0.05),
      blurRadius: 14 + d * 6,
      spreadRadius: -6 - d * 2,
      offset: const Offset(0, 8),
    ),
  ];
}
