import 'package:meta/meta.dart';

import 'event.dart';
import 'person.dart';

/// 事件在某天的发生实例（已 resolve 到公历）。
///
/// `person` 是把 `Event.people` 的 `PersonPatch` resolve 到全局 Person 后的结果；
/// 当前实现下，多数路径返回 `null`（resolve 在 UI / 显示层做）。
@immutable
class EventOccurrence {
  final Event event;
  final DateTime date; // 公历
  final DateTime? endDate; // 本期不实现，预留
  final Person? person;
  const EventOccurrence({
    required this.event,
    required this.date,
    this.endDate,
    this.person,
  });

  @override
  bool operator ==(Object o) =>
      o is EventOccurrence &&
      o.event == event &&
      o.date == date &&
      o.endDate == endDate &&
      o.person == person;

  @override
  int get hashCode => Object.hash(event, date, endDate, person);
}