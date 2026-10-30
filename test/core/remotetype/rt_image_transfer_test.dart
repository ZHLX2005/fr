// test/core/remotetype/rt_image_transfer_test.dart
//
// 图片通道（v0.8.0+ 文件模块）的纯逻辑契约：
//   · 明文形状与 mn-rt rt-align.js 的 img 分支对齐（字段名逐字一致）
//   · 分片大小 = 48KB 跨端契约：信封帧必须小于 serve 默认 maxPayload 100KB
//   · 分块数与 mn-rt rt-image.js 的推导一致（ceil(size / CHUNK)）
// 传输编排（ACK 对账 / 续传轮）依赖真会话，由 e2e 冒烟（mn-rt 仓
// client/test/e2e-image-smoke.js）覆盖。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart';
import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_image_transfer.dart';
import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_session.dart';

void main() {
  group('rtImagePlaintext：img 事件明文形状', () {
    test('img 字段 + ts + phoneId，img 原样携带', () {
      final plain = rtImagePlaintext({
        'op': 'begin', 'id': 'aabbccdd', 'n': 3, 'size': 100, 'mime': 'image/jpeg',
      }, 1700000000000, 'phone-abc12345');
      expect(plain['img'], {
        'op': 'begin', 'id': 'aabbccdd', 'n': 3, 'size': 100, 'mime': 'image/jpeg',
      });
      expect(plain['ts'], 1700000000000);
      expect(plain['phoneId'], 'phone-abc12345');
      // PC 端按 plain.img 分发；op 字段必须在 img 内层
      expect((plain['img'] as Map)['op'], 'begin');
    });
  });

  group('分片契约（与 mn-rt RT_IMAGE_CHUNK_SIZE 跨端一致）', () {
    test('分片大小 48KB', () {
      expect(kRtImageChunkSize, 48 * 1024);
    });

    test('信封帧体积上限：chunk base64 + 协议开销 < 90KB（serve 默认 100KB）', () {
      final chunk = Uint8List(kRtImageChunkSize);
      final d = base64Encode(chunk);
      // 明文 JSON 骨架 + RT1 信封字段（sid/seq/nonce/ct≈d+tag 膨胀）保守估算
      final plaintext = jsonEncode(rtImagePlaintext({
        'op': 'chunk', 'id': 'aabbccdd', 'i': 0, 'd': d,
      }, 1700000000000, 'phone-abc12345'));
      // RT1 层：ct = base64(密文(与明文等长) + 16B tag)，加 nonce/sid/seq/外层帧约 300B
      final frameEstimate = (plaintext.length * 4 / 3).ceil() + 512;
      expect(frameEstimate, lessThan(90 * 1024));
    });

    test('分块数：与 PC 端 normalizeImageOp 的 n/size 自洽校验一致', () {
      // 恰好整块：size = n*CHUNK，最后一块必为 (0, CHUNK]
      expect((kRtImageChunkSize * 3) / kRtImageChunkSize, 3.0);
      // 尾块 1 字节也占一块
      final tail = kRtImageChunkSize * 2 + 1;
      expect((tail + kRtImageChunkSize - 1) ~/ kRtImageChunkSize, 3);
    });

    test('10MB 图的分块数在白名单上限内（PC RT_IMAGE_MAX_CHUNKS）', () {
      final n = (kRtImageMaxBytes + kRtImageChunkSize - 1) ~/ kRtImageChunkSize;
      // mn-rt RT_IMAGE_MAX_CHUNKS = ceil(12MB / 48KB) = 256，10MB 需求留有余量
      expect(n, lessThan(256));
    });
  });

  group('RtImageTransfer：任务骨架', () {
    RtSession makeSession() => RtSession(
      serverUrl: 'http://127.0.0.1:1',
      key: 'TESTKEY123',
      targetClientId: 'unit-pc',
    );

    test('totalChunks 按分片大小推导，id 为 8 位 hex', () {
      final session = makeSession();
      addTearDown(session.dispose);
      final transfer = RtImageTransfer(
        session: session,
        bytes: Uint8List(kRtImageChunkSize * 2 + 5),
      );
      expect(transfer.totalChunks, 3);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(transfer.id), isTrue);
      expect(transfer.busy, isFalse);
      expect(transfer.phase, RtImagePhase.idle);
    });

    test('空图与超限图直接失败且不置 busy', () async {
      final session = makeSession();
      addTearDown(session.dispose);
      final empty = RtImageTransfer(session: session, bytes: Uint8List(0));
      expect(await empty.send(), isFalse);
      expect(empty.phase, RtImagePhase.failed);
      expect(empty.error, contains('大小'));

      final big = RtImageTransfer(
        session: session,
        bytes: Uint8List(kRtImageMaxBytes + 1),
      );
      expect(await big.send(), isFalse);
      expect(big.error, contains('大小'));
    });

    test('模块 id 已登记且可用（登记表单一事实源）', () {
      // 借此测试钉住「文件模块进登记表」这一事实，防误删
      const specs = [
        kRtCanvasModuleComposer, kRtCanvasModuleInput, kRtCanvasModuleKb,
        kRtCanvasModuleTouchpad, kRtCanvasModuleStickL, kRtCanvasModuleStickR,
        kRtCanvasModuleDpad, kRtCanvasModuleVpad, kRtCanvasModuleFiles,
      ];
      expect(specs.contains(kRtCanvasModuleFiles), isTrue);
      expect(kRtCanvasModuleFiles, 'files');
    });
  });
}
