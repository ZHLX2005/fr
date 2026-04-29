import '../interfaces/message_data.dart';

/// 水位胶囊消息数据
class WaterCapsuleMessageData implements IMessageData {
  final int level;

  WaterCapsuleMessageData(this.level);

  @override
  String get type => 'water_capsule';
}
