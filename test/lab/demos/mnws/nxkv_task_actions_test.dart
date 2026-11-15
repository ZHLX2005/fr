import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_controller.dart';
import 'package:xiaodouzi_fr/core/note/note_root_scope.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_task_view.dart';

/// 一条任务的**动作条**与**附件**（第 4 轮反馈第二、三条）。
///
/// 两条都是「用户看得见、但以前做错了」的地方：
///   · 动作条原来按状态在「领取 / 标完成」之间切 —— 现在只留「标完成」；
///   · 附件原来只报 PC 上的路径 —— 现在图片要真的画出来（字节经桥取回）。
void main() {
  kv.LocaltaskGetOutput task({String status = 'claimed'}) => kv.LocaltaskGetOutput.fromJson({
        'id': 3,
        'text': '# 优化样式\n\n正文',
        'status': status,
        'round': 1,
        'roundSummary': '',
        'reopenCount': 0,
        'childCount': 0,
        'childRoundCount': 0,
        'createdAt': '2026-11-15T05:47:41Z',
        'consumedAt': status == 'claimed' ? '2026-11-15T05:50:00Z' : '',
        'pickupSec': status == 'claimed' ? 139 : null,
        'completedAt': '',
        'doneAt': '',
        'feedback': '',
        'claimedBy': status == 'claimed' ? 'agent' : '',
        'claimedByName': status == 'claimed' ? 'agent' : '',
        'claimedFrom': 'local',
        'ready': status == 'pending',
        'blocksFollowing': false,
        'blockBy': <String>[],
        'deletedAt': '',
        'archivedAt': '',
        'archivedReason': '',
        'attachments': [
          {
            'id': 'a123729ded0766277b9e91500b2a98a3',
            'kind': 'file',
            'kindLabel': '图片',
            'name': '样式对比.png',
            'sizeText': '9 B',
            'isImage': true,
            'size': 9,
            'mime': 'image/png',
            'localPath': 'D:/w/nxkv/样式对比.png',
            'exists': true,
          },
        ],
      });

  Future<void> pump(WidgetTester tester, _StubController c) async {
    await tester.pumpWidget(MaterialApp(
      home: NoteRootScope(
        noteRoot: NoteFactory.create(),
        child: Scaffold(body: NxKvTaskView(controller: c, id: 3, topicKey: 'k')),
      ),
    ));
    // 第一帧：正文先到；第二帧：附件的字节也回来了
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('动作条只有「标完成」，没有「领取」', (tester) async {
    await pump(tester, _StubController(taskOutput: task()));

    expect(find.text('标完成'), findsOneWidget);
    expect(find.text('领取'), findsNothing);
    expect(find.text('反馈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未领取的任务也照样给「标完成」（拦不拦是服务端的事）', (tester) async {
    await pump(tester, _StubController(taskOutput: task(status: 'pending')));

    expect(find.text('标完成'), findsOneWidget);
    expect(find.text('领取'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片附件：字节经网络取回，内联画出来', (tester) async {
    final c = _StubController(taskOutput: task());
    await pump(tester, c);

    // 真的去取了（不是只显示一行路径）
    expect(c.fetchedIds, ['a123729ded0766277b9e91500b2a98a3']);
    // 附件区渲染成 Image，而不是一段文件名
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('样式对比.png'), findsOneWidget);
    // PC 上的路径仍然透出（agent 侧的事实），但已经不再是唯一答案
    expect(find.textContaining('PC 上：D:/w/nxkv/样式对比.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('附件取不回来：只在附件那一条说清，不连累正文', (tester) async {
    final c = _StubController(taskOutput: task(), failAttachments: true);
    await pump(tester, c);

    expect(find.text('#3'), findsOneWidget); // 正文照常
    expect(find.textContaining('取不回来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '附件失败不该变成整页异常');
  });
}

class _StubController extends NxKvController {
  _StubController({required this.taskOutput, this.failAttachments = false})
      : super(
          target: const MnWsAppTarget(
            pc: MnWsPcGroup(bridgeId: 'pc', name: 'test-pc', userId: 'u1', connectedAt: '', apps: []),
            pcApp: MnWsPcApp(
              app: 'nx-kv',
              title: 'nx-kv',
              port: null,
              base: null,
              bridgeId: 'pc',
              alive: true,
            ),
          ),
          endpoint: MnWsEndpoint(baseUrl: 'http://127.0.0.1:9', grantReader: () async => null),
        );

  final kv.LocaltaskGetOutput taskOutput;
  final bool failAttachments;

  /// 用例断言「真的为哪些 id 取了字节」。
  final List<String> fetchedIds = [];

  @override
  Future<kv.LocaltaskGetOutput> task(int id, String? key) async => taskOutput;

  @override
  Future<Uint8List> attachmentBytes(String fileId) async {
    fetchedIds.add(fileId);
    if (failAttachments) {
      throw const MnWsException(MnWsErrorKind.unreachable, '桥断了');
    }
    return _png;
  }

  static final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
}
