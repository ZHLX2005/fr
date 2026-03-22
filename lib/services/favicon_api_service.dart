import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 图标获取服务
class FaviconApiService {
  static const String _baseUrl = 'http://139.9.42.203:8988';

  /// 获取网站图标的多个源
  static List<String> _getFaviconUrls(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return [];

    final host = uri.host;
    final scheme = uri.scheme;

    return [
      // Google Favicon Service
      'https://www.google.com/s2/favicons?domain=$host&sz=128',
      'https://www.google.com/s2/favicons?domain=$host&sz=64',
      // DuckDuckGo Favicon Service
      'https://icons.duckduckgo.com/ip3/$host.ico',
      // 网站根目录的favicon.ico
      '$scheme://$host/favicon.ico',
      // 常见的favicon路径
      '$scheme://$host/favicon.png',
      '$scheme://$host/apple-touch-icon.png',
    ];
  }

  /// 通过API服务获取图标
  static Future<String?> fetchFaviconViaApi(String url) async {
    try {
      // 使用服务器的文件上传API获取图标
      final uri = Uri.parse('$_baseUrl/api/v1/favicon');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          return data['url'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('通过API获取图标失败: $e');
      return null;
    }
  }

  /// 直接下载图标并保存到本地
  static Future<String?> downloadAndSaveFavicon(String url, String bookmarkId) async {
    if (kIsWeb) {
      // Web平台不支持文件操作
      return null;
    }

    try {
      final faviconUrls = _getFaviconUrls(url);

      for (final faviconUrl in faviconUrls) {
        try {
          final response = await http.get(Uri.parse(faviconUrl))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            // 保存到本地
            final dir = await getApplicationDocumentsDirectory();
            final faviconDir = Directory('${dir.path}/favicons');
            if (!await faviconDir.exists()) {
              await faviconDir.create();
            }

            final ext = faviconUrl.contains('.png') ? '.png' : '.ico';
            final file = File('${faviconDir.path}/$bookmarkId$ext');
            await file.writeAsBytes(response.bodyBytes);

            return file.path;
          }
        } catch (e) {
          debugPrint('下载 $faviconUrl 失败: $e');
          continue;
        }
      }
      return null;
    } catch (e) {
      debugPrint('下载图标失败: $e');
      return null;
    }
  }

  /// 获取本地保存的图标路径
  static Future<String?> getLocalFaviconPath(String bookmarkId) async {
    if (kIsWeb) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final faviconDir = Directory('${dir.path}/favicons');

      // 检查.png和.ico
      final pngFile = File('${faviconDir.path}/$bookmarkId.png');
      final icoFile = File('${faviconDir.path}/$bookmarkId.ico');

      if (await pngFile.exists()) return pngFile.path;
      if (await icoFile.exists()) return icoFile.path;

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 清理本地图标缓存
  static Future<void> clearFaviconCache() async {
    if (kIsWeb) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final faviconDir = Directory('${dir.path}/favicons');

      if (await faviconDir.exists()) {
        await faviconDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('清理图标缓存失败: $e');
    }
  }
}
