import '../../api_client.dart';
import '../../api_response.dart';

/// KV 端点 — 轻量键值对，支持 TTL。
class KvEndpoint {
  final ApiClient _client;

  KvEndpoint(this._client);

  Future<ApiResponse<KvItem?>> get(String key) => _client.request<KvItem>(
        method: 'GET',
        path: '/api/v1/kv/$key',
        fromJson: (json) => KvItem.fromJson(json),
      );

  Future<ApiResponse<void>> set({
    required String key,
    required String value,
    int? ttl,
  }) =>
      _client.request<void>(
        method: 'POST',
        path: '/api/v1/kv',
        body: {'key': key, 'value': value, ?ttl: ttl},
      );

  Future<ApiResponse<void>> delete(String key) => _client.request<void>(
        method: 'DELETE',
        path: '/api/v1/kv/$key',
      );

  Future<ApiResponse<KvListResult>> list({int limit = 50, int offset = 0}) =>
      _client.request<KvListResult>(
        method: 'GET',
        path: '/api/v1/kv?limit=$limit&offset=$offset',
        fromJson: (json) => KvListResult.fromJson(json),
      );
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
