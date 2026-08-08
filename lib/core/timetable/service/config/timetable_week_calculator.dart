import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../widgets/theme/zen_theme.dart';

/// 工具：给定一个日期，返回**该日期或之前最近的那个周一**。
///
/// 例：周三 → 回退 2 天到本周一；周一 → 原样；周日 → 回退 6 天到本周一。
/// 用于"输入开学日 → 自动定位起始周"。
DateTime findNearestMondayOnOrBefore(DateTime date) {
  // Dart DateTime.weekday: 1=Mon, 7=Sun
  final back = date.weekday - DateTime.monday;
  return DateTime(date.year, date.month, date.day - back);
}

/// 周数推算 / 日期回退到周一 的弹窗。Zen 主题。
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
    // Tab 内容用 _tab.index 条件渲染 → 必须监听 controller 触发 rebuild，
    // 否则切 Tab 只动指示器、下方内容不跟随（"弹窗切换无效"）。
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
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
    final todayMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final startDate = todayMonday.add(Duration(days: -(weekNum - 1) * 7));
    setState(() {
      _error = null;
      _resultDate = startDate.toIso8601String().split('T')[0];
    });
  }

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
    // 遮罩由 showDialog 的 barrier 承担；外层 Material 透明只裁圆角，
    // 底色/描边/圆角交给 zenCard()，避免双层 Material 重复描边导致圆角缺口。
    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: zenCard(),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      const Icon(Icons.calendar_month, color: ZenColors.sage, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '设置起始日期',
                        style: ZenText.title.copyWith(fontSize: 16),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, color: ZenColors.secondary, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // TabBar
                  Container(
                    decoration: BoxDecoration(
                      color: ZenColors.bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: TabBar(
                      controller: _tab,
                      labelColor: ZenColors.sage,
                      unselectedLabelColor: ZenColors.secondary,
                      indicator: BoxDecoration(
                        color: ZenColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: ZenColors.hair),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,
                      ),
                      tabs: const [
                        Tab(text: '周数推算'),
                        Tab(text: '选日期'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tab 1：输入周数
                  if (_tab.index == 0) ...[
                    Text(
                      '输入当前是第几周，推算出起始日期（周一）',
                      style: ZenText.label.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: ZenText.monoDigitSmall.copyWith(fontSize: 18),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '例如：10',
                        hintStyle: ZenText.label.copyWith(fontSize: 14, color: ZenColors.hair),
                        filled: true,
                        fillColor: ZenColors.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: ZenColors.hair),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: ZenColors.hair),
                        ),
                      ),
                      onSubmitted: (_) => _calculate(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _calculate,
                        style: zenButton(foreground: ZenColors.sage, border: ZenColors.hair),
                        child: const Text('计算起始日期'),
                      ),
                    ),
                  ] else ...[
                  // Tab 2：选日期回退
                    Text(
                      '选择任意一天，自动回退到当天或之前的最近周一。',
                      style: ZenText.label.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickDateAndCompute,
                        style: zenButton(foreground: ZenColors.sage, border: ZenColors.hair),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text('选择日期'),
                      ),
                    ),
                  ],
                  // 结果
                  if (_resultDate != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ZenColors.sage.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: ZenColors.sage.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Text('起始日期（周一）', style: ZenText.label),
                          const SizedBox(height: 4),
                          Text(
                            _resultDate!,
                            style: ZenText.monoDigitSmall.copyWith(
                              color: ZenColors.sage, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, _resultDate),
                        style: zenButton(foreground: ZenColors.sage, border: ZenColors.hair),
                        child: const Text('应用此日期'),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: ZenColors.mutedRed, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}