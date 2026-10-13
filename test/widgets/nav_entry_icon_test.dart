// NavEntryIcon 渲染分流 + LabDemoIcon 换色正确性：
//
// 1. colorizeLabSvg：#2B3445 → ink、#5B7CFA → accent，原色值不残留
// 2. NavEntryIcon：labIconAsset 非 null 渲染 SvgPicture，null 走 Icon
// 3. 单色压制：accentColor == inkColor 时强调点与轮廓同色
//
// 注意 test/ 被 gitignore 拦新增，收录需 git add -f。

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/nav/nav_entry.dart';
import 'package:xiaodouzi_fr/core/theme/colors/strategy/color_strategy/color_strategy.dart';
import 'package:xiaodouzi_fr/core/theme/colors/strategy/color_strategy/themes/default.dart';
import 'package:xiaodouzi_fr/widgets/lab_demo_icon.dart';
import 'package:xiaodouzi_fr/widgets/nav_entry_icon.dart';

NavEntry _entry({String? labIconAsset}) => NavEntry(
      id: 'demo:clock',
      title: '时钟',
      icon: Icons.access_time,
      group: NavGroup.lab,
      labIconAsset: labIconAsset,
      builder: (_) => const SizedBox.shrink(),
    );

const _svg2Color =
    '<svg viewBox="0 0 32 32"><path fill="#2B3445"/><path fill="#5B7CFA"/></svg>';

/// 快捷造一个指定 primary 的 strategy（text 取 scheme.onSurface）。
ColorStrategy _strategy(Color primary, Color onSurface) =>
    DefaultColorStrategy(
      scheme: ColorScheme.light(primary: primary, onSurface: onSurface),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colorizeLabSvg 换色', () {
    test('ink / accent 双角色替换，原设计色不残留', () {
      final out = colorizeLabSvg(
        _svg2Color,
        ink: const Color(0xFF7A9A7E), // 茶禅 primary
        accent: const Color(0xFFA0594A), // 陶土红
      );
      expect(out.contains('#2B3445'), isFalse, reason: '轮廓原色残留');
      expect(out.contains('#5B7CFA'), isFalse, reason: '强调原色残留');
      expect(out.contains('#7A9A7E'), isTrue, reason: '轮廓未换成 ink');
      expect(out.contains('#A0594A'), isTrue, reason: '强调未换成 accent');
    });

    test('半透明 ink 保留 alpha（8 位 hex）——底栏未选中态区分的关键', () {
      final out = colorizeLabSvg(
        _svg2Color,
        ink: Colors.white.withValues(alpha: 0.42), // 底栏未选中 tint
        accent: const Color(0xFF163A94),
      );
      // 8 位写法 #RRGGBBAA，42% ≈ 0x6B
      expect(out.contains(RegExp(r'#FFFFFF6B', caseSensitive: false)), isTrue,
          reason: 'alpha 丢失会让未选中图标渲染成全亮度（曾因此选中/未选中无区别）');
    });

    test('双色压单色：ink == accent 时强调点与轮廓同色', () {
      final out = colorizeLabSvg(
        _svg2Color,
        ink: const Color(0xFF123456),
        accent: const Color(0xFF123456),
      );
      // 剩余 hex 色值只有一种
      final hexes = RegExp(r'#[0-9A-F]{6}')
          .allMatches(out)
          .map((m) => m.group(0))
          .toSet();
      expect(hexes, {'#123456'});
    });
  });

  group('adaptiveLabIconColors 明度差自适应', () {
    test('亮色主题：深 primary（cobalt 宝蓝）自动提亮到 L0.62', () {
      final cobalt = const Color(0xFF163A94);
      final (ink, accent) = adaptiveLabIconColors(
        _strategy(cobalt, const Color(0xFF1A1A1A)),
        Brightness.light,
      );
      expect(ink, const Color(0xFF1A1A1A), reason: '轮廓不动');
      expect(accent, isNot(cobalt), reason: '深 primary 未提亮');
      expect(HSLColor.fromColor(accent).lightness, closeTo(0.62, 0.01));
    });

    test('亮色主题：明度差已够（柠檬亮黄）原样返回', () {
      final lemon = const Color(0xFFE4C44A);
      final (ink, accent) = adaptiveLabIconColors(
        _strategy(lemon, const Color(0xFF2C2A24)),
        Brightness.light,
      );
      expect(ink, const Color(0xFF2C2A24));
      expect(accent, lemon);
    });

    test('深色主题：轮廓压暗 35%，accent（primary）成为最亮元素', () {
      final darkInk = const Color(0xFFE8E7E3);
      final darkPrimary = const Color(0xFFC9C5BD); // 暗黑 primary
      final (ink, accent) = adaptiveLabIconColors(
        _strategy(darkPrimary, darkInk),
        Brightness.dark,
      );
      expect(accent, darkPrimary, reason: '深色主题 accent 不动');
      expect(
        HSLColor.fromColor(ink).lightness,
        lessThan(HSLColor.fromColor(accent).lightness),
        reason: '压暗后轮廓必须暗于强调点，否则强调点糊在轮廓里',
      );
    });
  });

  group('NavEntryIcon 渲染分流', () {
    testWidgets('labIconAsset 非 null → SvgPicture（SVG）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavEntryIcon(entry: _entry(labIconAsset: '01-clock')),
        ),
      );
      // rootBundle 异步加载中先等一帧；断言目标是 SvgPicture 而非 Icon
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('labIconAsset null → Material Icon 兜底', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NavEntryIcon(entry: _entry())),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });
}
