// test/core/surround_game/lan/view_model/host_device_lost_test.dart
//
// 注入式单测：通过对端 deviceId 的 stream 注入空列表，验证 Host 端
// 从 HostInGame 迁移到 HostError（对手掉线）。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_host_view_model.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_event.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';

void main() {
  test('HostInGame + 对端掉线 → HostError', () async {
    final ctrl = StreamController<List<Device>>.broadcast();
    final room = GameRoom(
      roomId: 'r1',
      hostId: 'h',
      hostName: 'A',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final vm = LanHostViewModel(
      devicesStream: ctrl.stream,
      peerDeviceId: 'peer1',
    );
    vm.dispatch(HostCreateRoomWithRoom(room));
    vm.dispatch(HostStartGamePressed());
    // 跳过倒计时（手动 dispatch 4 次 HostTick，从 3 → 2 → 1 → 0 → InGame）
    vm.dispatch(const HostTick());
    vm.dispatch(const HostTick());
    vm.dispatch(const HostTick());
    vm.dispatch(const HostTick());
    expect(vm.value, isA<HostInGame>());

    // 注入空设备列表：peer1 消失，触发 deviceLost 路径
    ctrl.add(const <Device>[]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.value, isA<HostError>());
    final err = vm.value as HostError;
    expect(err.message, contains('掉线'));
    await ctrl.close();
    vm.dispose();
  });

  test('HostWaiting + 对端掉线 → 状态不变（非 InGame 不触发 HostError）', () async {
    // deviceLost 只在 HostInGame 状态下才会迁移到 HostError。
    // 此处 sanity check：Waiting 状态收到空列表仍保持 Waiting。
    final ctrl = StreamController<List<Device>>.broadcast();
    final room = GameRoom(
      roomId: 'r2',
      hostId: 'h',
      hostName: 'A',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final vm = LanHostViewModel(
      devicesStream: ctrl.stream,
      peerDeviceId: 'peer1',
    );
    vm.dispatch(HostCreateRoomWithRoom(room));
    expect(vm.value, isA<HostWaiting>());

    ctrl.add(const <Device>[]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.value, isA<HostWaiting>());
    await ctrl.close();
    vm.dispose();
  });

  test('engine init smoke', () {
    // 防止 engine import 闲置报 lint 警告
    expect(QuoridorEngine.initialize().status.name, isNotEmpty);
  });
}
