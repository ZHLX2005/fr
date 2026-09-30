import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/ai_chat/pi/pi_chat.dart';

/// 第 17 次复评 P-1/P-2/P-3/P-5 行为守护测试。
///
/// 这些断言的价值：UX 打磨很容易在重构中被"顺手删掉"——
/// 删除撤销窗从单例 timer 退化成 map，幽灵回归 (ghost-zombie) 复发；
/// 复制反馈从静默退回成 SnackBar 噪声；Regenerate 招牌动作被埋没。
/// 这里把它们钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PiChatSettings> settings() async =>
      PiChatSettings(await SharedPreferences.getInstance());

  setUp(() => SharedPreferences.setMockInitialValues({
        'pi_chat.baseUrl': 'http://127.0.0.1:1',
        'pi_chat.token': 'nxas_d1.fake.fake',
        'pi_chat.cwd': '/data',
      }));

  testWidgets('首屏不崩（P-5 Regenerate 入口未破坏页面）', (tester) async {
    final s = await settings();
    await tester.pumpWidget(MaterialApp(home: PiChatPage(settings: s)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('pi 对话'), findsOneWidget,
        reason: '首屏空态标题在场（说明 onRegenerate 分支没把页面崩了）');
  });

  test('P-1：撤销窗 Timer 改 per-sessionId map（不再是单例字段）',
      () async {
    final src =
        File('lib/core/ai_chat/pi/pi_session_list_page.dart').readAsStringSync();
    // 过滤掉注释行（仅检视活跃代码）
    final liveCode = src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');
    expect(liveCode.contains('_pendingDeleteTimer'), isFalse,
        reason: '活跃代码里单例字段 _pendingDeleteTimer 必须删除（注释里允许提及）');
    // map 字段在场
    expect(src.contains('_pending'), isTrue,
        reason: 'per-sessionId Timer map 必须存在');
    // 每个 _PendingDelete 都有独立 timer
    expect(src.contains('startTimer'), isTrue,
        reason: '每条会话独立 timer（startTimer 入口）');
    // dispose 时统一 cancel map 中所有 Timer
    expect(src.contains('for (final p in _pending.values)'), isTrue,
        reason: 'dispose 时必须取消 map 中所有未 commit 的 timer');
  });

  test('P-3：复制改静默哑弹（_showCopyFeedback 不再 SnackBar）', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_page.dart').readAsStringSync();
    // 节流方法只剩震动
    final methodBody = src.split('_showCopyFeedback(BuildContext')[1]
        .split('\n  }')[0];
    expect(methodBody.contains('HapticFeedback.selectionClick()'), isTrue,
        reason: '_showCopyFeedback 必须调用震动反馈');
    expect(methodBody.contains('showSnackBar'), isFalse,
        reason: '_showCopyFeedback 必须彻底去掉 SnackBar 路径');
  });

  test('P-5：controller.regenerate 方法已落地', () async {
    final src =
        File('lib/core/ai_chat/pi/pi_chat_controller.dart').readAsStringSync();
    expect(src.contains('Future<void> regenerate('), isTrue,
        reason: 'controller 必须有 regenerate 入口');
    // 必须复用 _turnAssistantKey 锚点或不污染前一轮回复
    expect(src.contains('reuseUserMessage: true'), isTrue,
        reason: 'regenerate 必须复用原 user 气泡（同 send 入口）');
  });

  test('P-5：_Bubble.onRegenerate 已接 controller 调 regenerate（）', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_page.dart').readAsStringSync();
    expect(src.contains('onRegenerate'), isTrue,
        reason: '_Bubble 必须有 onRegenerate 字段');
    expect(src.contains("label: const Text('重新生成')"), isTrue,
        reason: '按钮文本必须是「重新生成」');
    expect(src.contains('_controller.regenerate(m)'), isTrue,
        reason: '调用方必须把 _Bubble.onRegenerate 接到 controller.regenerate');
    // 第 18 轮：降级路径 — regenerateEnabled 字段 + tooltip
    expect(src.contains('regenerateEnabled'), isTrue,
        reason: '_Bubble 必须有 regenerateEnabled 字段');
    expect(src.contains('正在生成中，请先中止'), isTrue,
        reason: '降级 tooltip 必须存在');
    // 第 19 轮：失败气泡（m.error != null）的「重新生成」入口必须真打开
    // —— commit fe5fc007 声称"失败的助手气泡也显示"，但代码两处
    // m.error == null 守卫没去掉；本次真改后必须在活跃代码里 0 命中。
    final liveCode = src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');
    expect(liveCode.contains('m.error == null'), isFalse,
        reason: '第 19 轮真修：活跃代码里 m.error == null 守卫必须清除');
  });

  test('P-2：输入区 maxHeight=140 + maxLines=null 仍在', () async {
    final src = File('lib/core/ai_chat/pi/pi_chat_ui.dart').readAsStringSync();
    expect(src.contains('maxLines: null'), isTrue,
        reason: 'TextField 必须支持无限行');
    expect(src.contains('maxHeight: 140'), isTrue,
        reason: '输入框必须封顶');
    // PiComposer 子树内（class PiComposer 行 120 起 → 下一个 class _*）
    // 必须没有 SingleChildScrollView 包裹 TextField —— 这就是 P-2
    // 注释漂移的实质：声称有但没写。
    final composerStart = src.indexOf('class PiComposer');
    final afterComposer = src.substring(composerStart);
    final nextClass = afterComposer.indexOf('\nclass ');
    final composerScope = nextClass < 0
        ? afterComposer
        : afterComposer.substring(0, nextClass);
    final liveComposer = composerScope.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');
    expect(liveComposer.contains('SingleChildScrollView'), isFalse,
        reason: 'PiComposer 活跃代码里不能有 SingleChildScrollView 包裹 TextField');
  });
}