import '../interfaces/message_data.dart';

/// 水位胶囊消息数据
class WaterCapsuleMessageData implements IMessageData {
  final int level;
  final bool dev;

  WaterCapsuleMessageData(this.level, {this.dev = false});

  @override
  String get type => 'water';
}
