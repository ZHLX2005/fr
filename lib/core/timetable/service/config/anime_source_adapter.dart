/// 追剧模式 —— 番剧来源适配层
///
/// 当前唯一来源：自建聚合后端（详见 references/anime-backend-api-spec.md）。
/// 接口聚合 Bangumi 中文名 + AniList 精确时刻 + MAL 兜底，返回字段齐全的番剧列表。
/// 客户端只透传字段，不再做时区换算与合并。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 从 API 来源拉取的剧草稿（字段可能缺失，导入后由用户补齐）
class AnimeDraft {
  final String title;

  /// 开播日期 YYYY-MM-DD（可为空）
  final String? startDateIso;

  /// 播出星期 1-7（可为空）
  final int? weekday;

  /// 当天播出时间 HH:mm（公开 API 大多不提供具体时刻，可为空由用户补）
  final String? time;

  /// 期数（可为空，默认按季番 13 处理）
  final int? episodes;

  final String? sourceUrl;

  const AnimeDraft({
    required this.title,
    this.startDateIso,
    this.weekday,
    this.time,
    this.episodes,
    this.sourceUrl,
  });
}

/// 番剧季度（与后端枚举对齐；按日本电视台季度口径：冬 1 月 / 春 4 月 / 夏 7 月 / 秋 10 月）
enum AnimeSeason {
  winter('WINTER', '冬'),
  spring('SPRING', '春'),
  summer('SUMMER', '夏'),
  fall('FALL', '秋');

  final String code;
  final String label;
  const AnimeSeason(this.code, this.label);

  /// 自然月 → 季度（与 AniList 季度切分一致）
  static AnimeSeason fromMonth(int month) {
    if (month <= 3) return AnimeSeason.winter;
    if (month <= 6) return AnimeSeason.spring;
    if (month <= 9) return AnimeSeason.summer;
    return AnimeSeason.fall;
  }
}

/// 当前季度（按服务器本地月份判；与后端默认语义一致）
AnimeSeason currentAnimeSeason() =>
    AnimeSeason.fromMonth(DateTime.now().month);

/// 番剧来源适配器抽象
abstract class AnimeSourceAdapter {
  /// 来源唯一 id
  String get id;

  /// 来源展示名
  String get label;

  /// 拉取指定季度的番剧列表
  Future<List<AnimeDraft>> fetchSeason(AnimeSeason season, int year);
}

/// 自建聚合后端新番适配器（fr 28）
///
/// GET {BASE_URL}/api/v1/anime/season?season=...&year=... → 指定季度 TV 番剧列表。
/// 后端已完成 Bangumi 中文名 + AniList 时刻 + 总集数的合并，并按 JST 自然日
/// 输出 weekday(1-7) 与 time(HH:mm)。客户端只做字段透传，缺字段降级为 null。
class SelfHostedAnimeAdapter implements AnimeSourceAdapter {
  static const _baseUrl = 'http://47.110.80.47:81';
  static const _apiPath = '/api/v1/anime/season';

  @override
  String get id => 'selfhosted-season';

  @override
  String get label => '自建新番表';

  @override
  Future<List<AnimeDraft>> fetchSeason(AnimeSeason season, int year) async {
    final uri = Uri.parse('$_baseUrl$_apiPath').replace(queryParameters: {
      'season': season.code,
      'year': '$year',
    });
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'xiaodouzi-fr/1.0 (timetable anime adapter)',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return items
        .map(_toDraft)
        .whereType<AnimeDraft>()
        .toList(growable: false);
  }

  /// 单条 item → AnimeDraft；title 为空或非 Map 的条目返回 null 跳过
  static AnimeDraft? _toDraft(Map<String, dynamic> m) {
    final title = m['title'] as String?;
    if (title == null || title.isEmpty) return null;

    final weekdayRaw = m['weekday'] as int?;
    final weekday =
        (weekdayRaw != null && weekdayRaw >= 1 && weekdayRaw <= 7)
            ? weekdayRaw
            : null;

    final timeRaw = m['time'] as String?;
    final time = _normalizeTime(timeRaw);

    return AnimeDraft(
      title: title,
      startDateIso: m['startDateIso'] as String?,
      weekday: weekday,
      time: time,
      episodes: m['episodes'] as int?,
      sourceUrl: m['sourceUrl'] as String?,
    );
  }

  /// 后端契约 `HH:mm` JST 自然日；非空且格式合法才透传，否则置 null 由用户补
  static String? _normalizeTime(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(raw);
    if (m == null) return null;
    return '${m.group(1)}:${m.group(2)}';
  }
}

/// 已注册来源（单一自建后端）
final List<AnimeSourceAdapter> kAnimeSourceAdapters = [
  SelfHostedAnimeAdapter(),
];
