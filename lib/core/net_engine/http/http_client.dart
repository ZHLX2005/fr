// lib/core/net_engine/http/http_client.dart
//
// HTTP 客户端 — 向对端的 HTTP Server 发起请求，用于可靠 P2P 通信。
//
// 每个请求返回 HTTP 状态码 + 响应体，调用方据此知道对端是否收到。

import 'dart:convert';
import 'dart:io' show HttpException, SocketException;

import 'package:http/http.dart' as http;

/// 向对端发送 HTTP POST 请求
///
/// 返回 (statusCode, responseBody) 或抛异常
Future<HttpResponse> httpPost({
  required String ip,
  required int port,
  required String path,
  Map<String, dynamic>? body,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final url = Uri.parse('http://$ip:$port$path');
  final client = http.Client();
  try {
    final response = await client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
    Map<String, dynamic>? data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    return HttpResponse(response.statusCode, data);
  } on SocketException {
    throw HttpRequestException('Connection refused: $url');
  } on HttpException {
    rethrow;
  } finally {
    client.close();
  }
}

class HttpResponse {
  final int statusCode;
  final Map<String, dynamic>? body;

  const HttpResponse(this.statusCode, this.body);

  bool get isOk => statusCode == 200;
  bool get isError => statusCode >= 400;
}

class HttpRequestException implements Exception {
  final String message;
  HttpRequestException(this.message);
  @override
  String toString() => 'HttpRequestException: $message';
}

/// 通用响应体构造
Map<String, dynamic> okBody({String? message}) =>
    {'ok': true, if (message != null) 'message': message};

Map<String, dynamic> errorBody(String message) =>
    {'ok': false, 'error': message};
