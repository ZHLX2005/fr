import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'workspace_manager.dart';
import 'page_model.dart';

/// 工作区 Provider
///
/// 遵循项目现有模式（ChangeNotifier + provider package）。
/// 通过 context.watch 驱动 UI 刷新。
class WorkspaceProvider extends ChangeNotifier {
  final WorkspaceManager _manager;

  WorkspaceProvider() : _manager = WorkspaceManager();

  WorkspaceManager get manager => _manager;
  List<PageModel> get pages => _manager.pages;
  PageModel? get activePage => _manager.activePage;
  String? get activePageId => _manager.activePageId;
  bool get initialized => _manager.initialized;

  /// 从磁盘加载。首次使用则创建默认页。
  Future<void> init() async {
    await _manager.init();
    notifyListeners();
  }

  /// 创建新页面
  void createPage({String? title}) {
    _manager.createPage(title: title);
    notifyListeners();
  }

  /// 切换页面
  void switchPage(String id) {
    _manager.switchPage(id);
    notifyListeners();
  }

  /// 删除页面
  void deletePage(String id) {
    _manager.deletePage(id);
    notifyListeners();
  }

  /// 重命名页面
  void renamePage(String id, String newTitle) {
    for (final page in _manager.pages) {
      if (page.id == id) {
        page.title = newTitle;
        notifyListeners();
        return;
      }
    }
  }

  /// AI 命令处理
  Future<String> processAiCommand(String command, {String? selectedBlockId}) async {
    final result = await _manager.processAiCommand(command, selectedBlockId: selectedBlockId);
    notifyListeners();
    return result;
  }

  // ──────────── 便捷访问 ────────────

  /// 通过 Provider 获取 WorkspaceProvider（相当于 context.read）
  static WorkspaceProvider of(BuildContext context, {bool listen = false}) {
    return listen
        ? context.watch<WorkspaceProvider>()
        : context.read<WorkspaceProvider>();
  }
}
