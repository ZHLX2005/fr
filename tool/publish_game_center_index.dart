// publish_game_center_index.dart — 把游戏中心目录发布到 KV public
//
// 用法（已登录 kvcli，token 在 ~/.kvcli/config.json）：
//   dart run tool/publish_game_center_index.dart
//   dart run tool/publish_game_center_index.dart --base http://host:port --group 190
//
// 行为：
//   1. 读取 lib/core/game_kit/game_center_catalog.dart 的 kGameCenterCatalog
//   2. 登录态 POST /api/v1/kv 写回 key=game-center_catalog:index
//      （visibility=public, groupId=190, tags=['game-center-catalog']）
//   3. 匿名 GET /api/v1/kv/public/game-center_catalog:index 验证
//
// 与 add_skin.py（chess-skin-pipeline）同源：KV key 命名 `<domain>:index`、
// tag 命名 `<domain>`、groupId 190。目录发布后，ve game-skin-admin 的
// 「游戏封面」tab 自动拉到新列表（新增/下线游戏无需改 ve 代码）。

import 'dart:convert';
import 'dart:io';

import 'package:xiaodouzi_fr/core/game_kit/game_center_catalog.dart';

const String kDefaultBase = 'http://47.110.80.47:8988';
const String kKvKey = 'game-center_catalog:index';
const String kTag = 'game-center-catalog';
const int kDefaultGroup = 190;

Never die(String msg) {
  stderr.writeln('[ERR] $msg');
  exit(1);
}

void log(String msg) => stderr.writeln(msg);

String loadToken() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';
  final cfg = File('$home/.kvcli/config.json');
  final envCfg = Platform.environment['KVCLI_CONFIG'];
  final candidates = [
    if (envCfg != null && envCfg.isNotEmpty) File(envCfg),
    cfg,
  ];
  for (final p in candidates) {
    if (p.existsSync()) {
      try {
        final json = jsonDecode(p.readAsStringSync(encoding: utf8));
        final token = (json as Map<String, dynamic>)['token'];
        if (token is String && token.isNotEmpty) return token;
      } catch (e) {
        die('read token failed from ${p.path}: $e');
      }
    }
  }
  die('token not found; run `kvcli auth login` first');
}

Future<Map<String, dynamic>> httpJson(
  String base,
  String path, {
  String? token,
  bool anonymous = false,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$base$path');
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      uri,
    );
    if (token != null && !anonymous) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final text = await resp.transform(utf8.decoder).join().timeout(
          const Duration(seconds: 20),
        );
    final parsed = jsonDecode(text);
    if (parsed is! Map<String, dynamic>) {
      throw FormatException('unexpected response shape: $text');
    }
    return parsed;
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  var base = Platform.environment['CHESS_SKIN_BASE_URL'] ?? kDefaultBase;
  var group = kDefaultGroup;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--base') {
      if (i + 1 >= args.length) die('--base requires a value');
      base = args[++i];
    } else if (a == '--group') {
      if (i + 1 >= args.length) die('--group requires a value');
      final v = int.tryParse(args[++i]);
      if (v == null) die('invalid --group: ${args[i]}');
      group = v;
    } else {
      die('unknown arg: $a (usage: --base <url> --group <n>)');
    }
  }

  final token = loadToken();
  final value = gameCenterCatalogJson();
  final entries = jsonDecode(value) as List<dynamic>;
  log('catalog: ${entries.length} games from kGameCenterCatalog');

  log('[1/2] publishing KV $kKvKey (groupId=$group)');
  final resp = await httpJson(
    base,
    '/api/v1/kv',
    token: token,
    body: {
      'key': kKvKey,
      'value': value,
      'visibility': 'public',
      'groupId': group,
      'tags': [kTag],
    },
  );
  if (resp['code'] != 0) die('publish failed: $resp');

  log('[2/2] anonymous verify /api/v1/kv/public/$kKvKey?groupId=$group');
  final anon = await httpJson(
    base,
    '/api/v1/kv/public/$kKvKey?groupId=$group',
    anonymous: true,
  );
  if (anon['code'] != 0) die('anon verify failed: $anon');
  final arr = jsonDecode((anon['data'] as Map<String, dynamic>)['value'] as String)
      as List<dynamic>;
  if (arr.length != entries.length) {
    die('anon returned ${arr.length} entries, expected ${entries.length}');
  }
  final slugs = arr.map((e) => (e as Map<String, dynamic>)['slug']).toList();
  log('  verified ${arr.length} games: ${slugs.join(', ')}');
  log('OK: $kKvKey published (${arr.length} games) at $base');
}
