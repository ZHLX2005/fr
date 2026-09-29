import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../pi_config.dart';
import '../pi_exception.dart';

/// 一个可用模型（`GET /models?cwd=` 的 modelList 项）。
class PiModel {
  final String id;
  final String? name;
  final String? provider;

  const PiModel({required this.id, this.name, this.provider});

  /// `provider/id` 形式，便于存储与展示。
  String get qualifiedId => provider == null ? id : '$provider/$id';

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return qualifiedId;
  }

  factory PiModel.fromJson(Map<String, dynamic> json) => PiModel(
        id: (json['id'] ?? '').toString(),
        name: json['name']?.toString(),
        provider: json['provider']?.toString(),
      );

  @override
  String toString() => displayName;
}

/// 模型清单 + 会话默认模型/思考档位。
class PiModelCatalog {
  final List<PiModel> models;
  final PiModel? defaultModel;
  final String? defaultThinkingLevel;
  final Map<String, dynamic> raw;

  const PiModelCatalog({
    this.models = const [],
    this.defaultModel,
    this.defaultThinkingLevel,
    this.raw = const {},
  });

  /// 服务端是否真的配了模型（空列表 = 没配 → 发消息会 No API key found）。
  bool get hasModels => models.isNotEmpty;

  factory PiModelCatalog.fromJson(Map<String, dynamic> json) {
    final list = (json['modelList'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PiModel.fromJson)
        .toList();
    PiModel? def;
    final d = json['defaultModel'];
    if (d is Map<String, dynamic>) def = PiModel.fromJson(d);
    return PiModelCatalog(
      models: list,
      defaultModel: def,
      defaultThinkingLevel: json['defaultThinkingLevel']?.toString(),
      raw: json,
    );
  }
}

/// pi 模型端点。
///
/// ⚠️ `/models` **必须带 `?cwd=`**，否则 pi-web 返回 403 `Access denied`
/// （它对 cwd 有白名单校验）。
class PiModelsEndpoint {
  final PiConfig Function() _config;
  final http.Client _client;

  PiModelsEndpoint({required PiConfig Function() config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  /// 模型清单（含默认模型与思考档位）。
  Future<PiModelCatalog> list() async {
    final cfg = _config();
    final uri = cfg.uri('/models', {'cwd': cfg.cwd});
    final json = await _getJson(uri, timeout: const Duration(seconds: 120));
    return PiModelCatalog.fromJson(json);
  }

  /// 已启用的模型范围（patterns / allEnabled）。
  Future<Map<String, dynamic>> enabled() async =>
      _getJson(_config().uri('/models/enabled'), timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final cfg = _config();
    if (!cfg.isConfigured) {
      throw const PiApiException(
        statusCode: 0,
        message: 'pi 未配置：请先在设置里填写服务地址与 device token',
        code: 'NOT_CONFIGURED',
      );
    }
    http.Response resp;
    try {
      resp = await _client.get(uri, headers: {
        'Accept': 'application/json',
        if (cfg.token.isNotEmpty) 'Authorization': 'Bearer ${cfg.token}',
      }).timeout(timeout);
    } on TimeoutException {
      throw PiApiException(
        statusCode: 0,
        message: '请求超时：${uri.path}',
        code: 'TIMEOUT',
      );
    } catch (e) {
      throw PiApiException(statusCode: 0, message: '$e', code: 'NETWORK');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PiApiException.fromResponse(resp.statusCode, resp.body);
    }
    final decoded = json.decode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw PiApiException(
        statusCode: resp.statusCode,
        message: '响应不是 JSON 对象: ${resp.body}',
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
