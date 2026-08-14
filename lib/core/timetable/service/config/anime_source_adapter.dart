/// 追剧模式 —— 开放 API 来源适配层
///
/// 每个来源实现 [AnimeSourceAdapter]，拉取"番剧 + 播出日期时间"草稿，
/// 供设置页追剧区快速导入（填充剧行后再生成 DSL）。
/// 当前主源：Bangumi 公开日历 API（当前季，按星期分组）。
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

/// 已注册来源（新增来源在此登记即可出现在导入入口）
final List<AnimeSourceAdapter> kAnimeSourceAdapters = [
  BangumiCalendarAdapter(),
];
