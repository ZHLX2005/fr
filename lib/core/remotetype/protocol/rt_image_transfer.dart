// lib/core/remotetype/protocol/rt_image_transfer.dart
//
// RT1 图片传输编排（v0.8.0+ 文件模块·实时拍照）：一张照片 → 分片 → RT1 信封
// 逐块发送 → 逐块 ACK 对账 → end 被确认（= PC 已写入剪贴板）。
//
// 协议与 mn-rt client/lib/rt-image.js 构成两端：
//   begin : {'op':'begin','id','n','size','mime'}  元数据一次到位（PC 预分配缓冲）
//   chunk : {'op':'chunk','id','i','d':base64}     纯数据块；PC 受理即 ACK
//   end   : {'op':'end','id'}                       PC 到齐并写入剪贴板后才 ACK
//   abort : {'op':'abort','id'}                     用户取消，PC 释放缓冲
//
// 续传：每块独立 ACK；重试只补「未 ACK」的块（同 id，PC 端保留半成品缓冲、
// 重复块幂等覆写）。end 的 ACK 是唯一的整图成功信号——等不到就补发缺失块 +
// end，至多 kRtImageMaxResendRounds 轮。
//
// 分片大小是**跨端契约**，改动必须与 mn-rt RT_IMAGE_CHUNK_SIZE 同步
// （信封帧 ≈ 64KB，须小于 serve 默认 maxPayload 100KB）。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'rt_session.dart';

/// 单块原始字节数（与 mn-rt rt-image.js 的 RT_IMAGE_CHUNK_SIZE 严格一致）。
const int kRtImageChunkSize = 48 * 1024;

/// 单张图片字节上限（与 PC / rust 侧 12MB 防御对齐，取更严的 10MB）。
const int kRtImageMaxBytes = 10 * 1024 * 1024;

/// 缺块补发轮数上限（每轮重发全部缺失块 + end）。
const int kRtImageMaxResendRounds = 2;

/// 传输阶段（UI 只读这一组状态渲染）。
enum RtImagePhase {
  /// 未开始（拍照完成、等待发送）。
  idle,

  /// 分片发送中（含 begin/chunk/end 的首次发送）。
  sending,

  /// 已发完 end，等待 PC 确认（剪贴板写入成功）。
  waitingConfirm,

  /// 缺块补发轮（ack 缺失后的续传）。
  resending,

  /// 成功：end 被 ACK = 图片已进电脑剪贴板。
  done,

  /// 失败：重试轮耗尽 / 连接断开 / 用户取消。error 带原因。
  failed,
}

/// 一张图片的一次传输任务。failed 后想再试请新建任务（新任务换新 id，
/// PC 端旧半成品按保留期自然过期）——同 id 续传由 PC 主导，手机端跨任务
/// 丢状态（进程被杀）后无法对账，宁可整图重发。
class RtImageTransfer extends ChangeNotifier {
  RtImageTransfer({
    required RtSession session,
    required Uint8List bytes,
    this.mime = 'image/jpeg',
    this.name,
  }) : _session = session,
       _bytes = bytes,
       id = _randomId() {
    totalChunks = _chunkCount(_bytes.length);
  }

  final RtSession _session;
  final Uint8List _bytes;

  /// 载荷类型：'image/jpeg'（剪贴板图片）| 'application/octet-stream'
  /// （文件上传，v0.9.0+：PC 端落盘到接收目录后以 CF_HDROP 复制）。
  final String mime;

  /// 原始文件名（文件上传用，PC 端落盘命名；图片为 null）。
  final String? name;

  /// 传输 id（8 位 hex；PC 端按它识别续传）。
  final String id;

  RtImagePhase phase = RtImagePhase.idle;
  int totalChunks = 0;

  /// 已被 PC 确认落袋的分片数（进度条读数）。
  int ackedChunks = 0;
  String? error;

  bool get busy =>
      phase == RtImagePhase.sending ||
      phase == RtImagePhase.waitingConfirm ||
      phase == RtImagePhase.resending;

  StreamSubscription<int>? _ackSub;
  StreamSubscription<RtEvent>? _eventSub;
  // p2c seq → 语义：>=0 = 数据块下标；-1 = 控制指令（begin / end）
  final Map<int, int> _seqKind = {};
  final Set<int> _ackedChunks = {};
  final Set<int> _ackedControl = {};
  int _endSeq = 0;
  bool _cancelled = false;

  /// 发送整个载荷。返回 true = PC 已确认（图片进剪贴板 / 文件落盘并复制）；false = 失败（原因在 error）。
  Future<bool> send() async {
    if (busy || phase == RtImagePhase.done) return false;
    if (_bytes.isEmpty || _bytes.length > kRtImageMaxBytes) {
      return _fail('大小超出范围（≤10MB）');
    }
    _cancelled = false;
    _ackedChunks.clear();
    _ackedControl.clear();
    _seqKind.clear();
    ackedChunks = 0;
    error = null;

    _ackSub?.cancel();
    _ackSub = _session.ackAppliedSeqs.listen(_onAck);
    _eventSub?.cancel();
    _eventSub = _session.events.listen((e) {
      // 连接最终塌了就别再等确认：PC 端半成品有保留期，重连后重试即可
      if (e.kind == RtEventKind.disconnected && !e.willRetry && busy) {
        _fail('连接断开，传输中止（重连后可重试）');
      }
    });

    _phase(RtImagePhase.sending);
    final n = totalChunks;

    // begin：元数据一次到位（name 供文件落盘命名，图片不带）
    final beginSeq = await _sendOp({
      'op': 'begin',
      'id': id,
      'n': n,
      'size': _bytes.length,
      'mime': mime,
      if (name != null && name!.isNotEmpty) 'name': name,
    });
    if (beginSeq == null) return false;

    // 数据块：顺序全量首推（WS/TCP 保序；ACK 缺失走下面的续传轮补发）
    for (var i = 0; i < n; i += 1) {
      if (_cancelled) return false;
      if (!await _sendChunk(i)) return false;
    }

    // end + 确认循环（缺块补发至多 kRtImageMaxResendRounds 轮）
    for (var round = 0; round <= kRtImageMaxResendRounds; round += 1) {
      if (_cancelled) return false;
      final endSeq = await _sendOp({'op': 'end', 'id': id});
      if (endSeq == null) return false;
      _endSeq = endSeq;
      _phase(RtImagePhase.waitingConfirm);

      if (await _awaitEndAck()) {
        _phase(RtImagePhase.done);
        return true;
      }
      if (_cancelled) return false;
      if (round == kRtImageMaxResendRounds) break;

      // 对账：只补未确认的块（同 id，PC 保留缓冲、重复块幂等覆写）。
      // 补发块用新 seq——旧 seq 若只是 ACK 丢了，PC 重复收块是幂等的。
      _phase(RtImagePhase.resending);
      final missing = <int>[];
      _seqKind.forEach((_, idx) {
        if (idx >= 0 && !_ackedChunks.contains(idx)) missing.add(idx);
      });
      _seqKind.removeWhere((_, idx) => idx >= 0 && !_ackedChunks.contains(idx));
      for (final i in missing) {
        if (_cancelled) return false;
        if (!await _sendChunk(i)) return false;
      }
    }
    return _fail('重试 $kRtImageMaxResendRounds 轮仍未确认（检查电脑端与网络）');
  }

  /// 取消传输：通知 PC 释放半成品缓冲（尽力而为），任务置 failed。
  Future<void> abort() async {
    if (!busy) return;
    _cancelled = true;
    unawaited(_session.syncImageOp({'op': 'abort', 'id': id}));
    _fail('已取消');
  }

  @override
  void dispose() {
    _cancelled = true;
    _ackSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  // ---- 内部 ----

  void _onAck(int appliedSeq) {
    final kind = _seqKind[appliedSeq];
    if (kind == null) return;
    var changed = false;
    if (kind >= 0 && _ackedChunks.add(kind)) {
      ackedChunks = _ackedChunks.length;
      changed = true;
    }
    if (kind < 0) changed = _ackedControl.add(appliedSeq) || changed;
    if (changed) notifyListeners();
  }

  /// 等待 end 的 ACK（= 剪贴板写入成功）。超时预算随分片数放大、上限 120s。
  Future<bool> _awaitEndAck() async {
    final budgetMs = min(20000 + 200 * totalChunks, 120000);
    final deadline = DateTime.now().add(Duration(milliseconds: budgetMs));
    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) return false;
      if (_ackedControl.contains(_endSeq)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  /// 发一个数据块并登记 seq。返回 false = 发送失败（已置 failed 态）。
  Future<bool> _sendChunk(int i) async {
    final seq = await _sendOp({
      'op': 'chunk',
      'id': id,
      'i': i,
      'd': base64Encode(
        Uint8List.sublistView(
          _bytes,
          i * kRtImageChunkSize,
          min((i + 1) * kRtImageChunkSize, _bytes.length),
        ),
      ),
    });
    return seq != null;
  }

  /// 发一条 img 信封并登记。返回所用的 p2c seq；连接不可用返回 null
  /// （已置 failed 态）。
  Future<int?> _sendOp(Map<String, dynamic> op) async {
    final seq = await _session.syncImageOp(op);
    if (seq == null) {
      _fail('未连接（发送中止）');
      return null;
    }
    _seqKind[seq] = op['op'] == 'chunk' ? (op['i'] as int) : -1;
    return seq;
  }

  void _phase(RtImagePhase p) {
    phase = p;
    notifyListeners();
  }

  /// 置失败态。恒返回 false，方便 `return _fail(...)`。
  bool _fail(String message) {
    if (_cancelled && message == '已取消') {
      error = message;
    } else {
      error ??= message;
    }
    phase = RtImagePhase.failed;
    notifyListeners();
    return false;
  }

  static int _chunkCount(int size) =>
      (size + kRtImageChunkSize - 1) ~/ kRtImageChunkSize;

  static final Random _rng = Random.secure();

  static String _randomId() => List<int>.generate(
    4,
    (_) => _rng.nextInt(256),
  ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}
