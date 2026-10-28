import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../api/llm/llm.dart';
import '../../../services/gallery_service.dart';
import 'ai_gallery_models.dart';
import 'ai_gallery_settings.dart';
import 'ai_gallery_store.dart';

/// 扫描状态（逐张粒度，UI 网格直接消费）。
enum AiScanItemState { pending, analyzing, done, failed }

/// 网格里一张待分析图片的运行时状态。
@immutable
class AiScanItem {
  final AssetEntity asset;
  final AiScanItemState state;
  final AiScanResult? result;
  final String? error;

  const AiScanItem({
    required this.asset,
    this.state = AiScanItemState.pending,
    this.result,
    this.error,
  });

  AiScanItem copyWith({
    AiScanItemState? state,
    AiScanResult? result,
    String? error,
  }) {
    return AiScanItem(
      asset: asset,
      state: state ?? this.state,
      result: result ?? this.result,
      error: error,
    );
  }
}

/// 自动扫描调度器：取最新 X 张 → 缩图 base64 → 按最大并发量请求 LLM →
/// 逐张产出结果并持久化。
///
/// 并发模型：固定 worker 池（[AiGallerySettings.maxConcurrency] 个 worker
/// 从同一队列领任务），1 = 串行。支持中途取消（[cancel]，worker 领任务前
/// 检查取消标记）。
class AiGalleryScanner {
  final GalleryService _gallery;
  final LlmEndpoint _llm;
  final AiGalleryResultStore _store;

  AiGalleryScanner({
    GalleryService? gallery,
    LlmEndpoint? llm,
    AiGalleryResultStore? store,
  }) : _gallery = gallery ?? GalleryService(),
       _llm = llm ?? LlmEndpoint(),
       _store = store ?? AiGalleryResultStore();

  bool _cancelled = false;
  bool get isRunning => _completer != null && !_completer!.isCompleted;
  Completer<void>? _completer;

  /// 取消当前扫描（已在途的 HTTP 请求会完成但结果丢弃）。
  void cancel() {
    _cancelled = true;
  }

  /// 扫描最新 [settings.scanCount] 张图片。
  ///
  /// [onItem] 逐张回调状态变化（UI 增量刷新用）；返回完整 item 列表。
  /// 已有结果缓存且未过期的图片直接标记 done，不发请求。
  Future<List<AiScanItem>> scan({
    required AiGallerySettings settings,
    required Map<String, AiScanResult> cachedResults,
    required void Function(AiScanItem item) onItem,
  }) async {
    if (isRunning) return const [];
    _cancelled = false;
    _completer = Completer<void>();

    try {
      final assets = await _gallery.getAllAssets(pageSize: settings.scanCount);
      if (_cancelled) return const [];

      final items = <AiScanItem>[
        for (final a in assets)
          AiScanItem(
            asset: a,
            state: cachedResults.containsKey(a.id)
                ? AiScanItemState.done
                : AiScanItemState.pending,
            result: cachedResults[a.id],
          ),
      ];
      for (final it in items) {
        onItem(it); // 初始状态先全量推给 UI
      }

      // 待分析队列（保持最新在前）
      final queue = [
        for (final it in items)
          if (it.state == AiScanItemState.pending) it,
      ];
      if (queue.isEmpty) {
        _completer?.complete();
        return items;
      }

      final concurrency = settings.maxConcurrency.clamp(1, 8);
      var next = 0;
      Future<void> worker() async {
        while (!_cancelled) {
          final i = next++;
          if (i >= queue.length) return;
          final target = queue[i];
          _update(items, target.asset.id, (it) {
            final updated = it.copyWith(state: AiScanItemState.analyzing);
            onItem(updated);
            return updated;
          });
          try {
            final result = await _analyzeOne(settings, target.asset);
            if (_cancelled) return;
            await _store.upsert(result);
            _update(items, target.asset.id, (it) {
              final updated = it.copyWith(
                state: AiScanItemState.done,
                result: result,
              );
              onItem(updated);
              return updated;
            });
          } catch (e) {
            if (_cancelled) return;
            _update(items, target.asset.id, (it) {
              final updated = it.copyWith(
                state: AiScanItemState.failed,
                error: e.toString(),
              );
              onItem(updated);
              return updated;
            });
          }
        }
      }

      await Future.wait([
        for (var w = 0; w < concurrency; w++) worker(),
      ]);
      return items;
    } finally {
      _completer?.complete();
      _completer = null;
    }
  }

  /// 分析单张：原生缩图 → base64 → LLM → JSON 解析。
  Future<AiScanResult> _analyzeOne(
    AiGallerySettings settings,
    AssetEntity asset,
  ) async {
    // photo_manager 原生缩图：1568px 长边是各家 vision API 的性价比甜点，
    // jpeg q85 体积一般 100-300KB，base64 后仍远小于 4MB 级别原图。
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(1568, 1568),
      format: ThumbnailFormat.jpeg,
      quality: 85,
    );
    if (data == null) {
      throw Exception('无法读取图片数据');
    }
    final b64 = base64Encode(data);
    final image = LlmImage(
      base64Data: b64,
      mediaType: 'image/jpeg',
    );

    final chat = await _llm.chat(
      protocolId: settings.protocolId,
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      systemPrompt: '', // 提示词整体走 user 消息（单轮，无需 system 分离）
      messages: [
        LlmChatMessage(text: settings.prompt, images: [image]),
      ],
      maxTokens: 1024,
    );

    final fields = parseAiJson(chat.text);
    return AiScanResult.fromAiJson(assetId: asset.id, fields: fields);
  }

  /// items 按 assetId 原位替换为 updater 的返回值。
  void _update(
    List<AiScanItem> items,
    String assetId,
    AiScanItem Function(AiScanItem) updater,
  ) {
    final i = items.indexWhere((it) => it.asset.id == assetId);
    if (i >= 0) items[i] = updater(items[i]);
  }
}
