// lib/core/chess/replay/chess_replay_export.dart
//
// 「回放任一手局面 → 保存为残局快照」共享导出链（id61：快照 = 残局，概念统一）。
//
// 两个调用方：
//   · ChessRoomPage._exportCurrentReplayPosition —— 房间内回放条「导出残局快照」
//     id 方案：eg-<roomCode>-m<index>（同房间同手数幂等）
//   · ChessGameReplayPage._exportCurrentSnapshot —— 对局回放库回放页「导出残局快照」
//     id 方案：eg-rp-<recordId>-m<index>（同记录同手数幂等）
//
// 持久化到 <documents>/chess_endgames/（ChessEndgameStore），保存成功后
// SnackBar 提供分享入口。保存的残局会出现在开房间准备面板的「选择残局」
// 列表里 —— 即"回放中选一个节点创建快照，开房间只从快照选"的闭环。

import 'package:flutter/material.dart';

import '../endgame/chess_endgame.dart';
import '../endgame/chess_endgame_store.dart';

/// 构建并持久化一个残局快照（source 固定为 [ChessEndgameSource.replay]），
/// 成功/失败均以 SnackBar 反馈（幂等：id 已存在时提示"残局已更新"）。
/// [store] 注入点（测试用）：null → 生产默认构造。
Future<void> saveEndgameSnapshotWithFeedback(
  BuildContext context, {
  required String id,
  required String title,
  required String description,
  required String snapshotLabel,
  required String fen,
  required List<String> lineageMoves,
  required int lineageMoveIndex,
  ChessEndgameStore? store,
}) async {
  final endgame = ChessEndgame(
    id: id,
    title: title,
    description: description,
    createdAt: DateTime.now().toUtc().toIso8601String(),
    source: ChessEndgameSource.replay,
    snapshots: [
      ChessEndgameSnapshot(
        label: snapshotLabel,
        fen: fen,
        lineageMoves: lineageMoves,
        lineageMoveIndex: lineageMoveIndex,
      ),
    ],
  );
  final effectiveStore = store ?? ChessEndgameStore();
  try {
    final existed = await effectiveStore.existsLocal(id);
    await effectiveStore.save(endgame);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(existed ? '残局已更新：$title' : '已保存到残局库：$title'),
        action: SnackBarAction(
          label: '分享',
          onPressed: () async {
            try {
              await effectiveStore.exportAndShare(endgame);
            } on Object {
              // 分享失败静默（文件已落盘，用户可从残局库重试）。
            }
          },
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导出失败：$e')),
    );
  }
}
