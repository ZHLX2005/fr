/// 组任务的**显示序接线**：`localtask.boardtasks` 给的是队列序（待领在前、
/// 编号升序），组页与抽屉要的是「未完成 → 已领取 → 已终态，桶内最新在上」。
///
/// 纯函数的规则在 `nxkv_tree_test.dart` 里钉；这里只验 controller 有没有真的
/// 把那把尺子用上 —— 组任务不经 `loadTasks`（没有客户端可注入），所以直接
/// 灌 `boardTasks` 再读 `groupTasks`。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_controller.dart';

class _C extends NxKvController {
  _C()
      : super(
          target: const MnWsAppTarget(
            pc: MnWsPcGroup(
              bridgeId: 'laptop-test',
              name: 'test-pc',
              userId: 'u1',
              connectedAt: '',
              apps: [],
            ),
            pcApp: MnWsPcApp(
              app: 'nx-kv',
              title: 'nx-kv',
              port: null,
              base: null,
              bridgeId: 'laptop-test',
              alive: true,
            ),
          ),
          endpoint: MnWsEndpoint(
            baseUrl: 'http://127.0.0.1:9',
            grantReader: () async => null,
          ),
        );

  @override
  Future<void> refresh() async {}
}

kv.LocaltaskBoardTasksBoardTask _task(
  int id,
  String status, {
  String createdAt = '2026-11-16 08:00:00',
  String consumedAt = '',
  String completedAt = '',
}) =>
    kv.LocaltaskBoardTasksBoardTask(
      id: id,
      status: status,
      title: '任务 $id',
      round: 1,
      ready: status == 'pending',
      project: 'fr',
      topicKey: 'k1',
      createdAt: createdAt,
      consumedAt: consumedAt,
      completedAt: completedAt,
      claimedByName: '',
      roundSummary: '',
    );

void main() {
  test('groupTasks：服务端队列序 → 显示序（待领在前，桶内最新在上）', () {
    final c = _C()
      ..selectedBoardKey = 'group/kv_fr'
      ..boardTasks = [
        kv.LocaltaskBoardTasksBoard(
          id: 'b1',
          key: 'group/kv_fr',
          name: 'kv_fr',
          pending: 2,
          total: 4,
          // 队列序：早的在前（这条顺序就是 agent 的领取优先级）
          tasks: [
            _task(11, 'pending', createdAt: '2026-11-16 07:00:00'),
            _task(12, 'pending', createdAt: '2026-11-16 09:30:00'),
            _task(13, 'claimed',
                createdAt: '2026-11-15 20:00:00', consumedAt: '2026-11-16 10:00:00'),
            _task(14, 'done',
                createdAt: '2026-11-14 09:00:00',
                consumedAt: '2026-11-14 10:00:00',
                completedAt: '2026-11-16 11:00:00'),
          ],
        ),
      ];

    expect(c.groupTasks.map((t) => t.id), [12, 11, 13, 14]);
  });

  test('groupTasks：状态筛选只减不排（筛后仍是显示序）', () {
    final c = _C()
      ..selectedBoardKey = 'group/kv_fr'
      ..boardTasks = [
        kv.LocaltaskBoardTasksBoard(
          id: 'b1',
          key: 'group/kv_fr',
          name: 'kv_fr',
          pending: 1,
          total: 2,
          tasks: [
            _task(21, 'done',
                createdAt: '2026-11-16 07:00:00',
                consumedAt: '2026-11-16 07:30:00',
                completedAt: '2026-11-16 08:00:00'),
            _task(22, 'done',
                createdAt: '2026-11-16 06:00:00',
                consumedAt: '2026-11-16 06:30:00',
                completedAt: '2026-11-16 09:00:00'),
          ],
        ),
      ]
      ..statusFilter = 'done';

    expect(c.groupTasks.map((t) => t.id), [22, 21], reason: '完成晚的在前（完成时刻而非入队时刻）');
  });
}
