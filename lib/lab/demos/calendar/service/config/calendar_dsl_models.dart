// Calendar DSL model types (depend on domain Event/Person).
// Kept separate from calendar_config.dart to avoid import cycle:
//   domain/person.dart -> calendar_config.dart (for defaultGroupId)
//   calendar_config.dart -> domain/person.dart (would cycle)

import '../../domain/event.dart';
import '../../domain/person.dart';
import '../../data/calendar_config.dart';

export '../../data/calendar_config.dart' show CalendarGroup, CalendarConfig;

/// DSL parse result (events + person drafts + config + errors).
class CalendarDslFullResult {
  final List<Event> events;
  final List<CalendarPersonDraft> persons;
  final CalendarConfig? config;
  final List<String> errors;

  const CalendarDslFullResult({
    required this.events,
    required this.persons,
    required this.config,
    required this.errors,
  });
}

/// DSL person draft: created during parse, mapped to Person on apply.
/// relation is the PersonRelation.name string (DSL text format).
class CalendarPersonDraft {
  final String id;
  final String name;
  final String? relation;
  final String? avatarEmoji;
  final String? note;

  const CalendarPersonDraft({
    required this.id,
    required this.name,
    this.relation,
    this.avatarEmoji,
    this.note,
  });

  /// Convert relation name to PersonRelation enum.
  PersonRelation? get relationEnum {
    if (relation == null) return null;
    for (final r in PersonRelation.values) {
      if (r.name == relation) return r;
    }
    return null;
  }
}
