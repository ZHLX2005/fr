import '../../api_client.dart';
import '../../api_response.dart';

/// KvEndpoint 提供的最小操作集合 —— 让 CloudStorageSync 等上游能注入替身（测试/mock）。
abstract interface class KvOps {
  Future<ApiResponse<KvItem?>> get(String key);
  Future<ApiResponse<void>> set({required String key, required String value, int? ttl});
  Future<ApiResponse<void>> delete(String key);
  Future<ApiResponse<KvListResult>> list({int limit = 50, int offset = 0});
}

/// KV 端点 — 轻量键值对，支持 TTL。
class KvEndpoint implements KvOps {
  final ApiClient _client;

  KvEndpoint(this._client);

  @override
  Future<ApiResponse<KvItem?>> get(String key, {int? groupId}) =>
      _client.request<KvItem>(
        method: 'GET',
        path: '/api/v1/kv/$key${_gidQuery(groupId, hasQuery: false)}',
        fromJson: (json) => KvItem.fromJson(json),
      );

  @override
  Future<ApiResponse<void>> set({
    required String key,
    required String value,
    int? ttl,
    int? groupId,
  }) {
    final includeGid = groupId != null && groupId > 0;
    return _client.request<void>(
      method: 'POST',
      path: '/api/v1/kv',
      body: {
        'key': key,
        'value': value,
        'ttl': ?ttl,
        if (includeGid) 'groupId': groupId,
      },
    );
  }

  @override
  Future<ApiResponse<void>> delete(String key, {int? groupId}) =>
      _client.request<void>(
        method: 'DELETE',
        path: '/api/v1/kv/$key${_gidQuery(groupId, hasQuery: false)}',
      );

  @override
  Future<ApiResponse<KvListResult>> list({
    int limit = 50,
    int offset = 0,
    int? groupId,
  }) =>
      _client.request<KvListResult>(
        method: 'GET',
        path:
            '/api/v1/kv?limit=$limit&offset=$offset${_gidQuery(groupId, hasQuery: true)}',
        fromJson: (json) => KvListResult.fromJson(json),
      );

  /// groupId 有效(>0)时拼 query：已有 query 用 `&`，否则 `?`。
  String _gidQuery(int? groupId, {required bool hasQuery}) {
    if (groupId == null || groupId <= 0) return '';
    return '${hasQuery ? '&' : '?'}groupId=$groupId';
  }
}

class KvItem {
  final String key;
  final String value;
  final String? expiresAt;

  const KvItem({required this.key, required this.value, this.expiresAt});

  factory KvItem.fromJson(Map<String, dynamic> json) => KvItem(
        key: json['key'] as String? ?? '',
        value: json['value'] as String? ?? '',
        expiresAt: json['expires_at'] as String?,
      );
}

class KvListResult {
  final List<KvItem> items;
  final int total;

  const KvListResult({required this.items, required this.total});

  factory KvListResult.fromJson(Map<String, dynamic> json) => KvListResult(
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => KvItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        total: json['total'] as int? ?? 0,
      );
}
