/// 外部分享接收数据（Android ACTION_SEND → fr://share/receive 传递载荷）
class ShareReceiveData {
  final String? text;
  final List<String> fileUris;

  const ShareReceiveData({this.text, this.fileUris = const []});

  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) && fileUris.isEmpty;
}

/// 外部分享接收单例存储。
///
/// 与 ClockWidgetToggle 的 pending 模式一致：原生通道收到分享 →
/// 翻译器把载荷存入 pending → fr://share/receive handler 构建页面 →
/// 页面消费快照。
class ShareReceiveStore {
  ShareReceiveStore._();

  static ShareReceiveData? pending;
}
