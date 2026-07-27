import '../domain/person.dart';
import 'calendar_hive.dart';

/// Person 持久化（Hive Box）
class PersonRepository {
  /// 读取所有人物
  List<Person> load() {
    return CalendarHive.people.values.toList();
  }

  /// 新增
  Future<Person> add(Person p) async {
    await CalendarHive.people.put(p.id, p);
    return p;
  }

  /// 更新
  Future<void> update(Person p) async {
    await CalendarHive.people.put(p.id, p);
  }

  /// 删除
  Future<void> remove(String id) async {
    await CalendarHive.people.delete(id);
  }
}