import 'package:flutter/material.dart';
import '../models/line_models.dart';
import '../repository/chart_repository.dart';
import '../settings/line_settings.dart';
import '../widgets/song_detail_panel.dart';
import 'line_demo_page.dart';

/// 选歌界面
class SongSelectPage extends StatefulWidget {
  const SongSelectPage({super.key});

  @override
  State<SongSelectPage> createState() => _SongSelectPageState();
}

class _SongSelectPageState extends State<SongSelectPage> {
  List<SongData> _songs = [];
  SongData? _selectedSong;
  GameBorderStyle _borderStyle = GameBorderStyle.solid;
  LineDensity _lineDensity = LineDensity.normal;
  bool _isLoading = true;
  late FixedExtentScrollController _scrollController;
  static const int _loopMultiplier = 10000; // 循环倍数，用于无限滚动

  @override
  void initState() {
    super.initState();
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
    if (mounted) {
      setState(() {
        _songs = songs;
        _selectedSong = songs.isNotEmpty ? songs.first : null;
        _isLoading = false;
      });
      // 跳转到中间位置，实现无限循环
      if (songs.isNotEmpty) {
        final middleItem = (songs.length * _loopMultiplier / 2).round();
        _scrollController.jumpToItem(middleItem);
      }
    }
  }

  void _onStart() {
    if (_selectedSong == null) return;

    final chart = ChartData(
      name: _selectedSong!.name,
      bpm: _selectedSong!.bpm,
      dropDuration: _selectedSong!.dropDuration,
      notes: _selectedSong!.notes,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LineDemo(
          chart: chart,
          audioPath: _selectedSong!.audioPath.isNotEmpty ? _selectedSong!.audioPath : null,
        ).buildPage(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final navHeight = MediaQuery.of(context).padding.top + 56;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: color),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off, size: 64, color: color.withValues(alpha: 0.3)),
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
                  padding: EdgeInsets.only(left: 16, top: MediaQuery.of(context).padding.top),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new, color: color, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.only(right: 16, top: MediaQuery.of(context).padding.top),
                  child: IconButton(
                    icon: Icon(Icons.settings_outlined, color: color, size: 24),
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (context) => SpeedSettingsPage(primaryColor: color),
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
                  width: MediaQuery.of(context).size.width * 0.3,
                  child: Align(
                    alignment: const Alignment(0, -0.3),
                    child: SizedBox(
                      height: 48 * 3, // 恰好显示3个 item
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
                            final selectedIndex = _songs.indexWhere((s) => s.id == _selectedSong?.id);
                            final distance = (selectedIndex - realIndex).abs();
                            final minDistance = distance > _songs.length / 2
                                ? _songs.length - distance
                                : distance;
                            final isSelected = minDistance == 0;
                            final isNeighbor = minDistance == 1;

                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 32),
                                child: Text(
                                  song.name,
                                  style: TextStyle(
                                    fontSize: isSelected ? 22 : (isNeighbor ? 16 : 12),
                                    fontWeight: FontWeight.w200,
                                    color: isSelected
                                        ? color
                                        : (isNeighbor
                                            ? color.withValues(alpha: 0.5)
                                            : color.withValues(alpha: 0.25)),
                                    letterSpacing: isSelected ? 4 : 2,
                                  ),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
