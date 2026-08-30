import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../../../api/user/user_auth_service.dart';
import '../../../core/chess/p2p/chess_identity.dart';
import '../data/login_message_data.dart';
import '../data/register_message_data.dart';
import 'message_panel_controller.dart';

/// 注册流程控制器（全局 ChangeNotifier + GetIt 单例）。
///
/// 持有注册过程中已收集的字段与当前步骤游标 [currentStep]，驱动 5 步
/// 渐进式卡片：email(发码) → code → password → invite(注册) → success。
///
/// 设计：方法返回 [AuthResult]，**只在成功时** append 下一步卡片到
/// [MessagePanelController]；失败把结果交还卡片，由卡片本地 State 显示错误。
/// [back] 支持中途回退修改任意步骤。
class RegisterFlowController extends ChangeNotifier {
  String email = '';
  String code = '';
  String password = '';
  String invitationCode = '';
  String nickname = '';
  int? userId;

  /// 当前所在步骤（用于 back 回退判断）
  RegisterStep currentStep = RegisterStep.email;

  MessagePanelController get _panel => GetIt.instance<MessagePanelController>();
  UserAuthService get _auth => GetIt.instance<UserAuthService>();

  /// 追加下一步卡片并更新游标
  void _go(RegisterStep step) {
    currentStep = step;
    _panel.append(RegisterMessageData(step));
  }

  /// 开始注册流程：清空字段，追加邮箱步卡片
  void start() {
    email = '';
    code = '';
    password = '';
    invitationCode = '';
    nickname = '';
    userId = null;
    _go(RegisterStep.email);
  }

  /// 邮箱步：发送验证码。成功则记录邮箱并追加验证码步。
  Future<AuthResult> sendCode(String email) async {
    final r = await _auth.sendCode(email);
    if (r.isSuccess) {
      this.email = email;
      _go(RegisterStep.code);
    }
    return r;
  }

  /// 验证码步：记录验证码，追加密码步。
  void submitCode(String code) {
    this.code = code;
    _go(RegisterStep.password);
  }

  /// 密码步：记录密码，追加邀请码步。
  void submitPassword(String password) {
    this.password = password;
    _go(RegisterStep.invite);
  }

  /// 邀请码步：发起注册。成功则记录并追加成功步。
  Future<AuthResult> register(String invitationCode, String nickname) async {
    final r = await _auth.register(
      email: email,
      password: password,
      code: code,
      invitationCode: invitationCode,
      nickname: nickname,
    );
    if (r.isSuccess) {
      this.invitationCode = invitationCode;
      this.nickname = nickname;
      final userId = r.data?['userId'] as int?;
      this.userId = userId;
      if (userId != null) {
        // 持久化真实登录 uid → ChessIdentity 用 uid-<userId> 做稳定身份
        // （根因 1：token 字符串不是身份，换 token/重登录会变 → 被当新玩家）。
        await ChessIdentity.persistUserId(userId);
      }
      _go(RegisterStep.success);
    }
    return r;
  }

  /// 回退一步：删当前卡 + 删前一步旧卡 + 重建前一步为全新可编辑卡。
  ///
  /// 重建（而非保留旧卡）让回退到的步骤回到初始可编辑状态，行为可预测、
  /// 无死锁；该步已填值需重填，但回退本就是为修改。flow 字段不清：
  /// 重新确认时会覆盖。email 为起点、success 为终点，不可回退。
  void back() {
    final prev = _prevOf(currentStep);
    if (prev == null) return;
    _panel.removeLast(); // 删当前卡
    // 前一张若是注册卡，一并删除以重建（跳过用户中途插入的其它卡片）
    if (_panel.messages.isNotEmpty &&
        _panel.messages.last.data is RegisterMessageData) {
      _panel.removeLast();
    }
    _go(prev); // 重建前一步新卡 + 游标回退
  }

  /// 成功步：跳登录卡（预填注册邮箱）
  void gotoLogin() {
    _panel.append(LoginMessageData(initialEmail: email));
  }

  static RegisterStep? _prevOf(RegisterStep s) => switch (s) {
        RegisterStep.email => null,
        RegisterStep.code => RegisterStep.email,
        RegisterStep.password => RegisterStep.code,
        RegisterStep.invite => RegisterStep.password,
        RegisterStep.success => null,
      };
}
