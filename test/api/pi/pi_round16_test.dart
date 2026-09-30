import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/ai_chat/pi/pi_chat.dart';

/// 第 16 次复评 P-1/P-3/P-4 行为守护测试。
///
/// 这些断言的价值：UX 打磨很容易在重构中被"顺手删掉"——
/// 复制按钮又被 `&& !isUser` 漏掉 user 气泡、撤销窗又会变成即删即清空、
/// 节流又把 SnackBar 加回来。这里把它们钉住。
///
/// 策略：
/// - **视觉行为**（按钮位置/光标形态）无法在测试里可靠断言，钉代码即可。
/// - **行为路径**（撤销窗、节流、复制按钮）通过 widget 测试 + 源文标记符
///   双管齐下。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PiChatSettings> settings() async =>
      PiChatSettings(await SharedPreferences.getInstance());

  setUp(() => SharedPreferences.setMockInitialValues({
        'pi_chat.baseUrl': 'http://127.0.0.1:1',
        'pi_chat.token': 'nxas_d1.fake.fake',
        'pi_chat.cwd': '/data',
      }));

  testWidgets('PiChatPage 渲染空态（首屏不崩 — 双向复制分支无破坏）',
      (tester) async {
    final s = await settings();
    await tester.pumpWidget(MaterialApp(home: PiChatPage(settings: s)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('pi 对话'), findsOneWidget,
        reason: '空态标题在场（说明双向复制分支没把页面崩了）');
  });

  test('P-4：复制节流静态入口已落地', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_page.dart').readAsStringSync();
    expect(src.contains('_showCopyFeedback'), isTrue,
        reason: '第 16 轮必须落地复制节流静态入口');
    // 第 17 轮：节流策略改为彻底静默（任何时候都只震动）——
    // _lastCopyAtMs 时间戳字段已删除，_showCopyFeedback 只调震动。
    expect(src.contains('HapticFeedback.selectionClick()'), isTrue,
        reason: '第 17 轮：_showCopyFeedback 必须仍调震动反馈');
    // 复制反馈不得弹 SnackBar（与 ChatGPT/Claude 一致的零反馈静默）
    final methodBody = src.split('_showCopyFeedback(BuildContext')[1]
        .split('\n  }')[0];
    expect(methodBody.contains('showSnackBar'), isFalse,
        reason: '第 17 轮：_showCopyFeedback 内部不得有 showSnackBar');
  });

  test('P-4：会话列表撤销窗辅助类已落地', () async {
    final src =
        File('lib/core/ai_chat/pi/pi_session_list_page.dart').readAsStringSync();
    expect(src.contains('_PendingDelete'), isTrue,
        reason: '撤销窗辅助类必须落地');
    expect(src.contains('_actuallyDelete'), isTrue,
        reason: '真删除必须延后到撤销窗结束');
    expect(src.contains('撤销'), isTrue,
        reason: 'SnackBarAction 必须展示给用户');
    // undo 路径必须真插入（不是只标记 _committed=true 了事）
    expect(src.contains('_restoreRow'), isTrue,
        reason: '撤销时必须把 row 重新插入 _rows');
  });

  test('P-1：用户气泡复制按钮已去掉 !isUser 守卫', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_page.dart').readAsStringSync();
    // 第 16 轮前：复制按钮带 && !isUser 守卫；第 16 轮后：守卫删除，
    // 取舍的是 `message.text.isNotEmpty && !isStreaming`。
    expect(src.contains('&& !isStreaming)'), isTrue,
        reason: '复制按钮守卫必须是 !isStreaming（不是 !isUser）');
    // 双重防御：确认旧守卫 !isUser 不再单独存在（不在 comment 里）
    final liveCode = src.split('\n').where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(!liveCode.contains('!isStreaming && !isUser'), isTrue,
        reason: '旧 !isUser 守卫必须从活跃代码清除');
  });

  test('P-3：错误横幅有「重试」按钮（与失败气泡的「重发」对称）', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_page.dart').readAsStringSync();
    expect(src.contains("label: const Text('重试')"), isTrue,
        reason: '错误横幅必须挂「重试」按钮');
  });

  test('P-7：流式光标改竖线（2px 宽 + AnimatedOpacity 周期）', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_page.dart').readAsStringSync();
    expect(src.contains('width: 2,'), isTrue,
        reason: '光标宽度必须是 2px（不是 8px 方块）');
    expect(src.contains('AnimatedOpacity') ||
            src.contains('Opacity('), isTrue,
        reason: '光标动画必须是 Opacity 周期而非 FadeTransition 整块');
  });

  test('P-2：PiComposer maxLines=null + ConstrainedBox.maxHeight=140',
      () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_ui.dart').readAsStringSync();
    expect(src.contains('maxLines: null'), isTrue,
        reason: 'TextField 必须支持无限行（与外层 maxHeight 配合内滚）');
    expect(src.contains('maxHeight: 140'), isTrue,
        reason: '输入框必须封顶（不撑爆 composer）');
  });
}