import 'dart:async';

import 'package:flutter/services.dart';

typedef NovelPageTurnCallback = void Function();

class NovelVolumeKeyTurnBridge {
  NovelVolumeKeyTurnBridge({
    this.onNext,
    this.onPrevious,
  });

  static const MethodChannel channel = MethodChannel(
    'lab.novel_reader.volume_key_turn',
  );

  final NovelPageTurnCallback? onNext;
  final NovelPageTurnCallback? onPrevious;

  bool _active = false;
  bool _enabled = false;

  Future<void> activate({required bool enabled}) async {
    if (_active) {
      _enabled = enabled;
      await _safeInvoke('setEnabled', enabled);
      return;
    }

    _active = true;
    _enabled = enabled;
    channel.setMethodCallHandler(_handleMethodCall);

    await _safeInvoke('setActive', true);
    await _safeInvoke('setEnabled', enabled);
  }

  Future<void> deactivate() async {
    if (!_active) return;
    _active = false;
    _enabled = false;

    channel.setMethodCallHandler(null);
    await _safeInvoke('setActive', false);
  }

  Future<void> _safeInvoke(String method, Object? arguments) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Non-Android platforms do not implement this bridge.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (!_active || !_enabled) return;

    if (call.method == 'onVolumeKey') {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final key = args['key'] as String?;
      if (key == 'down') {
        onNext?.call();
      } else if (key == 'up') {
        onPrevious?.call();
      }
    }
  }
}
