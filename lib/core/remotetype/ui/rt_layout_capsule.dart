// lib/core/remotetype/ui/rt_layout_capsule.dart
//
// 布局胶囊：所有布局共用的左上角控件。
//
// 点开 = 布局面板（第一层是全部布局的列表，最下面是「远程输入设置」入口）。
// 连接状态点 + 当前布局名同在一颗胶囊里——用户随时知道「现在在哪张布局、
// 还在不在连着」，切布局只差一次点按。
//
// 画布（横屏）与写字页（竖屏）用同一份：布局之间是平级的，控件也平级，
// 所以写字页不再单开一套「返回写字」之类的旁门。

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 左上角布局胶囊：状态点 + 当前布局名 + chevron，点开进布局面板。
class RtLayoutCapsule extends StatelessWidget {
  const RtLayoutCapsule({
    super.key,
    required this.connected,
    required this.layoutName,
    required this.onOpen,
  });

  /// 连接状态（点为连接色，未连为灰）。
  final bool connected;

  /// 当前布局名。
  final String layoutName;

  /// 点开：打开布局面板（布局列表 + 设置入口）。
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onOpen();
            },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 状态点：连接色 + 同色光晕（对齐原型 dot halo）。
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? cs.primary : cs.outlineVariant,
                      boxShadow: connected
                          ? [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.25),
                                spreadRadius: 2.5,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      layoutName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.expand_more,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
