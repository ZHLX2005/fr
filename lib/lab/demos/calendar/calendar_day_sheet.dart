import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/lab_calendar_event.dart';
import 'providers/lab_calendar_provider.dart';
import 'calendar_day_cell.dart';

/// 某天事件编辑底部抽屉
class CalendarDayEventSheet extends StatefulWidget {
  final int year;
  final int month;
  final int day;

  const CalendarDayEventSheet({
    super.key,
    required this.year,
    required this.month,
    required this.day,
  });

  @override
  State<CalendarDayEventSheet> createState() => _CalendarDayEventSheetState();
}

class _CalendarDayEventSheetState extends State<CalendarDayEventSheet> {
  final _titleController = TextEditingController();
  String _selectedColor = kLabCalendarPalette.first;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    final events = p.eventsOf(widget.year, widget.month, widget.day);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.year}年${widget.month}月${widget.day}日 · 待办',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '暂无待办，先添加一个',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: events.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final e = events[i];
                  final color = parseHex(e.color) ?? Colors.black;
                  return _EventTile(
                    color: color,
                    title: e.title,
                    description: e.description,
                    isSynced: e.isSyncedToSystemCalendar,
                    onDelete: () => p.deleteEvent(e.id),
                    onSyncToCalendar: () => _syncEvent(p, e.id),
                  );
                },
              ),
            ),
          const Divider(height: 24),
          const Text(
            '新建待办',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: '事件标题',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '颜色',
            style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: kLabCalendarPalette.map((c) {
              final isSel = c == _selectedColor;
              final color = parseHex(c) ?? Colors.black;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSel
                        ? Border.all(color: Colors.black, width: 3)
                        : Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加待办'),
              onPressed: _onAdd,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1976D2),
                side: const BorderSide(
                  color: Color(0xFF1976D2),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _onAdd() async {
    final p = context.read<LabCalendarProvider>();
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入事件标题')),
      );
      return;
    }
    await p.addEvent(
      year: widget.year,
      month: widget.month,
      day: widget.day,
      title: title,
      color: _selectedColor,
    );
    _titleController.clear();
  }

  Future<void> _syncEvent(LabCalendarProvider p, String eventId) async {
    final ok = await p.syncToSystemCalendar(eventId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已同步到系统日历' : '同步失败，请检查日历权限'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Color color;
  final String title;
  final String? description;
  final bool isSynced;
  final VoidCallback onDelete;
  final VoidCallback? onSyncToCalendar;

  const _EventTile({
    required this.color,
    required this.title,
    required this.description,
    required this.isSynced,
    required this.onDelete,
    this.onSyncToCalendar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSynced) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: Color(0xFF4CAF50),
                      ),
                    ],
                  ],
                ),
                if ((description ?? '').isNotEmpty)
                  Text(
                    description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF666666),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!isSynced && onSyncToCalendar != null)
            IconButton(
              icon: const Icon(Icons.sync_rounded, size: 18),
              color: const Color(0xFF1976D2),
              onPressed: onSyncToCalendar,
              tooltip: '同步到系统日历',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: const Color(0xFF999999),
            onPressed: onDelete,
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}
