import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/focus_subject.dart';
import 'providers/focus_provider.dart';
import 'focus_timer_page.dart';
import 'focus_stats_page.dart';

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
                color: Colors.grey[600],
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFB5C9A3), // 柔和鼠尾草绿
            Color(0xFFD4E4C4),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB5C9A3).withValues(alpha: 0.25),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '学习领域',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            TextButton.icon(
              onPressed: () => _showSubjectManagement(context, focusProvider),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('管理'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
              ),
            ),
          ],
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
          color: subject.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: subject.color.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: subject.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    subject.icon,
                    size: 20,
                    color: subject.color,
                  ),
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
                backgroundColor: subject.color.withValues(alpha: 0.15),
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
                color: const Color(0xFF8B9DC3),
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
          color: color.withValues(alpha: 0.12),
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

  void _showSubjectManagement(BuildContext context, FocusProvider focusProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SubjectManagementSheet(focusProvider: focusProvider),
    );
  }
}

/// 科目管理底部弹窗
class _SubjectManagementSheet extends StatelessWidget {
  final FocusProvider focusProvider;

  const _SubjectManagementSheet({required this.focusProvider});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '管理学习领域',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _showEditDialog(context, null),
                  color: const Color(0xFF8B9DC3),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: focusProvider.subjects.length,
              itemBuilder: (context, index) {
                final subject = focusProvider.subjects[index];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: subject.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      subject.icon,
                      color: subject.color,
                    ),
                  ),
                  title: Text(subject.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showEditDialog(context, subject),
                        color: Colors.grey[600],
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _confirmDelete(context, subject),
                        color: Colors.red[300],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, FocusSubject? subject) {
    showDialog(
      context: context,
      builder: (context) => _SubjectEditDialog(
        subject: subject,
        onSave: (newSubject) async {
          if (subject == null) {
            await focusProvider.addSubject(newSubject);
          } else {
            await focusProvider.updateSubject(newSubject);
          }
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, FocusSubject subject) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除 "${subject.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await focusProvider.deleteSubject(subject.id);
            },
            child: Text('删除', style: TextStyle(color: Colors.red[300])),
          ),
        ],
      ),
    );
  }
}

/// 科目编辑对话框
class _SubjectEditDialog extends StatefulWidget {
  final FocusSubject? subject;
  final Future<void> Function(FocusSubject) onSave;

  const _SubjectEditDialog({
    this.subject,
    required this.onSave,
  });

  @override
  State<_SubjectEditDialog> createState() => _SubjectEditDialogState();
}

class _SubjectEditDialogState extends State<_SubjectEditDialog> {
  late TextEditingController _nameController;
  late int _selectedIconIndex;
  late int _selectedColorIndex;
  late int _targetHours;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.subject?.name ?? '');
    _selectedIconIndex = widget.subject != null
        ? FocusIcons.availableIcons.indexWhere(
            (i) => i == widget.subject!.iconIndex)
        : 0;
    if (_selectedIconIndex < 0) _selectedIconIndex = 0;

    _selectedColorIndex = widget.subject != null
        ? FocusColors.availableColors.indexWhere(
            (c) => c.toARGB32() == widget.subject!.color.toARGB32())
        : 0;
    if (_selectedColorIndex < 0) _selectedColorIndex = 0;

    _targetHours = (widget.subject?.targetMinutes ?? 3600) ~/ 60;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.subject == null ? '添加领域' : '编辑领域'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
              maxLength: 20,
            ),
            const SizedBox(height: 16),
            const Text('图标', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(FocusIcons.availableIcons.length, (index) {
                final isSelected = _selectedIconIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIconIndex = index),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? FocusColors.availableColors[_selectedColorIndex].withValues(alpha: 0.2)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: FocusColors.availableColors[_selectedColorIndex], width: 2)
                          : null,
                    ),
                    child: Icon(
                      FocusIcons.availableIcons[index],
                      size: 20,
                      color: isSelected ? FocusColors.availableColors[_selectedColorIndex] : Colors.grey[600],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text('颜色', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(FocusColors.availableColors.length, (index) {
                final isSelected = _selectedColorIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColorIndex = index),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: FocusColors.availableColors[index],
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: FocusColors.availableColors[index].withValues(alpha: 0.5),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text('目标学时（小时）', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _targetHours > 1
                      ? () => setState(() => _targetHours--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_targetHours',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                IconButton(
                  onPressed: () => setState(() => _targetHours++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 8),
                Text(
                  '小时',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            if (_nameController.text.trim().isEmpty) return;

            final subject = FocusSubject(
              id: widget.subject?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
              name: _nameController.text.trim(),
              color: FocusColors.availableColors[_selectedColorIndex],
              iconIndex: _selectedIconIndex,
              targetMinutes: _targetHours * 60,
              completedMinutes: widget.subject?.completedMinutes ?? 0,
            );

            await widget.onSave(subject);
            if (context.mounted) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            backgroundColor: FocusColors.availableColors[_selectedColorIndex],
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}