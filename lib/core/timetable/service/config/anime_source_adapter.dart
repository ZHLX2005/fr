/// 追剧模式 —— 开放 API 来源适配层
///
/// 每个来源实现 [AnimeSourceAdapter]，拉取"番剧 + 播出日期时间"草稿，
/// 供设置页追剧区快速导入（填充剧行后再生成 DSL）。
/// 来源：Bangumi 公开日历（当季，中文译名为主）+ AniList 当季新番
/// （补齐具体播出时刻 JST 与总集数，Bangumi 不提供的字段）。
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

/// 番剧来源适配器抽象
abstract class AnimeSourceAdapter {
  /// 来源唯一 id
  String get id;

  /// 来源展示名
  String get label;

  /// 拉取当前可导入的番剧列表
  Future<List<AnimeDraft>> fetch();
}

/// Bangumi 公开日历适配器
///
/// GET https://api.bgm.tv/calendar → 按星期分组的当季新番。
/// 提供开播日期(air_date)与星期(air_weekday)；具体播出时刻与期数
/// API 不直接提供，返回 null 由用户在剧行补齐。
class BangumiCalendarAdapter implements AnimeSourceAdapter {
  static const _apiUrl = 'https://api.bgm.tv/calendar';

  @override
  String get id => 'bangumi-calendar';

  @override
  String get label => 'Bangumi 当季新番';

  @override
  Future<List<AnimeDraft>> fetch() async {
    final response = await http.get(
      Uri.parse(_apiUrl),
      headers: {
        'User-Agent': 'xiaodouzi-fr/1.0 (timetable anime adapter)',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;

    final drafts = <AnimeDraft>[];
    for (int i = 0; i < data.length; i++) {
      final day = data[i] as Map<String, dynamic>;
      final itemsJson = day['items'] as List<dynamic>? ?? [];
      for (final raw in itemsJson) {
        final m = raw as Map<String, dynamic>;
        final airWeekday = (m['air_weekday'] as int?) ?? (i + 1) % 7;
        drafts.add(
          AnimeDraft(
            title: _displayName(m),
            startDateIso: m['air_date'] as String?,
            weekday: airWeekday == 0 ? 7 : airWeekday, // 0=周日 → 7
            time: null,
            episodes: null,
            sourceUrl: m['url'] as String?,
          ),
        );
      }
    }
    return drafts;
  }

  static String _displayName(Map<String, dynamic> m) {
    final cn = m['name_cn'] as String?;
    if (cn != null && cn.isNotEmpty) return cn;
    return m['name'] as String? ?? '未知动画';
  }
}

/// AniList 当季新番适配器
///
/// POST https://graphql.anilist.co → 当前季 TV 番剧列表。
/// 相比 Bangumi 日历，能补齐 [AnimeDraft.time]（由 nextAiringEpisode.airingAt
/// 时间戳换算 JST 播出时刻）与 [AnimeDraft.episodes]（总集数）。
/// 无中文名，标题优先日文原名（native），缺失回退罗马音（romaji）。
class AniListSeasonAdapter implements AnimeSourceAdapter {
  static const _apiUrl = 'https://graphql.anilist.co';

  /// 单季 TV 番约 50~100 部，翻页上限 3 页防御性兜底
  static const _perPage = 50;
  static const _maxPages = 3;

  static const _query = r'''
query($season: MediaSeason, $year: Int, $page: Int) {
  Page(perPage: 50, page: $page) {
    media(season: $season, seasonYear: $year, type: ANIME, format: TV, sort: START_DATE) {
      title { romaji native }
      episodes
      startDate { year month day }
      nextAiringEpisode { airingAt }
      siteUrl
    }
  }
}
''';

  @override
  String get id => 'anilist-season';

  @override
  String get label => 'AniList 当季新番';

  @override
  Future<List<AnimeDraft>> fetch() async {
    final now = DateTime.now();
    final season = _seasonOf(now.month);
    final year = now.year;

    final drafts = <AnimeDraft>[];
    for (var page = 1; page <= _maxPages; page++) {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': _query,
              'variables': {
                'season': season,
                'year': year,
                'page': page,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final mediaList = ((data['Page']
                  as Map<String, dynamic>?)?['media']
              as List<dynamic>? ??
          [])
          .cast<Map<String, dynamic>>();
      drafts.addAll(mediaList.map(_toDraft).whereType<AnimeDraft>());
      if (mediaList.length < _perPage) break; // 已到最后一页
    }
    return drafts;
  }

  /// 月 → AniList 季度名（1-3 冬 / 4-6 春 / 7-9 夏 / 10-12 秋）
  static String _seasonOf(int month) {
    if (month <= 3) return 'WINTER';
    if (month <= 6) return 'SPRING';
    if (month <= 9) return 'SUMMER';
    return 'FALL';
  }

  /// 单条 media → AnimeDraft；缺 startDate 的条目返回 null 跳过
  static AnimeDraft? _toDraft(Map<String, dynamic> m) {
    final titleMap = m['title'] as Map<String, dynamic>?;
    final native = titleMap?['native'] as String?;
    final romaji = titleMap?['romaji'] as String?;
    final title = (native != null && native.isNotEmpty)
        ? native
        : (romaji != null && romaji.isNotEmpty)
            ? romaji
            : null;
    if (title == null) return null;

    final start = m['startDate'] as Map<String, dynamic>?;
    final year = start?['year'] as int?;
    if (year == null) return null;
    final month = (start?['month'] as int?) ?? 1;
    final day = (start?['day'] as int?) ?? 1;
    final startDate = DateTime.utc(year, month, day);
    final startDateIso =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    // nextAiringEpisode.airingAt 是 UTC 时间戳；日本无夏令时，+9h 换算 JST
    // 即得到该周固定播出时刻（HH:mm）与星期。
    String? time;
    int? weekday;
    final airingAt =
        (m['nextAiringEpisode'] as Map<String, dynamic>?)?['airingAt'] as int?;
    if (airingAt != null) {
      final jst = DateTime.fromMillisecondsSinceEpoch(
        airingAt * 1000,
        isUtc: true,
      ).add(const Duration(hours: 9));
      time =
          '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}';
      weekday = jst.weekday; // Dart 1=周一..7=周日，与草稿语义一致
    }
    weekday ??= startDate.weekday;

    return AnimeDraft(
      title: title,
      startDateIso: startDateIso,
      weekday: weekday,
      time: time,
      episodes: m['episodes'] as int?,
      sourceUrl: m['siteUrl'] as String?,
    );
  }
}

/// 已注册来源（新增来源在此登记即可出现在导入入口）
final List<AnimeSourceAdapter> kAnimeSourceAdapters = [
  BangumiCalendarAdapter(),
  AniListSeasonAdapter(),
];
