import '../interfaces/message_data.dart';

/// 登录卡片数据（表单型单卡：email + password → login → 存 token）。
class LoginMessageData implements IMessageData {
  /// 预填邮箱（注册成功后跳登录可预填）
  final String? initialEmail;

  const LoginMessageData({this.initialEmail});

  @override
  String get type => 'login';
}
