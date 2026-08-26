import '../../../../core/storage/hive/calendar_repository.dart';
import '../domain/event.dart';

/// Event 持久化包装（Hive Box 现在 untyped Map —— 见 CalendarRepository）。
class EventRepository {
  /// 读取所有事件
  List<Event> load() {
    return CalendarRepository.instance.loadEvents();
  }

  /// 新增事件
  Future<Event> add(Event e) async {
    await CalendarRepository.instance.saveEvent(e);
    return e;
  }

  /// 更新（按 id 覆盖）
  Future<void> update(Event e) async {
    await CalendarRepository.instance.saveEvent(e);
  }

  /// 删除（按 id）
  Future<void> delete(String id) async {
    await CalendarRepository.instance.deleteEvent(id);
  }
}