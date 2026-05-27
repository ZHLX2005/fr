part of 'inline_format.dart';

class MentionFormat extends InlineFormat {
  final String blockId;
  const MentionFormat(this.blockId);

  @override
  Map<String, dynamic> toJson() => {'type': 'mention', 'block_id': blockId};

  @override
  bool operator ==(Object other) =>
      other is MentionFormat && other.blockId == blockId;
  @override
  int get hashCode => blockId.hashCode;
}
