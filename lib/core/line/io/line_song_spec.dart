// lib/core/line/io/line_song_spec.dart
//
// 音游「线」曲库规约 —— Supabase music 表 → KV public + File API。
//
// 约定（与 game-center / emoji / skin 同构）：
//   KV key  = line_song:index
//   KV tag  = line-song
//   File tags = line-song / line-song:<songId> / line-song:<songId>:<asset>
//   File key  = line/<songId>/{audio|cover|chart}
//   groupId   = 190（public）
//
// 每曲 3 个资产：audio（音频）/ cover（封面）/ chart（谱面 JSON）。
// 谱面 notes 不进 KV body，一律走 File。

import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/public_kv_reader.dart';

/// 曲库资产 key
const Set<String> kLineSongAssetKeys = {'audio', 'cover', 'chart'};

const String kLineSongAssetAudio = 'audio';
const String kLineSongAssetCover = 'cover';
const String kLineSongAssetChart = 'chart';

/// 默认后端（与皮肤 / 封面管线同一 host）
const String kDefaultLineSongBaseUrl = 'http://47.110.80.47:8988';

/// KV 索引 key
const String kLineSongKvIndexKey = 'line_song:index';

/// KV / File 公共 tag 前缀
const String kLineSongTagPrefix = 'line-song';

/// groupId
const int kLineSongGroupId = PublicKvReader.kPublicGroupId;

/// song id 正则（kebab-case，与 GameSkinMeta 对齐）
final RegExp kLineSongIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

/// 构造默认 [PublicFileResolver]
PublicFileResolver lineSongFileResolver({
  String baseUrl = kDefaultLineSongBaseUrl,
}) =>
    PublicFileResolver(baseUrl: baseUrl);

/// 构造默认 [PublicKvReader]
PublicKvReader lineSongKvReader({
  String baseUrl = kDefaultLineSongBaseUrl,
  int groupId = kLineSongGroupId,
}) =>
    PublicKvReader(baseUrl: baseUrl, groupId: groupId);
