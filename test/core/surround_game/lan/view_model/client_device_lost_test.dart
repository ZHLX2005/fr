// test/core/surround_game/lan/view_model/client_device_lost_test.dart
//
// 注入式单测：通过对端 deviceId 的 stream 注入空列表，验证 Client 端
// 从 ClientInGame 迁移到 ClientDisconnected。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_client_view_model.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_event.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';

void main() {
  test('ClientInGame + 对端掉线 → ClientDisconnected', () async {
    final ctrl = StreamController<List<Device>>.broadcast();
    final target = GameRoom(
      roomId: 'r1',
      hostId: 'h',
      hostName: 'A',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final vm = LanClientViewModel(
      devicesStream: ctrl.stream,
      peerDeviceId: 'peer1',
    );
    vm.dispatch(ClientJoinPressed(target));
    vm.dispatch(ClientJoinAccepted(target));
    vm.dispatch(const HostStartedCountdown(1));
    // secondsLeft=1 → 单次 tick 即进入 InGame
    vm.dispatch(const ClientTick());
    expect(vm.value, isA<ClientInGame>());

    // 注入空设备列表：peer1 消失，触发 deviceLost 路径
    ctrl.add(const <Device>[]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.value, isA<ClientDisconnected>());
    await ctrl.close();
    vm.dispose();
  });

  test('ClientWaiting + 对端掉线 → 状态不变（非 InGame 不触发 Disconnected）', () async {
    // deviceLost 只在 ClientInGame 状态下才会迁移到 ClientDisconnected。
    final ctrl = StreamController<List<Device>>.broadcast();
    final target = GameRoom(
      roomId: 'r2',
      hostId: 'h',
      hostName: 'A',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final vm = LanClientViewModel(
      devicesStream: ctrl.stream,
      peerDeviceId: 'peer1',
    );
    vm.dispatch(ClientJoinPressed(target));
    vm.dispatch(ClientJoinAccepted(target));
    expect(vm.value, isA<ClientWaiting>());

    ctrl.add(const <Device>[]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.value, isA<ClientWaiting>());
    await ctrl.close();
    vm.dispose();
  });

  test('engine init smoke', () {
    expect(QuoridorEngine.initialize().status.name, isNotEmpty);
  });
}
