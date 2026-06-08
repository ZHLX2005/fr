/// 下载控制器 — 支持取消 / 暂停 / 断点续传。
class DownloadController {
  bool _isCancelled = false;
  bool _isPaused = false;

  bool get isCancelled => _isCancelled;
  bool get isPaused => _isPaused;
  bool get shouldStop => _isCancelled || _isPaused;

  void cancel() => _isCancelled = true;
  void pause() => _isPaused = true;
  void reset() {
    _isCancelled = false;
    _isPaused = false;
  }
}
