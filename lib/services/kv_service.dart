import 'dart:convert';
import 'package:http/http.dart' as http;

/// KV 键值存储服务
class KvService {
  static const String _baseUrl = 'http://139.9.42.203:8988/api/v1';

  /// 获取KV值
  Future<KvGetResult?> get(String key) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/kv?key=$key'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null) {
          return KvGetResult.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 设置KV值
  Future<bool> set(String key, String value, {int? ttl}) async {
    try {
      final body = {
        'key': key,
        'value': value,
        if (ttl != null) 'ttl': ttl,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/kv'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 删除KV值
  Future<bool> delete(String key) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/kv?key=$key'),
        headers: {'Content-Type': 'application/json'},
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 获取所有KV列表
  Future<List<KvItem>> list({int limit = 50, int offset = 0}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/kv?limit=$limit&offset=$offset'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null && data['data']['items'] != null) {
          final items = data['data']['items'] as List;
          return items.map((item) => KvItem.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}

/// KV 获取结果
class KvGetResult {
  final String key;
  final String value;
  final String? expiresAt;

  KvGetResult({required this.key, required this.value, this.expiresAt});

  factory KvGetResult.fromJson(Map<String, dynamic> json) {
    return KvGetResult(
      key: json['key'] ?? '',
      value: json['value'] ?? '',
      expiresAt: json['expires_at'],
    );
  }
}

/// KV 项
class KvItem {
  final String key;
  final String value;
  final String? expiresAt;

  KvItem({required this.key, required this.value, this.expiresAt});

  factory KvItem.fromJson(Map<String, dynamic> json) {
    return KvItem(
      key: json['key'] ?? '',
      value: json['value'] ?? '',
      expiresAt: json['expires_at'],
    );
  }
}
