// 游戏中心 - 主页直入的独立游戏列表页面
//
// 通过 part of 复用 LabPage 的 _ScrollRevealGrid / _openDemoPage 等私有 widget，
// 保持与 LabPage 同一套渲染/打开/收藏/背景图体验，零组件代码重复。
//
// 添加新游戏：让新 demo override `type => DemoType.game` 即可自动出现在本页面。

part of 'lab_page.dart';

class GameCenterPage extends StatelessWidget {
  const GameCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final games = demoRegistry.getAll().filterByType(DemoType.game);

    return Scaffold(
      appBar: AppBar(title: const Text('游戏中心')),
      body: _ScrollRevealGrid(
        demos: games,
        controller: ScrollController(),
        onDemoTap: (demo) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _DemoDetailPage(demo: demo)),
          );
        },
        physics: const BouncingScrollPhysics(),
      ),
    );
  }
}
