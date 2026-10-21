// lib/core/remotetype/rt_text_sync.dart
//
// 文本同步管线：控制器监听 → composing 挂起/补发 → 250ms 防抖 → syncText。
// 会话与端到端状态经 getter 注入，结果经回调交还页面（记账 / 落历史 / 清空 /
// 提示），本类不持有 BuildContext、不感知 UI。

import 'dart:async';

import 'package:flutter/material.dart';

import 'rt_constants.dart';
import 'rt_session.dart';

/// 文本同步管线（页面持有一份，随页面销毁）。
class RtTextSync {
  RtTextSync({
    required this.controller,
    required this.resolveSession,
    required this.isE2eOk,
    required this.enterMode,
    required this.onSyncSent,
    required this.persistHistory,
    required this.onFlushed,
    required this.onNotify,
  });

  /// 监听对象（页面负责 addListener/removeListener）。
  final TextEditingController controller;

  /// 当前会话；null（未连接）时同步静默跳过——与原行为一致。
  final RtSession? Function() resolveSession;

  /// 端到端是否已确认（决定要不要挂「核对配对 key」提示）。
  final bool Function() isE2eOk;

  /// 回车注入方式：'enter' = 发送 / 'shift_enter' = 换行。
  final String Function() enterMode;

  /// 一包文本同步成功：页面记账（syncSent++）+ 闪「已同步」。
  final void Function() onSyncSent;

  /// 发送模式收尾：正文落历史（页面负责 RtPrefs.pushHistory + setState）。
  final Future<void> Function(String body) persistHistory;

  /// 一轮发送收尾：清识别基线 + 清输入框（发送模式 flush 与空卡回车共用）。
  final void Function() onFlushed;

  /// 需要用户看见的提示（页面负责 mounted 守卫 + SnackBar）。
  final void Function(String message) onNotify;

  Timer? _debounce;
  // 合成区缓滞上传：输入法语音识别常把已识别汉字长期留在 composing 区
  Timer? _composingTimer;
  // 配对未确认提示：key 不一致时 PC 端会静默丢弃全部信封，
  // 不提示的话用户只看到「打了字没同步」，无从自查
  Timer? _e2eHintTimer;
  bool _e2eHintShown = false;
  // 控制器事件状态：onChanged 只在文本变化时触发，「结束合成」（composing
  // 清空但文本不变）那帧只有 controller 监听能捕获——语音文字卡同步的根因
  bool _wasComposing = false;
  String _lastText = '';
  bool _disposed = false;

  /// 端到端确认到达：撤掉待发的提示（_e2eHintShown 不重置，见 rt_page _onEvent）。
  void cancelE2eHint() {
    _e2eHintTimer?.cancel();
  }

  /// 新会话建立 / 显式断开 / 重连：重置一次性提示位。
  void resetHint() {
    _e2eHintTimer?.cancel();
    _e2eHintShown = false;
  }

  /// 会话拆除前挂起未决任务（防抖 / 合成补发 / 提示）。
  void cancelPending() {
    _debounce?.cancel();
    _composingTimer?.cancel();
    _e2eHintTimer?.cancel();
  }

  void dispose() {
    _disposed = true;
    cancelPending();
  }

  /// 控制器级监听（不用 onChanged：它只在文本变化时触发，收尾帧捕获不到）。
  ///
  /// 输入法语音的完整事件序列：
  ///   ① 语音逐字上屏：文本变 + composing 挂着 → 挂起（拼音中间态不上传）
  ///   ② 结束合成：composing 清空但【文本不变】→ 只有这里能捕获 → 补发
  ///   ③ 部分输入法从不结束合成 → 静默 1.5s 且合成区已是汉字 → 直接上传
  void onControllerChanged() {
    final v = controller.value;
    final composing = v.composing != TextRange.empty;
    final textChanged = v.text != _lastText;

    if (composing) {
      _wasComposing = true;
      if (!textChanged) return; // 纯光标/选区移动
      _lastText = v.text;
      _composingTimer?.cancel();
      _composingTimer = Timer(const Duration(milliseconds: 1500), () {
        final vv = controller.value;
        if (_disposed || vv.composing == TextRange.empty) return;
        if (_hasCjk(vv.composing.textInside(vv.text))) {
          _lastText = vv.text;
          scheduleSync();
        }
      });
      return;
    }

    _composingTimer?.cancel();
    final wasComposing = _wasComposing;
    _wasComposing = false;
    if (textChanged || wasComposing) {
      _lastText = v.text;
      scheduleSync();
    }
  }

  /// 是否含 CJK 统表汉字（语音识别中间结果；拼音拼写中间态只含 ASCII）
  static bool _hasCjk(String s) {
    for (final r in s.runes) {
      if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) {
        return true;
      }
    }
    return false;
  }

  /// 立即排一笔同步（输入合成收尾、切发送模式、历史回填共用入口）。
  void scheduleSync() {
    if (_disposed) return;
    final session = resolveSession();
    if (session == null) return;
    // 配对未确认：延迟 2.5s 仍无 ACK 则提示一次（正常 ACK 往返 < 1s）
    if (!isE2eOk()) {
      _e2eHintTimer?.cancel();
      _e2eHintTimer = Timer(const Duration(milliseconds: 2500), () {
        if (_disposed || isE2eOk() || _e2eHintShown) return;
        _e2eHintShown = true;
        onNotify(
          '电脑端未确认配对：请核对两端配对 key 是否完全一致'
          '（电脑端重启 serve 会生成新 key）',
        );
      });
    } else {
      _e2eHintTimer?.cancel();
    }
    _debounce?.cancel();
    _debounce = Timer(kRtSyncDebounce, () {
      if (_disposed) return;
      final text = controller.text;
      // 发送模式 + 句尾 Enter =「发送」：PC 端注入 Enter 后目标框清空、
      // mirror 归零（rt-align commitApplied），手机端同步清空开始新一条，
      // 两侧对齐到空。空卡回车（只有换行）不发包，直接开新卡。
      final flushAfterSend = enterMode() == 'enter' && text.endsWith('\n');
      if (flushAfterSend && text.trim().isEmpty) {
        onFlushed();
        return;
      }
      session
          .syncText(text, enterMode: enterMode())
          .then((sent) async {
            if (_disposed) return;
            if (sent) {
              onSyncSent();
              if (flushAfterSend) {
                final body = text.replaceFirst(RegExp(r'\n+$'), '').trim();
                if (body.isNotEmpty) {
                  await persistHistory(body);
                }
                onFlushed();
              }
            }
          })
          .catchError((Object e) {
            onNotify('同步失败：$e');
          });
    });
  }
}
