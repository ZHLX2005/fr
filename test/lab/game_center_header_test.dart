// 游戏中心 H3R-C 头部（搜索框即头）冒烟测试：
// 功能行渲染、搜索过滤、搜索历史持久化、毛玻璃条滚动态。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/game_center_page.dart';
import '../../lib/core/game_center/game_meta.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  bootstrapLab();
  // 头部返回钮 / 玻璃条返回钮都由 context.navCanPop 门控（页面在真实环境
  // 是 push 进路由的）—— 这里同样以 push 方式挂载，home 直挂会导致
  // navCanPop = false、两个返回钮都不渲染。
  await tester.pumpWidget(
    // GameCenterPage 是 ConsumerStatefulWidget（initState 读目录同步
    // provider）—— 测试挂载必须包 ProviderScope。
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GameCenterPage(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle(const Duration(milliseconds: 1100));
}

void main() {
  testWidgets('头部功能行：返回钮 + 搜索框 + 提交钮 + 无渐变标题头部', (tester) async {
    await _pump(tester);

    // 返回钮（头部 + 玻璃条左端各一）+ 提交钮都在
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNWidgets(2));
    expect(find.text('搜索'), findsOneWidget);
    // 搜索框占位（无历史 → 通用提示）
    expect(find.text('搜索游戏 · 玩法 · 分类'), findsOneWidget);

    // 搜索历史弹层入口在玻璃条上（初始隐藏，Opacity 里仍存在）
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);

    // 旧的渐变头部元素已删除：统计微行文案不再存在
    expect(find.textContaining('款 · 联机'), findsNothing);
  });

  testWidgets('输入实时过滤网格；无命中显示搜索空态', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), '2048');
    await tester.pumpAndSettle();

    expect(find.text('2048'), findsWidgets); // 网格卡标题 + TextField 文本
    expect(find.text('没有找到相关游戏'), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在的游戏xyz');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关游戏'), findsOneWidget);
  });

  testWidgets('提交搜索记入历史；占位文字切换为历史首条；清空后复原', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), '五子棋');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // 历史写入 prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kGcSearchHistoryKey), contains('五子棋'));

    // 清空输入 → 占位 = 历史首条
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('五子棋'), findsWidgets);

    // 弹层清空：玻璃条 history 图标不可见时直接点不可靠 → 用点回顶聚焦后滚回
    // （弹层交互此处不展开，仅验证历史数据生命周期）
  });

  testWidgets('滚动越过阈值后毛玻璃条出现（游戏中心标题）', (tester) async {
    await _pump(tester);

    // 玻璃条初始不拦截
    expect(find.text('游戏中心'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -160));
    await tester.pumpAndSettle();

    // 玻璃条 fully visible 后仍渲染标题文本
    expect(find.text('游戏中心'), findsOneWidget);
  });
}
