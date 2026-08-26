import 'package:meta/meta.dart';

import 'person.dart';

/// 内嵌的人物补丁 —— 直接挂在 Event.people 上，无需先建 Person。
///
/// `name` 是补丁的 key。重复 `name` 在同组中通过 `LabPeopleProvider.upsertPatch`
/// resolve 到全局 Person（已存在则按 patch 字段更新；不存在则新建）。
@immutable
class PersonPatch {
  final String? name;
  final PersonRelation? relation;
  final String? avatarEmoji;
  final String? note;
  const PersonPatch({this.name, this.relation, this.avatarEmoji, this.note});

  @override
  bool operator ==(Object o) =>
      o is PersonPatch &&
      o.name == name &&
      o.relation == relation &&
      o.avatarEmoji == avatarEmoji &&
      o.note == note;

  @override
  int get hashCode => Object.hash(name, relation, avatarEmoji, note);
}