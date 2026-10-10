// 点击 / 检索计数（本地观测；后续可接后端）。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kClicksKey = 'nav_metric_clicks';
const _kSearchesKey = 'nav_metric_searches';

class NavMetricsState {
  const NavMetricsState({this.clicks = 0, this.searches = 0});

  final int clicks;
  final int searches;

  NavMetricsState copyWith({int? clicks, int? searches}) => NavMetricsState(
        clicks: clicks ?? this.clicks,
        searches: searches ?? this.searches,
      );
}

class NavMetricsNotifier extends Notifier<NavMetricsState> {
  @override
  NavMetricsState build() => const NavMetricsState();

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    state = NavMetricsState(
      clicks: prefs.getInt(_kClicksKey) ?? 0,
      searches: prefs.getInt(_kSearchesKey) ?? 0,
    );
  }

  Future<void> recordClick(String label) async {
    state = state.copyWith(clicks: state.clicks + 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kClicksKey, state.clicks);
  }

  Future<void> recordSearch(String query) async {
    if (query.trim().isEmpty) return;
    state = state.copyWith(searches: state.searches + 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSearchesKey, state.searches);
  }
}

final navMetricsProvider =
    NotifierProvider<NavMetricsNotifier, NavMetricsState>(
  NavMetricsNotifier.new,
);
