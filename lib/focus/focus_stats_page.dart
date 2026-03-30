import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/focus_provider.dart';
import 'models/focus_session.dart';

/// 数据统计页面 - 增强版
class FocusStatsPage extends StatefulWidget {
  const FocusStatsPage({super.key});

  @override
  State<FocusStatsPage> createState() => _FocusStatsPageState();
}

class _FocusStatsPageState extends State<FocusStatsPage> {
  late DateTime _currentMonth;
  int _selectedDayIndex = -1;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _selectedDayIndex = -1;
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _selectedDayIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime.now();
                _selectedDayIndex = -1;
              });
            },
            tooltip: '回到今天',
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
                _buildCalendarSection(focusProvider),
                const SizedBox(height: 16),
                if (_selectedDayIndex >= 0) ...[
                  _buildDayDetailSection(focusProvider),
                  const SizedBox(height: 16),
                ],
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
                  style: const TextStyle(
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

  /// 日历区域
  Widget _buildCalendarSection(FocusProvider focusProvider) {
    final monthData = _getMonthData(focusProvider);
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          // 月份导航
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _previousMonth,
              ),
              Text(
                '${_currentMonth.year}年${_currentMonth.month}月',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _nextMonth,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 星期标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((day) {
              final isWeekend = day == '六' || day == '日';
              return SizedBox(
                width: 40,
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isWeekend ? Colors.red[300] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // 日期网格
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: monthData.length,
            itemBuilder: (context, index) {
              final dayData = monthData[index];
              if (dayData == null) {
                return const SizedBox();
              }
              final isSelected = _selectedDayIndex == index;
              return _buildCalendarCell(dayData, isSelected, focusProvider);
            },
          ),
          const SizedBox(height: 12),
          // 热力图标例
          _buildHeatmapLegend(),
        ],
      ),
    );
  }

  /// 获取当月数据
  List<Map<String, dynamic>?> _getMonthData(FocusProvider focusProvider) {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startWeekday = firstDay.weekday; // 1=周一, 7=周日

    final List<Map<String, dynamic>?> result = [];

    // 填充月初空白
    for (int i = 1; i < startWeekday; i++) {
      result.add(null);
    }

    // 填充日期
    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final dayMinutes = focusProvider.sessions
          .where((session) =>
              session.startTime.year == date.year &&
              session.startTime.month == date.month &&
              session.startTime.day == date.day)
          .fold<int>(0, (sum, session) => sum + session.durationMinutes);

      result.add({
        'day': day,
        'date': date,
        'minutes': dayMinutes,
        'level': _getHeatmapLevel(dayMinutes),
        'isToday': _isToday(date),
      });
    }

    return result;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// 热力图级别（0-4）
  int _getHeatmapLevel(int minutes) {
    if (minutes == 0) return 0;
    if (minutes < 30) return 1;
    if (minutes < 60) return 2;
    if (minutes < 120) return 3;
    return 4;
  }

  /// 日历单元格
  Widget _buildCalendarCell(Map<String, dynamic> dayData, bool isSelected, FocusProvider focusProvider) {
    final level = dayData['level'] as int;
    final isToday = dayData['isToday'] as bool;
    final date = dayData['date'] as DateTime;
    final isWeekend = date.weekday == 6 || date.weekday == 7;
    final day = dayData['day'] as int;

    final colors = [
      Colors.grey[100]!,
      const Color(0xFFD4EAD4),
      const Color(0xFF9CAF88),
      const Color(0xFF7A9A6E),
      const Color(0xFF5C8B5E),
    ];

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedDayIndex = -1;
          } else {
            // Find the index of this day in monthData
            final monthData = _getMonthData(focusProvider);
            for (int i = 0; i < monthData.length; i++) {
              if (monthData[i] != null && (monthData[i]!)['day'] == day) {
                _selectedDayIndex = i;
                break;
              }
            }
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors[level],
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFF5C8B5E), width: 2)
              : isToday
                  ? Border.all(color: Colors.blue, width: 1)
                  : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 12,
              color: level > 0 ? Colors.white : (isWeekend ? Colors.red[300] : Colors.grey[700]),
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// 热力图标例
  Widget _buildHeatmapLegend() {
    final labels = ['无', '<30', '30-60', '60-120', '>120'];
    final colors = [
      Colors.grey[100]!,
      const Color(0xFFD4EAD4),
      const Color(0xFF9CAF88),
      const Color(0xFF7A9A6E),
      const Color(0xFF5C8B5E),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors[index],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// 当日详细记录
  Widget _buildDayDetailSection(FocusProvider focusProvider) {
    final monthData = _getMonthData(focusProvider);
    if (_selectedDayIndex < 0 || _selectedDayIndex >= monthData.length) {
      return const SizedBox.shrink();
    }

    final dayData = monthData[_selectedDayIndex];
    if (dayData == null) return const SizedBox.shrink();

    final date = dayData['date'] as DateTime;
    final daySessions = focusProvider.sessions.where((session) =>
        session.startTime.year == date.year &&
        session.startTime.month == date.month &&
        session.startTime.day == date.day).toList();

    if (daySessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 32, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              '${date.month}月${date.day}日 无专注记录',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final totalMinutes = daySessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${date.month}月${date.day}日详情',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '共 ${totalMinutes} 分钟',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...daySessions.map((session) {
            final subject = focusProvider.subjects.firstWhere(
              (s) => s.id == session.subjectId,
              orElse: () => focusProvider.subjects.first,
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: subject.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(subject.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${session.startTime.hour}:${session.startTime.minute.toString().padLeft(2, '0')} - '
                          '${session.endTime.hour}:${session.endTime.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${session.durationMinutes}分钟',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: subject.color,
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
          if (subjects.isEmpty)
            Center(
              child: Text(
                '暂无学科数据',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          else
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