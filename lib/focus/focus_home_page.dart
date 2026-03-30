import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/focus_subject.dart';
import 'providers/focus_provider.dart';
import 'focus_timer_page.dart';
import 'focus_stats_page.dart';
import 'package:provider/provider.dart';

/// 专注计时器首页 - Dashboard
class FocusHomePage extends StatelessWidget {
  const FocusHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<FocusProvider>(
          builder: (context, focusProvider, child) {
            if (focusProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreeting(context),
                  const SizedBox(height: 32),
                  _buildTodayCard(context, focusProvider),
                  const SizedBox(height: 24),
                  _buildSubjectSection(context, focusProvider),
                  const SizedBox(height: 24),
                  _buildQuickActions(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 问候语
  Widget _buildGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 6) {
      greeting = '夜深了';
    } else if (hour < 12) {
      greeting = '早上好';
    } else if (hour < 18) {
      greeting = '下午好';
    } else {
      greeting = '晚上好';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting，',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w300,
                color: Colors.grey[700],
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '今天准备深潜到哪一段时光？',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w400,
              ),
        ),
      ],
    );
  }

  /// 今日学时卡片
  Widget _buildTodayCard(BuildContext context, FocusProvider focusProvider) {
    final todayMinutes = focusProvider.getTodayMinutes();
    final hours = todayMinutes ~/ 60;
    final minutes = todayMinutes % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF9CAF88), // 鼠尾草绿
            const Color(0xFFB5C9A3),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9CAF88).withValues(alpha: 0.3),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日专注',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hours > 0 ? '$hours' : '${minutes.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  hours > 0 ? ' 小时 ${minutes.toString().padLeft(2, '0')} 分钟' : ' 分钟',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 科目快捷入口
  Widget _buildSubjectSection(BuildContext context, FocusProvider focusProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '学习领域',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
          ),
          itemCount: focusProvider.subjects.length > 4 ? 4 : focusProvider.subjects.length,
          itemBuilder: (context, index) {
            final subject = focusProvider.subjects[index];
            return _buildSubjectCard(context, subject, focusProvider);
          },
        ),
      ],
    );
  }

  /// 科目卡片
  Widget _buildSubjectCard(BuildContext context, FocusSubject subject, FocusProvider focusProvider) {
    final completedMinutes = focusProvider.getSubjectMinutes(subject.id);
    final hours = completedMinutes ~/ 60;
    final minutes = completedMinutes % 60;

    return GestureDetector(
      onTap: () => _navigateToTimer(context, subject),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: subject.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: subject.color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  subject.icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subject.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: subject.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              hours > 0 ? '$hours 小时 $minutes 分钟' : '$minutes 分钟',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: subject.progress,
                backgroundColor: subject.color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(subject.color),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 快捷操作
  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                context,
                icon: Icons.bar_chart_outlined,
                label: '数据统计',
                color: const Color(0xFF5C9EAD),
                onTap: () => _navigateToStats(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 操作按钮
  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToTimer(BuildContext context, [FocusSubject? subject]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FocusTimerPage(initialSubject: subject),
      ),
    );
  }

  void _navigateToStats(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FocusStatsPage(),
      ),
    );
  }

}
