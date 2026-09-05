import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../../domain/chart_data.dart';
import '../../domain/song_data.dart';
import '../../domain/song_medal.dart';
import '../../io/chart_repository.dart';
import '../../io/line_orientation.dart';
import '../../settings/line_settings.dart';
import '../widgets/song_detail_panel.dart';
import 'game_page.dart' show GamePage;

/// 选歌界面
class SongSelectPage extends StatefulWidget {
  const SongSelectPage({super.key});

  @override
  State<SongSelectPage> createState() => _SongSelectPageState();
}

class _SongSelectPageState extends State<SongSelectPage> {
  List<SongData> _songs = [];
  SongData? _selectedSong;
  Map<String, SongMedal> _medals = {};
  GameBorderStyle _borderStyle = GameBorderStyle.solid;
  LineDensity _lineDensity = LineDensity.normal;
  bool _isLoading = true;
  late FixedExtentScrollController _scrollController;
  static const int _loopMultiplier = 10000;

  @override
  void initState() {
    super.initState();
    unawaited(LineOrientation.enableAll());
    _scrollController = FixedExtentScrollController();
    _loadSongs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    final songs = await ChartRepository.loadAllSongs();
    final medals = await SongMedalStore.loadMany(songs.map((s) => s.id));
    if (mounted) {
      setState(() {
        _songs = songs;
        _medals = medals;
        _selectedSong = songs.isNotEmpty ? songs.first : null;
        _isLoading = false;
      });
      if (songs.isNotEmpty) {
        final middleItem = (songs.length * _loopMultiplier / 2).round();
        _scrollController.jumpToItem(middleItem);
      }
    }
  }

  void _onStart() {
    if (_selectedSong == null) return;
    unawaited(_startGame(_selectedSong!));
  }

  Future<void> _startGame(SongData selected) async {
    final chart = ChartData(
      name: selected.name,
      bpm: selected.bpm,
      dropDuration: selected.dropDuration,
      notes: selected.notes,
    );

    String? audioPath =
        selected.audioPath.isNotEmpty ? selected.audioPath : null;
    final record = await ChartRepository.loadSongRecord(selected.id);
    if (record != null) {
      final local = await ChartRepository.cachedAudioPath(record);
      if (local != null) audioPath = local;
    }

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GamePage(
          chart: chart,
          audioPath: audioPath,
          songId: selected.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final size = MediaQuery.of(context).size;
    final landscape = size.width > size.height;
    final navHeight = MediaQuery.of(context).padding.top + (landscape ? 44 : 56);
    final wheelWidth = size.width * (landscape ? 0.28 : 0.3);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(child: CircularProgressIndicator(color: color)),
      );
    }

    if (_songs.isEmpty) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off,
                size: 64,
                color: color.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No songs found',
                style: TextStyle(color: color.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // 导航栏
          SizedBox(
            height: navHeight,
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    top: MediaQuery.of(context).padding.top,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      color: color,
                      size: 24,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.only(
                    right: 16,
                    top: MediaQuery.of(context).padding.top,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.settings_outlined, color: color, size: 24),
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (context) =>
                              SpeedSettingsPage(primaryColor: color),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // 选歌区域
          Expanded(
            child: Row(
              children: [
                // 左侧歌曲滚轮 (30%) — 圆筒循环滚动，只显示3个
                SizedBox(
                  width: wheelWidth,
                  child: Align(
                    alignment: const Alignment(0, -0.2),
                    child: SizedBox(
                      height: 48 * 3,
                      child: ListWheelScrollView.useDelegate(
                        controller: _scrollController,
                        itemExtent: 48,
                        diameterRatio: 1.5,
                        perspective: 0.003,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (virtualIndex) {
                          final realIndex = virtualIndex % _songs.length;
                          setState(() => _selectedSong = _songs[realIndex]);
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: _songs.length * _loopMultiplier,
                          builder: (context, virtualIndex) {
                            final realIndex = virtualIndex % _songs.length;
                            final song = _songs[realIndex];
                            final selectedIndex = _songs.indexWhere(
                              (s) => s.id == _selectedSong?.id,
                            );
                            final distance = (selectedIndex - realIndex).abs();
                            final minDistance = distance > _songs.length / 2
                                ? _songs.length - distance
                                : distance;
                            final isSelected = minDistance == 0;
                            final isNeighbor = minDistance == 1;
                            final medal = _medals[song.id] ?? SongMedal.none;

                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (medal != SongMedal.none) ...[
                                      Text(
                                        medal.label,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.5,
                                          color: isSelected
                                              ? color.withValues(alpha: 0.7)
                                              : color.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        song.name,
                                        style: TextStyle(
                                          fontSize: isSelected
                                              ? 22
                                              : (isNeighbor ? 16 : 12),
                                          fontWeight: FontWeight.w200,
                                          color: isSelected
                                              ? color
                                              : (isNeighbor
                                                    ? color.withValues(
                                                        alpha: 0.5,
                                                      )
                                                    : color.withValues(
                                                        alpha: 0.25,
                                                      )),
                                          letterSpacing: isSelected ? 4 : 2,
                                        ),
                                        textAlign: TextAlign.right,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                // 右侧详情面板 (70%)
                Expanded(
                  child: _selectedSong != null
                      ? SongDetailPanel(
                          song: _selectedSong!,
                          medal: _medals[_selectedSong!.id] ?? SongMedal.none,
                          borderStyle: _borderStyle,
                          lineDensity: _lineDensity,
                          onBorderStyleChanged: (style) {
                            setState(() => _borderStyle = style);
                          },
                          onLineDensityChanged: (density) {
                            setState(() => _lineDensity = density);
                          },
                          onStart: _onStart,
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
