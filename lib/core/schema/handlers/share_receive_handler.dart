// lib/core/schema/handlers/share_receive_handler.dart
import 'package:flutter/material.dart';

import '../fr_route_handler.dart';
import '../../share_receive/share_receive_page.dart';

/// fr://share/receive → 外部分享接收页。
///
/// 其他 app 分享文本/文件到 FR：ACTION_SEND → MainActivity →
/// WidgetChannel.shareReceived → 翻译器把载荷存入 ShareReceiveStore.pending →
/// 本 handler 返回分享接收页（页面消费 pending 快照）。
class ShareReceiveHandler extends FrRouteHandler {
  const ShareReceiveHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    assert(
      match.authority == 'share/receive',
      'ShareReceiveHandler 期望 authority=share/receive,实际: ${match.authority}',
    );
    return const ShareReceivePage();
  }
}
