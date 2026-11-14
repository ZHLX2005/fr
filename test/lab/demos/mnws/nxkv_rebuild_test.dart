import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/mnws_app_views.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_queue_view.dart';

/// 「主页面一直 loading」的回归用例（第 2 轮验收反馈）。
///
/// 病根不在数据：`NxKvController` 是 ChangeNotifier，但**它不替谁重建界面**。
/// 第 1 轮三个视图都是「在 build 里读 controller 字段」的静态 widget，
/// 谁也没订阅 —— `bootstrap()` 跑完 `notifyListeners()` 发出去了，主区没人接，
/// 于是 `loading` 早在 controller 里变成 false，转圈还一直转。
/// 当时唯一能看见真数据的地方是抽屉：它自己 `addListener` 了。
///
/// 修法是在视图根上包一层 `NxKvScope`（见 `nxkv_widgets.dart`）。
/// 这个用例锁的就是「通知之后界面得跟着动」——把那一层摘掉它会变红。
void main() {
  const topic = kv.LocaltaskListTopic(
    key: 'board/kv_fr',
    name: 'fr',
    cwd: 'D:/DevProjects/my/github/fr',
    summary: '现状一句话',
    waiting: false,
    pending: 1,
    claimed: 0,
    done: 0,
    total: 1,
  );

  testWidgets('bootstrap 完成后主区不再转圈（视图订阅了 controller）', (tester) async {
    final c = _StubController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NxKvQueueView(controller: c, onOpen: (_) {})),
    ));

    // 第 1 帧：还没有主题 → 整屏转圈（这正是用户看到的画面）
    expect(c.loading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 模拟 bootstrap 的结果：controller 里状态变了，然后通知一次
    c.topics = const [topic];
    c.loading = false;
    c.select(topic.key);

    await tester.pump();

    // 通知得有人接：转圈下去，换成「这个主题还没有任务」
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('这个主题还没有任务'), findsOneWidget);
  });

  testWidgets('拉不到主题时报错可重试，而不是永远转圈', (tester) async {
    final c = _StubController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NxKvQueueView(controller: c, onOpen: (_) {})),
    ));

    c.loading = false;
    c.error = '连不上 mn-ws 服务：Connection refused';
    c.notify(); // controller 侧发一次通知，看界面接不接
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('连不上 nx-kv'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

/// 只测「界面跟不跟得上通知」，所以把网络那三个入口全部悬空：
/// 这一层不该为了跑一个渲染用例去连桥。
class _StubController extends NxKvController {
  _StubController()
      : super(
          target: MnWsAppTarget(
            pc: const MnWsPcGroup(
              bridgeId: 'laptop-test',
              name: 'test-pc',
              userId: 'u1',
              connectedAt: '',
              apps: [],
            ),
            pcApp: const MnWsPcApp(
              app: 'nx-kv',
              title: 'nx-kv',
              port: null,
              base: null,
              bridgeId: 'laptop-test',
              active: true,
            ),
          ),
          // 指向一个没人听的端口：真发请求也不会成功，而下面的覆写让它压根不发
          endpoint: MnWsEndpoint(
            baseUrl: 'http://127.0.0.1:9',
            grantReader: () async => null,
          ),
        );

  @override
  Future<void> refresh() async {}

  @override
  Future<void> checkContract() async {}

  @override
  Future<void> loadTasks({String? status}) async {}

  /// `notifyListeners` 是 @protected：由子类代发，用例里就能正常触发一次通知。
  void notify() => notifyListeners();
}
