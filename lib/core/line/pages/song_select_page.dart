import 'package:flutter/material.dart';
import '../models/line_models.dart';
import '../repository/chart_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController = FixedExtentScrollController(initialItem: 0);
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
      body: Row(
        children: [
          // 左侧歌曲滚轮 (30%)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.3,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ListWheelScrollView.useDelegate(
                  controller: _scrollController,
                  itemExtent: 48,
                  diameterRatio: 100,
                  perspective: 0.001,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    setState(() => _selectedSong = _songs[index]);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: _songs.length,
                    builder: (context, index) {
                      final song = _songs[index];
                      final selectedIndex = _songs.indexWhere((s) => s.id == _selectedSong?.id);
                      final distance = (selectedIndex - index).abs();
                      final isSelected = distance == 0;
                      final isNeighbor = distance == 1;

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
                // 短横线指示器
                Positioned(
                  left: 0,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color,
                            color.withValues(alpha: 0),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ],
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
    );
  }
}
