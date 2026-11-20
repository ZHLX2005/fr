import 'package:flutter/material.dart';

import 'calendar_palette.dart';
import 'calendar_view_mode.dart';

IconData calendarViewModeIcon(CalendarViewMode mode) {
  switch (mode) {
    case CalendarViewMode.list:
      return Icons.view_agenda_outlined;
    case CalendarViewMode.year:
      return Icons.grid_view_rounded;
    case CalendarViewMode.month:
      return Icons.calendar_view_month_outlined;
    case CalendarViewMode.week:
      return Icons.view_week_outlined;
    case CalendarViewMode.threeDay:
      return Icons.view_column_outlined;
    case CalendarViewMode.day:
      return Icons.view_day_outlined;
  }
}

/// 顶部“视图”菜单：锚定在右上角，不用系统 PopupMenu。
Future<CalendarViewMode?> showCalendarViewMenu(
  BuildContext context, {
  required CalendarViewMode current,
  required CalendarPalette palette,
}) {
  return showGeneralDialog<CalendarViewMode>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭视图菜单',
    barrierColor: Colors.black.withValues(alpha: 0.04),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              top: MediaQuery.of(context).padding.top + 58,
              right: 10,
              width: 252,
              child: _ViewMenuCard(
                current: current,
                palette: palette,
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.035),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ViewMenuCard extends StatelessWidget {
  const _ViewMenuCard({required this.current, required this.palette});

  final CalendarViewMode current;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.overlay,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in CalendarViewMode.values)
              _ViewMenuRow(
                mode: mode,
                selected: mode == current,
                palette: palette,
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewMenuRow extends StatelessWidget {
  const _ViewMenuRow({
    required this.mode,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final CalendarViewMode mode;
  final bool selected;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.accent : palette.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.transparent,
        child: Row(
          children: [
            Icon(calendarViewModeIcon(mode), size: 23, color: color),
            const SizedBox(width: 17),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 17,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 14, color: palette.accent),
              ),
          ],
        ),
      ),
    );
  }
}
