import 'package:meta/meta.dart';

/// 历法 anchor —— 事件首次发生的历法 + 历法下的年月日。
///
/// `sealed` 设计使得 `Period.yearly` 在 `solar` / `lunar` 之间取值时编译器能帮忙穷举。
@immutable
sealed class Anchor {
  const Anchor();
}

@immutable
class SolarAnchor extends Anchor {
  final int month; // 1-12
  final int day;   // 1-31
  final int year;
  const SolarAnchor({required this.month, required this.day, required this.year});

  @override
  bool operator ==(Object o) =>
      o is SolarAnchor && o.month == month && o.day == day && o.year == year;

  @override
  int get hashCode => Object.hash(month, day, year);
}

@immutable
class LunarAnchor extends Anchor {
  final int month;   // 1-12
  final int day;     // 1-30
  final bool isLeap; // 仅闰月才有意义
  final int year;    // 农历年
  const LunarAnchor({
    required this.month,
    required this.day,
    required this.isLeap,
    required this.year,
  });

  @override
  bool operator ==(Object o) =>
      o is LunarAnchor &&
      o.month == month &&
      o.day == day &&
      o.isLeap == isLeap &&
      o.year == year;

  @override
  int get hashCode => Object.hash(month, day, isLeap, year);
}

/// 工厂扩展，提供 AnchorFactory.solar(...) / lunar(...) 形式。
/// （命名为 *Factory 而不是 Anchor.solar() 是为了避免和 sealed 子类构造器重名。）
extension AnchorFactory on Anchor {
  static Anchor solar({required int month, required int day, required int year}) =>
      SolarAnchor(month: month, day: day, year: year);

  static Anchor lunar({
    required int month,
    required int day,
    required bool isLeap,
    required int year,
  }) =>
      LunarAnchor(month: month, day: day, isLeap: isLeap, year: year);
}