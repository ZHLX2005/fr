import 'package:flutter/material.dart';
import '../models/line_models.dart';
import '../repository/chart_repository.dart';
import '../widgets/rotating_cover.dart';
import '../widgets/song_list_tile.dart';
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
  BorderStyle _borderStyle = BorderStyle.solid;
  LineDensity _lineDensity = LineDensity.normal;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
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

  void _onSongSelected(SongData song) {
    setState(() => _selectedSong = song);
  }

  void _onStart() {
    if (_selectedSong == null) return;

    // Convert SongData to ChartData for LineDemoPage
    final chart = ChartData(
      name: _selectedSong!.name,
      bpm: _selectedSong!.bpm,
      dropDuration: _selectedSong!.dropDuration,
      notes: _selectedSong!.notes,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LineDemoPage(chart: chart),
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
          // 左侧歌曲列表 (30%)
          Container(
            width: MediaQuery.of(context).size.width * 0.3,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: color.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // 标题
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'SONGS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.6),
                      letterSpacing: 4,
                    ),
                  ),
                ),
                Divider(color: color.withValues(alpha: 0.1), height: 1),
                // 列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _songs.length,
                    itemBuilder: (context, index) {
                      final song = _songs[index];
                      return SongListTile(
                        song: song,
                        isSelected: song.id == _selectedSong?.id,
                        onTap: () => _onSongSelected(song),
                      );
                    },
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
