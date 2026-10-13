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
