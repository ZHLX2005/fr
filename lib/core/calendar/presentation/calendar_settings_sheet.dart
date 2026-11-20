import 'package:flutter/material.dart';

import 'calendar_controls.dart';
import 'calendar_palette.dart';
import 'calendar_view_menu.dart';
import 'calendar_view_mode.dart';

Future<void> showCalendarSettingsSheet(
  BuildContext context, {
  required CalendarPalette palette,
  required CalendarViewMode viewMode,
  required bool showCompleted,
  required bool mondayFirst,
  required ValueChanged<CalendarViewMode> onViewModeChanged,
  required ValueChanged<bool> onShowCompletedChanged,
  required ValueChanged<bool> onMondayFirstChanged,
  required VoidCallback onGoToday,
}) {
  var currentMode = viewMode;
  var currentShowCompleted = showCompleted;
  var currentMondayFirst = mondayFirst;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.16),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '日历设置',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(sheetContext).pop(),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: palette.surfaceAlt,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '视图',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.6,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    _ViewModeGrid(
                      current: currentMode,
                      palette: palette,
                      onSelected: (mode) {
                        setSheetState(() => currentMode = mode);
                        onViewModeChanged(mode);
                      },
                    ),
                    const SizedBox(height: 14),
                    _SettingSwitchRow(
                      icon: Icons.check_circle_outline,
                      label: '显示已完成任务',
                      value: currentShowCompleted,
                      palette: palette,
                      onChanged: (value) {
                        setSheetState(() => currentShowCompleted = value);
                        onShowCompletedChanged(value);
                      },
                    ),
                    _SettingSwitchRow(
                      icon: Icons.today_outlined,
                      label: '周一作为一周开始',
                      value: currentMondayFirst,
                      palette: palette,
                      onChanged: (value) {
                        setSheetState(() => currentMondayFirst = value);
                        onMondayFirstChanged(value);
                      },
                    ),
                    _SettingActionRow(
                      icon: Icons.my_location_outlined,
                      label: '回到今天',
                      palette: palette,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onGoToday();
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: CalendarActionButton(
                        label: '完成',
                        palette: palette,
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _ViewModeGrid extends StatelessWidget {
  const _ViewModeGrid({
    required this.current,
    required this.palette,
    required this.onSelected,
  });

  final CalendarViewMode current;
  final CalendarPalette palette;
  final ValueChanged<CalendarViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in CalendarViewMode.values)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: width,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        calendarViewModeIcon(mode),
                        size: 18,
                        color: current == mode
                            ? palette.accent
                            : palette.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current == mode
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: current == mode
                              ? palette.accent
                              : palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final CalendarPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Icon(icon, size: 20, color: palette.textSecondary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 14, color: palette.textPrimary),
          ),
          const Spacer(),
          CalendarSwitch(
            value: value,
            palette: palette,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingActionRow extends StatelessWidget {
  const _SettingActionRow({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Icon(icon, size: 20, color: palette.textSecondary),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 14, color: palette.textPrimary),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
