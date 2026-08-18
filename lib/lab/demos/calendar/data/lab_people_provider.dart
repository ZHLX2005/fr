import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/hive/calendar_repository.dart';
import '../data/calendar_config.dart';
import '../domain/person.dart';
import 'person_repository.dart';

class LabPeopleProvider with ChangeNotifier {
  /// 当前活跃实例
  static LabPeopleProvider? current;

  final PersonRepository _repo = PersonRepository();
  final _uuid = const Uuid();

  List<Person> _people = [];
  String _activeGroupId = CalendarGroup.defaultGroupId;
  bool _ready = false;

  /// 当前 group 的人（按 groupId 过滤）
  List<Person> get people => List.unmodifiable(
      _people.where((p) => p.groupId == _activeGroupId));
  /// 所有 group 的人
  List<Person> get allPeople => List.unmodifiable(_people);

  /// 数据是否已加载完成（Hive init + 人员加载）。未完成时视图渲染 loading 占位。
  bool get ready => _ready;
  String get activeGroupId => _activeGroupId;

  LabPeopleProvider() {
    current = this;
    _init();
  }

  Future<void> _init() async {
    await CalendarRepository.instance.init();
    _activeGroupId = await CalendarRepository.instance.getActiveGroupId();
    _people = _repo.load();
    _ready = true;
    notifyListeners();
  }

  /// 与 LabCalendarProvider 同步激活 group（双向）
  Future<void> setActiveGroup(String groupId) async {
    if (_activeGroupId == groupId) return;
    _activeGroupId = groupId;
    notifyListeners();
  }

  Person? byId(String id) {
    for (final p in _people) {
      if (p.id == id && p.groupId == _activeGroupId) return p;
    }
    return null;
  }

  /// 全局 byId（不限 group）—— DSL 解析/事件 personId 引用用
  Person? byIdAnyGroup(String id) {
    for (final p in _people) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<Person> add({
    required String name,
    required PersonRelation relation,
    String? avatarEmoji,
    String? note,
  }) async {
    final p = Person(
      id: _uuid.v4(),
      name: name,
      relation: relation,
      avatarEmoji: avatarEmoji,
      note: note,
      createdAt: DateTime.now(),
      groupId: _activeGroupId,
    );
    _people.add(p);
    await _repo.add(p);
    notifyListeners();
    return p;
  }

  Future<void> update(Person p) async {
    final i = _people.indexWhere((x) => x.id == p.id);
    if (i == -1) return;
    _people[i] = p;
    await _repo.update(p);
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _people.removeWhere((p) => p.id == id);
    await _repo.remove(id);
    notifyListeners();
  }

  /// 删除指定 group 的所有人（删除 group 时调用）
  Future<void> removeByGroup(String groupId) async {
    final toDelete = _people.where((p) => p.groupId == groupId).toList();
    for (final p in toDelete) {
      _people.removeWhere((x) => x.id == p.id);
      await _repo.remove(p.id);
    }
    if (toDelete.isNotEmpty) notifyListeners();
  }

  List<Person> byRelation(PersonRelation r) =>
      _people.where((p) => p.groupId == _activeGroupId && p.relation == r).toList();
}