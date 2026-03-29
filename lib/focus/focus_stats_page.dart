import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/focus_provider.dart';
import 'models/focus_session.dart';

/// 数据统计页面
class FocusStatsPage extends StatelessWidget {
  const FocusStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Consumer<FocusProvider>(
        builder: (context, focusProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildWeeklyCard(focusProvider),
                const SizedBox(height: 16),
                _buildHeatmapSection(focusProvider),
                const SizedBox(height: 16),
                _buildSubjectDistribution(focusProvider),
                const SizedBox(height: 16),
                _buildRecentSessions(focusProvider),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 本周统计卡片
  Widget _buildWeeklyCard(FocusProvider focusProvider) {
    final weekMinutes = focusProvider.getWeekMinutes();
    final hours = weekMinutes ~/ 60;
    final minutes = weekMinutes % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5C9EAD),
            Color(0xFF88B3C8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本周专注',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hours.toString(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  ' 小时',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '$minutes 分钟',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 热力图区域
  Widget _buildHeatmapSection(FocusProvider focusProvider) {
    final heatmapData = focusProvider.getHeatmapData();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '活跃度',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final data = heatmapData[index];
              return Column(
                children: [
                  _buildHeatmapCell(data['level'] as int),
                  const SizedBox(height: 8),
                  Text(
                    weekdays[index],
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  /// 热力图单元格
  Widget _buildHeatmapCell(int level) {
    final colors = [
      Colors.grey[200]!,
      const Color(0xFFD4EAD4),
      const Color(0xFF9CAF88),
      const Color(0xFF7A9A6E),
      const Color(0xFF5C8B5E),
    ];

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors[level],
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  /// 学科分布
  Widget _buildSubjectDistribution(FocusProvider focusProvider) {
    final subjects = focusProvider.subjects;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '学科分布',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ...subjects.map((subject) {
            final minutes = focusProvider.getSubjectMinutes(subject.id);
            if (minutes == 0) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(subject.icon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(subject.name),
                      const Spacer(),
                      Text(
                        '${minutes ~/ 60}h ${minutes % 60}m',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: subject.progress,
                      backgroundColor: subject.color.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(subject.color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 最近会话记录
  Widget _buildRecentSessions(FocusProvider focusProvider) {
    final sessions = focusProvider.sessions.reversed.take(10).toList();

    if (sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(
              Icons.spa_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '开始你的第一段专注时光',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近记录',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ...sessions.map((session) {
            final subject = focusProvider.subjects.firstWhere(
              (s) => s.id == session.subjectId,
              orElse: () => focusProvider.subjects.first,
            );

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: subject.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(subject.icon, style: const TextStyle(fontSize: 20)),
                ),
              ),
              title: Text(subject.name),
              subtitle: Text(
                '${session.mode == FocusMode.pomodoro ? "番茄钟" : "自由计时"} · ${_formatDate(session.startTime)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              trailing: Text(
                '${session.durationMinutes}分钟',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
