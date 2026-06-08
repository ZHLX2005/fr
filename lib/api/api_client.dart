import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'api_response.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'token/token_manager.dart';

// ════════════════════════════════════════════════════════════════════
// 拦截器链接口
// ════════════════════════════════════════════════════════════════════

/// 请求上下文，拦截器通过它读取/修改请求并触发后续处理。
abstract class ApiChain<T> {
  String get method;
  String get path;
  Map<String, String> get headers;
  Object? get body;
  T Function(Map<String, dynamic>)? get fromJson;
  Future<ApiResponse<T>> proceed();
}

/// 拦截器抽象。
abstract class Interceptor {
  Future<ApiResponse<T>> intercept<T>(ApiChain<T> chain);
}

// ════════════════════════════════════════════════════════════════════
// API 客户端
// ════════════════════════════════════════════════════════════════════

/// 统一的 HTTP 客户端，内置拦截器链。
///
/// 拦截器链式处理：
/// 1. [AuthInterceptor] — 有 token 时注入，无 token 时跳过（当前后端 auth 可选）
/// 2. [LoggingInterceptor] — 请求/响应日志
/// 3. [RetryInterceptor] — 5xx 指数退避重试
class ApiClient {
  final http.Client _inner;
  final ApiConfig _config;
  final List<Interceptor> _interceptors;

  ApiClient({
    required ApiConfig config,
    required TokenManager tokenManager,
    http.Client? httpClient,
    List<Interceptor>? extraInterceptors,
  })  : _inner = httpClient ?? http.Client(),
        _config = config,
        _interceptors = [
          AuthInterceptor(tokenManager: tokenManager),
          LoggingInterceptor(),
          RetryInterceptor(maxRetries: config.maxRetries),
          ...?extraInterceptors,
        ];

  /// 发送请求，经过完整拦截器链。
  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    Map<String, String>? headers,
    Object? body,
    T Function(Map<String, dynamic>)? fromJson,
  }) {
    return _execute<T>(
      index: 0,
      method: method,
      path: path,
      headers: headers ?? {},
      body: body,
      fromJson: fromJson,
    );
  }

  Future<ApiResponse<T>> _execute<T>({
    required int index,
    required String method,
    required String path,
    required Map<String, String> headers,
    Object? body,
    T Function(Map<String, dynamic>)? fromJson,
  }) {
    if (index >= _interceptors.length) {
      return _doHttp<T>(
        method: method,
        path: path,
        headers: headers,
        body: body,
        fromJson: fromJson,
      );
    }

    final interceptor = _interceptors[index];
    final mutableHeaders = Map<String, String>.from(headers);
    final chain = _ChainContext<T>(
      method: method,
      path: path,
      headers: mutableHeaders,
      body: body,
      fromJson: fromJson,
      next: () => _execute(
        index: index + 1,
        method: method,
        path: path,
        headers: mutableHeaders,
        body: body,
        fromJson: fromJson,
      ),
    );
    return interceptor.intercept(chain);
  }

  Future<ApiResponse<T>> _doHttp<T>({
    required String method,
    required String path,
    required Map<String, String> headers,
    Object? body,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('${_config.baseUrl}$path');
      final timeout = _config.timeout;

      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _inner.get(uri, headers: headers).timeout(timeout);
          break;
        case 'POST':
          headers['Content-Type'] = 'application/json';
          response = await _inner
              .post(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(timeout);
          break;
        case 'PUT':
          headers['Content-Type'] = 'application/json';
          response = await _inner
              .put(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(timeout);
          break;
        case 'DELETE':
          response = await _inner.delete(uri, headers: headers).timeout(timeout);
          break;
        default:
          throw ApiException(code: -1, message: 'Unsupported method: $method');
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw ApiException(code: response.statusCode, message: 'Invalid JSON response', rawBody: response.body);
      }

      final code = json['code'] as int? ?? response.statusCode;
      final message = json['message'] as String? ?? '';
      T? data;
      if (json['data'] != null && fromJson != null) {
        data = fromJson(json['data'] as Map<String, dynamic>);
      }
      return ApiResponse(code: code, message: message, data: data);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(code: -1, message: 'HTTP error: $e');
    }
  }

  void dispose() => _inner.close();
}

/// 拦截器链上下文实现。
class _ChainContext<T> implements ApiChain<T> {
  @override
  final String method;
  @override
  final String path;
  @override
  final Map<String, String> headers;
  @override
  final Object? body;
  @override
  final T Function(Map<String, dynamic>)? fromJson;
  final Future<ApiResponse<T>> Function() _next;

  _ChainContext({
    required this.method,
    required this.path,
    required this.headers,
    this.body,
    this.fromJson,
    required Future<ApiResponse<T>> Function() next,
  }) : _next = next;

  @override
  Future<ApiResponse<T>> proceed() => _next();
}
