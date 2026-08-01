import 'dart:convert';

import 'package:http/http.dart' as http;

import 'e2ekv_config.dart';
import 'e2ekv_exception.dart';
import 'e2ekv_models.dart';

/// e2ekv 端点 —— 自持 http.Client。
///
/// 鉴权用派生的 AuthHash（不是登录 token），响应是裸 JSON（非 ApiClient 的
/// {code,message,data} 信封），因此不走 ApiClient 的拦截器链 —— 走
/// github/notion 模式。
///
/// 全部 6 个端点（与后端 cmd.go 路由一致）：
///   POST   /v1/e2ekv/setup     X-E2EKV-Auth-Hash
///   GET    /v1/e2ekv/         Bearer
///   GET    /v1/e2ekv/{k}      Bearer
///   PUT    /v1/e2ekv/{k}      Bearer
///   DELETE /v1/e2ekv/{k}      Bearer
///   GET    /v1/e2ekv/healthz  无
class E2EKVEndpoint {
  final String baseUrl;
  final http.Client _client;

  E2EKVEndpoint({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? E2EKVConfig.production().baseUrl,
        _client = client ?? http.Client();

  void close() => _client.close();

  Future<SetupRes> setup({required String authHash, required KdfParams kdf}) =>
      _send<SetupRes>(
        method: 'POST',
        path: '/v1/e2ekv/setup',
        jsonBody: {'kdf': kdf.toJson()},
        headers: {'X-E2EKV-Auth-Hash': authHash},
        parse: SetupRes.fromJson,
      );

  Future<ListRes> list({required String authHash, int limit = 100, int offset = 0}) =>
      _send<ListRes>(
        method: 'GET',
        path: '/v1/e2ekv/?limit=$limit&offset=$offset',
        headers: _bearer(authHash),
        parse: ListRes.fromJson,
      );

  Future<GetRes> get({required String authHash, required String k}) =>
      _send<GetRes>(
        method: 'GET',
        path: '/v1/e2ekv/${Uri.encodeComponent(k)}',
        headers: _bearer(authHash),
        parse: GetRes.fromJson,
      );

  Future<PutRes> put({
    required String authHash,
    required String k,
    required int version,
    required String nonce,
    required String ciphertext,
    required KdfBlobMeta kdfMeta,
  }) =>
      _send<PutRes>(
        method: 'PUT',
        path: '/v1/e2ekv/${Uri.encodeComponent(k)}',
        jsonBody: {
          'version': version,
          'nonce': nonce,
          'ciphertext': ciphertext,
          'kdf_meta': kdfMeta.toJson(),
        },
        headers: _bearer(authHash),
        parse: PutRes.fromJson,
      );

  Future<DeleteRes> delete({required String authHash, required String k}) =>
      _send<DeleteRes>(
        method: 'DELETE',
        path: '/v1/e2ekv/${Uri.encodeComponent(k)}',
        headers: _bearer(authHash),
        parse: DeleteRes.fromJson,
      );

  /// GET /v1/e2ekv/healthz —— 无鉴权。
  Future<bool> healthz() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/v1/e2ekv/healthz'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _bearer(String authHash) =>
      {'Authorization': 'Bearer $authHash'};

  Future<T> _send<T>({
    required String method,
    required String path,
    required Map<String, String> headers,
    Map<String, dynamic>? jsonBody,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final h = Map<String, String>.from(headers);
    if (jsonBody != null) h['Content-Type'] = 'application/json';
    final body = jsonBody == null ? null : jsonEncode(jsonBody);

    late http.Response resp;
    try {
      switch (method) {
        case 'GET':
          resp = await _client.get(uri, headers: h);
        case 'POST':
          resp = await _client.post(uri, headers: h, body: body);
        case 'PUT':
          resp = await _client.put(uri, headers: h, body: body);
        case 'DELETE':
          resp = await _client.delete(uri, headers: h, body: body);
        default:
          throw E2EKVException(
            statusCode: -1,
            code: 'E2EKV_CLIENT_ERROR',
            message: 'Unsupported method: $method',
          );
      }
    } catch (e) {
      if (e is E2EKVException) rethrow;
      throw E2EKVException(
        statusCode: -1,
        code: 'E2EKV_NETWORK',
        message: '$e',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw E2EKVException(
        statusCode: resp.statusCode,
        code: 'E2EKV_BAD_JSON',
        message: 'Invalid JSON body',
      );
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return parse(json);
    }
    throw E2EKVException(
      statusCode: resp.statusCode,
      code: json['code'] as String? ?? 'E2EKV_ERROR',
      message: json['message'] as String? ?? resp.body,
    );
  }
}