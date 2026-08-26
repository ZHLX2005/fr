import 'package:meta/meta.dart';

import '../domain/event.dart';
import '../domain/anchor.dart';
import '../domain/period.dart';
import '../domain/person_patch.dart';

/// 事件草稿 —— DSL 解析、表单提交都先得到它，再由 Provider 落地为 Event。
///
/// 不含 `id` / `groupId` / `createdAt` —— 这些由 Provider 在落盘时分配。
@immutable
class EventDraft {
  final String title;
  final EventType type;
  final Anchor anchor;
  final Period period;
  final ColorTag colorTag;
  final List<PersonPatch> people;
  final String? note;
  const EventDraft({
    required this.title,
    required this.type,
    required this.anchor,
    required this.period,
    required this.colorTag,
    this.people = const [],
    this.note,
  });
}