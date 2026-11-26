import 'package:flutter/material.dart';

import 'calendar_controls.dart';
import 'calendar_palette.dart';

/// 页头（原型 `.phead`）：左「标题 + 副标题」，右「控件组」。
///
/// 月页用它承载「2026年 11月 / 农历…本月 8 天有安排」（收起态换成
/// 「11月 · 第 1 周 / 收起态 · 上滑展开整月」），年页承载年份，周/日/日程
/// 承载各自标题——五个页签共用同一节奏，避免各页各写一套标题排版。
class CalendarPaneHeader extends StatelessWidget {
  const CalendarPaneHeader({
    super.key,
    required this.title,
    required this.palette,
    this.subtitle,
    this.actions = const <Widget>[],
    this.titleSize = 25,
  });

  final String title;
  final String? subtitle;
  final CalendarPalette palette;
  final List<Widget> actions;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleSize,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: palette.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: palette.textSecondary.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
        ],
      ),
    );
  }
}

/// 页头通用小按钮（原型 `.ibtn` 的 34×34 / 圆角 11 版本）。
class CalendarPaneAction extends StatelessWidget {
  const CalendarPaneAction({
    super.key,
    required this.icon,
    required this.palette,
    required this.onTap,
    this.tooltip,
    this.angle = 0,
  });

  final IconData icon;
  final CalendarPalette palette;
  final VoidCallback onTap;
  final String? tooltip;

  /// 图标旋转角（收起按钮用 π×(1-p) 表示展开/收起）。
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: CalendarIconButton(
        icon: icon,
        palette: palette,
        tooltip: tooltip,
        onTap: onTap,
        size: 34,
        iconSize: 18,
        angle: angle,
        radius: 11,
      ),
    );
  }
}
