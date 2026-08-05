import '../../../../core/storage/hive/calendar_repository.dart';
import '../domain/person.dart';

/// Person 持久化（Hive Box）
class PersonRepository {
  /// 读取所有人物
  List<Person> load() {
    return CalendarRepository.instance.people.values.toList();
  }

  /// 新增
  Future<Person> add(Person p) async {
    await CalendarRepository.instance.people.put(p.id, p);
    return p;
  }

  /// 更新
  Future<void> update(Person p) async {
    await CalendarRepository.instance.people.put(p.id, p);
  }

  /// 删除
  Future<void> remove(String id) async {
    await CalendarRepository.instance.people.delete(id);
  }
}