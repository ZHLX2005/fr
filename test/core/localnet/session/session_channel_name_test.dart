// Copyright (c) 2026. Test for Session.channelName field behavior.
//
// V1 contract:
//   - Session(...) with no channelName → session.channelName == null
//   - Session(..., channelName: 'x') → session.channelName == 'x'
//
// These tests do not exercise sync behavior — they only verify the field is
// stored verbatim. A fake ChannelManager with noSuchMethod lets us instantiate
// Session without standing up EventBus/DeviceManager/HttpTransport.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_message.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/send_result.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';

void main() {
  group('Session.channelName', () {
    test('不传 channelName 时默认为 null', () {
      final state = ValueNotifier<int>(42);
      final session = Session<ValueNotifier<int>>(
        peerId: 'peerA',
        state: state,
        channelManager: _FakeChannelManager(),
        serializer: _IntPassthroughSerializer(),
      );
      expect(session.channelName, isNull);
    });

    test('传 channelName 时该字段被设置', () {
      final state = ValueNotifier<int>(42);
      final session = Session<ValueNotifier<int>>(
        peerId: 'peerA',
        state: state,
        channelManager: _FakeChannelManager(),
        serializer: _IntPassthroughSerializer(),
        channelName: 'surround/game/state',
      );
      expect(session.channelName, 'surround/game/state');
    });
  });
}

// 简单 fake channel manager — 不真正通信，只让 Session 可以构造出来。
// 实现了 ChannelManager 的全部公共方法；私有字段 (_channelControllers) 不需要实现。
class _FakeChannelManager implements ChannelManager {
  @override
  Stream<ChannelMessage> watchChannel(String channel) => const Stream<ChannelMessage>.empty();

  @override
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  ) async =>
      SendResult.ok();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  // 兜底：剩余的公共方法（如 testSimulateMessage）如果被调用不抛异常。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IntPassthroughSerializer implements StateSerializer<ValueNotifier<int>> {
  @override
  Map<String, dynamic> serialize(ValueNotifier<int> notifier) => {'v': notifier.value};

  @override
  ValueNotifier<int> deserialize(Map<String, dynamic> data, ValueNotifier<int> target) {
    target.value = data['v'] as int;
    return target;
  }
}
