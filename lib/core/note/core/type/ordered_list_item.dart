part of 'type.dart';

class OrderedListItemType extends BlockType {
  final int number;

  const OrderedListItemType({this.number = 1})
    : super(tag: 'ordered_list_item', canHaveChildren: true);

  factory OrderedListItemType.fromData(Map<String, dynamic> data) {
    return OrderedListItemType(number: data['number'] as int? ?? 1);
  }

  @override
  Map<String, dynamic> toJson() => {'number': number};

  @override
  bool operator ==(Object other) =>
    other is OrderedListItemType && other.number == number;
  @override
  int get hashCode => Object.hash(runtimeType, number);

  @override
  BlockType? get onEnterType => OrderedListItemType(number: number + 1);

  static TypeConversionRule<BlockType> get inputTrigger => TypeConversionRule(
    pattern: RegExp(r'^(\d+)\. '),
    createType: (m) => OrderedListItemType(number: int.parse(m.group(1)!)),
  );
}
