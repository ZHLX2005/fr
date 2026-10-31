import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../api/llm/llm.dart';
import '../../../services/gallery_service.dart';
import 'ai_gallery_log.dart';
import 'ai_gallery_models.dart';
import 'ai_gallery_prompt.dart';
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

  /// 这张图实际发过几次请求（含首次）；失败项也能看出重试是否有生效。
  final int attempts;

  const AiScanItem({
    required this.asset,
    this.state = AiScanItemState.pending,
    this.result,
    this.error,
    this.attempts = 0,
  });

  bool get isFailed => state == AiScanItemState.failed;

  AiScanItem copyWith({
    AiScanItemState? state,
    AiScanResult? result,
    String? error,
    int? attempts,
    bool clearError = false,
  }) {
    return AiScanItem(
      asset: asset,
      state: state ?? this.state,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
      attempts: attempts ?? this.attempts,
    );
  }
}

/// 自动扫描调度器：取最新 X 张 → 缩图 base64 → 按最大并发量请求 LLM →
/// 逐张产出结果并持久化。
///
/// 并发模型：固定 worker 池（[AiGallerySettings.maxConcurrency] 个 worker
/// 从同一队列领任务），1 = 串行。支持中途取消（[cancel]，worker 领任务前
/// 检查取消标记）。
///
/// 失败重试：单张失败（网络/限流/JSON 解析不了）会按
/// [AiGallerySettings.retryCount] 重试；解析类失败不是原样重发 —— 把解析器
/// 的错误 + 上一次原始回复拼成新提示词再请求（见 `ai_gallery_prompt.dart`）。
class AiGalleryScanner {
  /// 硬上限，避免设置里配一个离谱值把额度打光。
  static const int maxAttemptsCap = 5;

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

  /// 取消当前扫描（已在途的 HTTP 请求会完成但不再领新任务）。
  void cancel() {
    _cancelled = true;
    AiGalleryLog.instance.warn('扫描', '收到取消指令');
  }

  /// 扫描最新 [settings.scanCount] 张图片。
  ///
  /// [onItem] 逐张回调状态变化（UI 增量刷新用）；返回完整 item 列表。
  /// 已有结果缓存的图片直接标记 done，不发请求。
  Future<List<AiScanItem>> scan({
    required AiGallerySettings settings,
    required Map<String, AiScanResult> cachedResults,
    required void Function(AiScanItem item) onItem,
  }) async {
    if (isRunning) return const [];
    _cancelled = false;
    _completer = Completer<void>();

    try {
      AiGalleryLog.instance.info(
        '扫描',
        '开始 · 最新 ${settings.scanCount} 张 · 并发 ${settings.maxConcurrency}'
        ' · 重试 ${settings.retryCount} 次 · 模型 ${settings.model}'
        ' · 提示词 ${settings.prompt.length} 字',
      );

      final assets = await _gallery.getLatestImages(limit: settings.scanCount);
      if (_cancelled) return const [];
      if (assets.isEmpty) {
        AiGalleryLog.instance.error('扫描', '没有取到任何图片（权限或相册为空）');
      } else {
        AiGalleryLog.instance.info(
          '扫描',
          '取到 ${assets.length} 张 · 最新 ${_fmt(assets.first.createDateTime)}'
          ' · 最旧 ${_fmt(assets.last.createDateTime)}（应严格倒序）',
        );
      }

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
        AiGalleryLog.instance.info('扫描', '全部命中缓存，无需请求');
        return items;
      }
      AiGalleryLog.instance.info('扫描', '待分析 ${queue.length} 张，开始请求');

      final concurrency = settings.maxConcurrency.clamp(1, 8);
      var next = 0;
      Future<void> worker() async {
        while (!_cancelled) {
          final i = next++;
          if (i >= queue.length) return;
          await processItem(
            item: queue[i],
            settings: settings,
            onItem: onItem,
            index: i + 1,
            total: queue.length,
          );
        }
      }

      await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
      AiGalleryLog.instance.info(
        '扫描',
        '结束 · 成功 ${items.where((it) => it.state == AiScanItemState.done).length}'
        ' · 失败 ${items.where((it) => it.state == AiScanItemState.failed).length}',
      );
      return items;
    } finally {
      _completer?.complete();
      _completer = null;
    }
  }

  /// 处理单张：状态 → 分析（含重试）→ 落盘。**不抛异常**，失败信息进 item。
  ///
  /// 手动「重试失败项」也走这条路径，所以状态回调与持久化逻辑只有一份。
  Future<AiScanItem> processItem({
    required AiScanItem item,
    required AiGallerySettings settings,
    required void Function(AiScanItem) onItem,
    int? index,
    int? total,
  }) async {
    final label = index == null ? item.asset.id : '#$index/$total';
    final analyzing = item.copyWith(
      state: AiScanItemState.analyzing,
      clearError: true,
    );
    onItem(analyzing);

    AiGalleryLog.instance.info('分析', '$label ${item.asset.id} 开始');

    try {
      final outcome = await analyzeAsset(
        settings: settings,
        asset: item.asset,
        label: label,
      );
      await _store.upsert(outcome.result);
      final updated = item.copyWith(
        state: AiScanItemState.done,
        result: outcome.result,
        attempts: outcome.attempts,
        clearError: true,
      );
      onItem(updated);
      return updated;
    } catch (e) {
      final attempts = e is AiGalleryAnalysisFailure ? e.attempts : 1;
      final message = describeAiError(
        e,
      ) + (attempts > 1 ? '（共尝试 $attempts 次）' : '');
      AiGalleryLog.instance.error('分析', '$label 最终失败 · $message');
      final updated = item.copyWith(
        state: AiScanItemState.failed,
        error: message,
        attempts: attempts,
      );
      onItem(updated);
      return updated;
    }
  }

  /// 分析单张图片（含重试），成功返回结果与请求次数。
  ///
  /// 失败抛 [AiGalleryAnalysisFailure]，里面带着「最后一次的错误」和
  /// 「一共试了几次」，方便 UI 与日志对齐。
  Future<({AiScanResult result, int attempts})> analyzeAsset({
    required AiGallerySettings settings,
    required AssetEntity asset,
    String label = '',
  }) async {
    final image = await _encodeImage(asset);
    final basePrompt = settings.prompt.trim().isEmpty
        ? kDefaultGalleryPrompt
        : settings.prompt;
    final maxAttempts = (settings.retryCount + 1).clamp(1, maxAttemptsCap);

    var prompt = basePrompt;
    var lastReply = '';
    var attemptsUsed = 0;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final sw = Stopwatch()..start();
      attemptsUsed = attempt;
      try {
        AiGalleryLog.instance.info(
          'AI请求',
          '$label ${asset.id} 第 $attempt/$maxAttempts 次 · ${settings.model}'
          ' · 提示词 ${prompt.length} 字 · 图片 ${_kb(image.base64Data)}',
        );
        AiGalleryLog.instance.debug('AI提示词', prompt);

        final chat = await _llm.chat(
          protocolId: settings.protocolId,
          baseUrl: settings.baseUrl,
          apiKey: settings.apiKey,
          model: settings.model,
          systemPrompt: '', // 提示词整体走 user 消息（单轮，无需 system 分离）
          messages: [LlmChatMessage(text: prompt, images: [image])],
          maxTokens: 1024,
        );
        sw.stop();
        lastReply = chat.text;
        AiGalleryLog.instance.debug(
          'AI响应',
          '${chat.text}${chat.model.isEmpty ? '' : '（model=${chat.model}）'}',
        );

        final fields = parseAiJson(chat.text);
        final result = AiScanResult.fromAiJson(assetId: asset.id, fields: fields);
        AiGalleryLog.instance.info(
          '解析成功',
          '$label ${result.title} · ${result.group} · ${fields.length} 字段'
          ' · ${sw.elapsedMilliseconds}ms',
        );
        return (result: result, attempts: attempt);
      } catch (e) {
        sw.stop();
        lastError = e;
        final detail = describeAiError(e);
        AiGalleryLog.instance.error(
          '失败',
          '$label 第 $attempt/$maxAttempts 次 · ${e.runtimeType} · $detail'
          ' · ${sw.elapsedMilliseconds}ms',
        );

        // 配置类错误（地址/Key 为空）重试没有意义，直接失败。
        if (e is LlmRequestException) break;
        if (attempt >= maxAttempts) break;

        prompt = buildGalleryRetryPrompt(
          basePrompt: basePrompt,
          attempt: attempt,
          error: detail,
          previousReply: lastReply,
        );
        AiGalleryLog.instance.warn(
          '重试',
          '$label 第 ${attempt + 1}/$maxAttempts 次 · 已把解析错误拼进提示词'
          '（新提示词 ${prompt.length} 字）',
        );
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    throw AiGalleryAnalysisFailure(
      describeAiError(lastError ?? Exception('未知错误')),
      attempts: attemptsUsed == 0 ? maxAttempts : attemptsUsed,
      cause: lastError,
    );
  }

  /// 原生缩图 → base64。1568px 长边是各家 vision API 的性价比甜点，
  /// jpeg q85 体积一般 100-300KB，base64 后仍远小于 4MB 级原图。
  Future<LlmImage> _encodeImage(AssetEntity asset) async {
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(1568, 1568),
      format: ThumbnailFormat.jpeg,
      quality: 85,
    );
    if (data == null) {
      throw Exception('无法读取图片数据（asset=${asset.id}）');
    }
    return LlmImage(base64Data: base64Encode(data), mediaType: 'image/jpeg');
  }

  static String _kb(String base64) {
    final bytes = base64.length * 3 / 4;
    return bytes >= 1024 * 1024
        ? '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB'
        : '${(bytes / 1024).toStringAsFixed(0)}KB';
  }

  static String _fmt(DateTime t) =>
      '${t.month}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 单张分析最终失败：带可读原因与尝试次数。
class AiGalleryAnalysisFailure implements Exception {
  final String message;
  final int attempts;
  final Object? cause;

  const AiGalleryAnalysisFailure(
    this.message, {
    required this.attempts,
    this.cause,
  });

  @override
  String toString() => message;
}
