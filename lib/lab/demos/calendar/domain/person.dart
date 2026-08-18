/// 人与日历所有者的关系
enum PersonRelation { self, family, friend, colleague, other }

class Person {
  final String id;
  final String name;
  final PersonRelation relation;
  final String? avatarEmoji; // 单 emoji 头像（避免图片依赖）
  final String? note;
  final DateTime createdAt;

  const Person({
    required this.id,
    required this.name,
    required this.relation,
    required this.createdAt,
    this.avatarEmoji,
    this.note,
  });

  Person copyWith({
    String? name,
    PersonRelation? relation,
    String? avatarEmoji,
    String? note,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      relation: relation ?? this.relation,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'relation': relation.name,
        if (avatarEmoji != null) 'avatarEmoji': avatarEmoji,
        if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String,
        name: j['name'] as String,
        relation: PersonRelation.values.byName(j['relation'] as String),
        avatarEmoji: j['avatarEmoji'] as String?,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
