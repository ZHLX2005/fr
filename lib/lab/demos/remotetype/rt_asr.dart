// lib/lab/demos/remotetype/rt_asr.dart
//
// 语音识别（speech_to_text）控制器：mic 按钮背后的全部 ASR 逻辑。
// 会话状态不在这——只管「听 / 停 / 出错自救」，识别文本直接写入页面传入的
// TextEditingController；提示经 showError 回调回页面弹 SnackBar（控制器
// 不持有 BuildContext），listening 翻转经 onChanged 通知页面刷新按钮外观。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音识别控制器（页面持有一份，随页面销毁）。
class RtAsr {
  RtAsr({
    required this.controller,
    required this.onChanged,
    required this.showError,
  });

  /// 识别文本的落点：partial/final 都以「base + 本段识别」整体覆写。
  final TextEditingController controller;

  /// listening 翻转后通知页面刷新（mic 按钮外观）。
  final VoidCallback onChanged;

  /// 需要用户看见的错误提示（页面负责 mounted 守卫 + SnackBar）。
  final void Function(String message) showError;

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _listening = false;
  bool _available = false;
  // 识别器楔死自救：插件跨 listen 复用 SpeechRecognizer 实例且错误路径不 destroy，
  // 国产 ROM 厂商引擎（与输入法语音同源）会把出错实例楔在 busy 态——之后永久
  // error_busy，直到 app 重启。翻转 onDevice 触发插件 createRecognizer 的
  // 销毁重建分支，拿到全新实例（onDevice 可用时还顺带切到本地离线引擎）。
  bool _rebuildTick = false;
  bool _busyRetryPending = false; // busy 自动重试进行中，防递归
  bool _disposed = false;

  /// 本段已确认文本基线：final/stop 时把已上屏文本存这里，下一段拼接在其后。
  String base = '';

  bool get listening => _listening;

  /// 页面销毁：停录音并让后续异步回调（busy 重试等）失效。
  void dispose() {
    _disposed = true;
    if (_listening) unawaited(_stt.stop());
  }

  /// 复位录音状态：错误路径下 onStatus 不一定回调 done/notListening，
  /// 不主动复位按钮会卡在「停止」态且识别器不释放。
  void reset() {
    if (_listening) {
      unawaited(_stt.stop());
    }
    _listening = false;
    onChanged();
  }

  Future<void> toggle() async {
    if (_disposed) return;
    if (_listening) {
      await _stt.stop();
      _listening = false;
      onChanged();
      base = controller.text;
      return;
    }

    if (!_available) {
      _available = await _stt.initialize(
        onError: (e) {
          debugPrint('stt error: ${e.errorMsg}');
          // 引擎层错误上浮；no_match / speech_timeout 是说话停顿的非致命反馈，不打扰
          const benign = {'error_no_match', 'error_speech_timeout'};
          if (benign.contains(e.errorMsg)) return;
          // 非 benign 错误一律强制重建识别器（见 _rebuildTick 注释），
          // 否则厂商引擎的楔死实例会让后续每次 listen 都 busy
          _rebuildTick = !_rebuildTick;
          reset();
          // busy：实例楔死的典型表现，销毁重建后自动重试一次
          if (e.errorMsg == 'error_busy') {
            if (_busyRetryPending) {
              _busyRetryPending = false;
              showError('语音识别引擎繁忙：重试仍失败，请重启输入法（或重启手机）后再试');
              return;
            }
            _busyRetryPending = true;
            Timer(const Duration(milliseconds: 800), () {
              if (!_disposed && !_listening) toggle();
            });
            return;
          }
          showError('语音识别错误：${e.errorMsg}');
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (!_disposed && _listening) {
              _listening = false;
              base = controller.text;
              onChanged();
            }
          }
        },
      );
      if (!_available) {
        showError('语音识别不可用（权限或引擎缺失）');
        return;
      }
    }

    base = controller.text;
    try {
      await _stt.listen(
        // speech_to_text 契约：partial 与 final 的 recognizedWords 都是
        // 「本段完整识别文本」（Android SpeechToTextPlugin.updateResults
        // 只取 RESULTS_RECOGNITION[0]），final 到达时把该段并入 base。
        // 不能在 final 时丢弃 words——那会把刚说完的话整段清空。
        onResult: (result) {
          if (_disposed) return;
          final text = base + result.recognizedWords;
          controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          if (result.finalResult) base = text;
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: 'zh_CN',
          onDevice: _rebuildTick,
        ),
      );
    } catch (e) {
      // listen 抛异常（如引擎服务缺失）不能无声吞掉，否则按钮像坏了
      showError('语音启动失败：$e');
      return;
    }
    _busyRetryPending = false;
    _listening = true;
    onChanged();
  }
}
