import 'package:flutter/material.dart';

import '../../../../../core/theme/component/calendar/paper_palette.dart';
import '../../domain/person.dart';

/// 人物头像 chip：emoji 优先，否则取姓名首字符
class PersonChip extends StatelessWidget {
  final Person? person;
  final double size;
  const PersonChip({super.key, required this.person, this.size = 16});

  static String emojiOf(Person? p) {
    if (p == null) return '👤';
    if (p.avatarEmoji != null && p.avatarEmoji!.isNotEmpty) return p.avatarEmoji!;
    if (p.name.isEmpty) return '👤';
    return p.name.substring(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    final emoji = emojiOf(person);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pp.bgElevated,
        shape: BoxShape.circle,
        border: Border.all(color: pp.line, width: 1),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
    );
  }
}