import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../presentation/timetable_colors.dart';

/// 工具：给定一个日期，返回**该日期或之前最近的那个周一**。
///
/// 例：周三 → 回退 2 天到本周一；周一 → 原样；周日 → 回退 6 天到本周一。
/// 用于"输入开学日 → 自动定位起始周"。
DateTime findNearestMondayOnOrBefore(DateTime date) {
  // Dart DateTime.weekday: 1=Mon, 7=Sun
  final back = date.weekday - DateTime.monday;
  return DateTime(date.year, date.month, date.day - back);
}

/// 学校模式：输入当前周数 → 计算起始日期
/// 输入任意日期 → 自动回退到该日期之前的最近周一
class WeekCalculatorDialog extends StatefulWidget {
  const WeekCalculatorDialog({super.key});

  @override
  State<WeekCalculatorDialog> createState() => _WeekCalculatorDialogState();
}

class _WeekCalculatorDialogState extends State<WeekCalculatorDialog>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final TabController _tab;
  String? _resultDate;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  void _calculate() {
    final input = _controller.text.trim();
    final weekNum = int.tryParse(input);
    if (weekNum == null || weekNum < 1) {
      setState(() {
        _error = '请输入有效的周数（≥1）';
        _resultDate = null;
      });
      return;
    }

    final today = DateTime.now();
    // 找到今天所在周的周一
    final todayMonday = today.subtract(Duration(days: today.weekday - 1));
    // 起始日期 = 今天周一 - (weekNum - 1) * 7天
    final startDate = todayMonday.subtract(Duration(days: (weekNum - 1) * 7));

    setState(() {
      _error = null;
      _resultDate = startDate.toIso8601String().split('T')[0];
    });
  }

  /// 从任意日期回到之前的最近周一
  Future<void> _pickDateAndCompute() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择开学日期或之前的任意一天',
    );
    if (picked == null) return;
    final monday = findNearestMondayOnOrBefore(picked);
    setState(() {
      _error = null;
      _resultDate = monday.toIso8601String().split('T')[0];
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(color: Colors.black26),
        ),
        Center(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surface,
            child: Container(
              width: 320,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TimetableColors.border, width: 1),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(Icons.calendar_month, color: TimetableColors.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '起始日期',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: TimetableColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Tab：第几周 / 任意日期
                  TabBar(
                    controller: _tab,
                    labelColor: TimetableColors.accent,
                    unselectedLabelColor: TimetableColors.textSecondary,
                    indicatorColor: TimetableColors.accent,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: '当前是第几周'),
                      Tab(text: '选日期自动回退到周一'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Tab 1：输入周数
                  if (_tab.index == 0) ...[
                    Text(
                      '输入当前是第几周，系统自动推算出开学起始日期（周一）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: TimetableColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '例如：10',
                        hintStyle: TextStyle(
                          color: TimetableColors.textTertiary,
                          fontSize: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                      onSubmitted: (_) => _calculate(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _calculate,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TimetableColors.accent,
                          side: BorderSide(
                            color: TimetableColors.accent.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '计算起始日期',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ] else ...[
                  // Tab 2：选日期回退
                    Text(
                      '选择开学日（任意一天），系统自动回退到当天或之前的最近周一。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: TimetableColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickDateAndCompute,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TimetableColors.accent,
                          side: BorderSide(
                            color: TimetableColors.accent.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text(
                          '选择日期',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                  // 结果（两种 tab 共享）
                  if (_resultDate != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TimetableColors.selectedBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: TimetableColors.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '起始日期（周一）',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: TimetableColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _resultDate!,
                            style: TextStyle(
                              color: TimetableColors.accent,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, _resultDate),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: TimetableColors.accent,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          '应用此日期',
                          style: TextStyle(
                            color: TimetableColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
