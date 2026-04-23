import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'timetable_colors.dart';

/// 学校模式：输入当前周数 → 计算起始日期
class WeekCalculatorDialog extends StatefulWidget {
  const WeekCalculatorDialog({super.key});

  @override
  State<WeekCalculatorDialog> createState() => _WeekCalculatorDialogState();
}

class _WeekCalculatorDialogState extends State<WeekCalculatorDialog> {
  final _controller = TextEditingController();
  String? _resultDate;
  String? _error;

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

  @override
  void dispose() {
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
              width: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TimetableColors.border, width: 1),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(Icons.calendar_month, color: TimetableColors.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '周数推算起始日期',
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
                  const SizedBox(height: 16),
                  // 说明
                  Text(
                    '输入当前是第几周，系统自动推算出开学起始日期（周一）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: TimetableColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 输入框
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '例如：10',
                      hintStyle: TextStyle(color: TimetableColors.textTertiary, fontSize: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                    onSubmitted: (_) => _calculate(),
                  ),
                  const SizedBox(height: 16),
                  // 计算按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _calculate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TimetableColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('计算起始日期', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  // 结果
                  if (_resultDate != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TimetableColors.selectedBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: TimetableColors.accent.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '起始日期',
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
                          side: BorderSide(color: TimetableColors.accent, width: 1.5),
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
