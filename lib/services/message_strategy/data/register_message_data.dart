import '../interfaces/message_data.dart';

/// 注册流程的步骤。
enum RegisterStep { email, code, password, invite, success }

/// 注册流程的一步卡片数据。
///
/// type 统一为 `'register'`，靠 [step] 区分该步渲染什么输入。
/// 整条流程由 [RegisterFlowController] 推进，每步确认后 append 下一步。
class RegisterMessageData implements IMessageData {
  final RegisterStep step;

  const RegisterMessageData(this.step);

  @override
  String get type => 'register';
}
