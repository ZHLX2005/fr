import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/hive/calendar_repository.dart';
import '../domain/person.dart';
import 'person_repository.dart';

class LabPeopleProvider with ChangeNotifier {
  final PersonRepository _repo = PersonRepository();
  final _uuid = const Uuid();

  List<Person> _people = [];
  bool _ready = false;
  List<Person> get people => List.unmodifiable(_people);

  /// 数据是否已加载完成（Hive init + 人员加载）。未完成时视图渲染 loading 占位。
  bool get ready => _ready;

  LabPeopleProvider() {
    _init();
  }

  Future<void> _init() async {
    await CalendarRepository.instance.init();
    _people = _repo.load();
    _ready = true;
    notifyListeners();
  }

  Person? byId(String id) {
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

  List<Person> byRelation(PersonRelation r) =>
      _people.where((p) => p.relation == r).toList();
}