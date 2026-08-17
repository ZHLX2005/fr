// Calendar core types: CalendarGroup + CalendarConfig (no domain deps,
// safe to import from domain/event.dart and domain/person.dart).

class CalendarGroup {
  /// default group id: all events/people default to this; never deletable.
  static const String defaultGroupId = 'default';

  final String id;
  final String name;
  final String? note;
  final int createdAt;

  const CalendarGroup({
    required this.id,
    required this.name,
    this.note,
    required this.createdAt,
  });

  bool get isDefault => id == defaultGroupId;

  CalendarGroup copyWith({String? name, String? note}) => CalendarGroup(
    id: id,
    name: name ?? this.name,
    note: note ?? this.note,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'note': note,
    'createdAt': createdAt,
  };

  factory CalendarGroup.fromJson(Map<String, dynamic> json) => CalendarGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    note: json['note'] as String?,
    createdAt: json['createdAt'] as int,
  );
}

class CalendarConfig {
  final String defaultSystem;
  final String startDateIso;
  final String defaultColorTag;

  const CalendarConfig({
    this.defaultSystem = 'solar',
    this.startDateIso = '2025-01-01',
    this.defaultColorTag = 'gray',
  });

  static const CalendarConfig defaultConfig = CalendarConfig();

  Map<String, dynamic> toJson() => {
    'defaultSystem': defaultSystem,
    'startDateIso': startDateIso,
    'defaultColorTag': defaultColorTag,
  };

  factory CalendarConfig.fromJson(Map<String, dynamic> json) =>
      CalendarConfig(
        defaultSystem: json['defaultSystem'] as String? ?? 'solar',
        startDateIso: json['startDateIso'] as String? ?? '2025-01-01',
        defaultColorTag: json['defaultColorTag'] as String? ?? 'gray',
      );
}
