part of 'type.dart';

class SyncedBlockType extends BlockType {
  final String refBlockId;

  const SyncedBlockType({this.refBlockId = ''})
    : super(tag: 'synced_block');

  factory SyncedBlockType.fromData(Map<String, dynamic> data) {
    return SyncedBlockType(refBlockId: data['refBlockId'] as String? ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {'refBlockId': refBlockId};

  @override
  bool operator ==(Object other) =>
    other is SyncedBlockType && other.refBlockId == refBlockId;
  @override
  int get hashCode => Object.hash(runtimeType, refBlockId);
}
