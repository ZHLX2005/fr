import 'package:supabase_flutter/supabase_flutter.dart';
import 'chart_repository.dart';

/// Supabase 初始化配置
class SupabaseConfig {
  static const String _url = 'https://kklrbynhqpwwhtfanqwt.supabase.co';
  static const String _anonKey =
      'sb_publishable_LMz3PGBaEJ3lJzMiS1BP1A_RajRck4P';

  static Future<void> init() async {
    await Supabase.initialize(url: _url, anonKey: _anonKey);
    ChartRepository.initSupabase(_url, _anonKey);
  }
}
