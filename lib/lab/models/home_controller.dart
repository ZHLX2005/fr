import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'home_item.dart';
import 'home_state.dart';

/// 桌面控制器
class HomeController extends ChangeNotifier {
  List<HomeItem> _items = [];
  List<HomeItem>? _previewItems;
  DragState _drag = DragState.empty;
  final HistoryStack _history = HistoryStack();

  List<HomeItem> get items => _items;
  DragState get drag => _drag;
  HistoryStack get history => _history;
  bool get canUndo => _history.canUndo;

  List<HomeItem> get visibleItems => _previewItems ?? _items;

  HomeController() {
    _initDefaultItems();
  }

  void _initDefaultItems() {
    _items = [
      AppItem(
        id: '1',
        title: '微信',
        icon: Icons.chat,
        color: const Color(0xFF07C160),
      ),
      AppItem(
        id: '2',
        title: 'QQ',
        icon: Icons.message,
        color: const Color(0xFF12B7F5),
      ),
      AppItem(
        id: '3',
        title: '淘宝',
        icon: Icons.shopping_bag,
        color: const Color(0xFFFF6A00),
      ),
      AppItem(
        id: '4',
        title: '抖音',
        icon: Icons.music_video,
        color: const Color(0xFF000000),
      ),
      AppItem(
        id: '5',
        title: '京东',
        icon: Icons.local_mall,
        color: const Color(0xFFE4393C),
      ),
      AppItem(
        id: '6',
        title: '拼多多',
        icon: Icons.thumb_up,
        color: const Color(0xFFE22018),
      ),
      AppItem(
        id: '7',
        title: '美团',
        icon: Icons.fastfood,
        color: const Color(0xFFFF6B00),
      ),
      AppItem(
        id: '8',
        title: '支付宝',
        icon: Icons.payment,
        color: const Color(0xFF1677FF),
      ),
      AppItem(
        id: '9',
        title: '银行',
        icon: Icons.account_balance,
        color: const Color(0xFF2196F3),
      ),
    ];
  }

  /// 开始拖拽
  void startDrag(String itemId) {
    _drag = DragState(draggingId: itemId);
    _previewItems = null;
    notifyListeners();
  }

  /// 更新悬停索引（用于占位符预览）
  void updateHoverIndex(int index) {
    if (_drag.draggingId == null) return;

    final before = _items;
    final dragging = before.firstWhere(
      (e) => e.id == _drag.draggingId,
      orElse: () => PlaceholderItem(),
    );
    if (dragging is! AppItem) return;

    final list = before.where((e) => e.id != dragging.id).toList();
    final clamped = index.clamp(0, list.length);
    list.insert(clamped, PlaceholderItem());

    _previewItems = list;
    _drag = _drag.copyWith(
      hoverIndex: clamped,
      hoverOverItemId: null,
      isFolderHover: false,
    );
    notifyListeners();
  }

  /// 更新悬停在某个item上（用于文件夹合并）
  void updateHoverOverItem(String targetItemId, {required bool folderHover}) {
    if (_drag.draggingId == null) return;
    _drag = _drag.copyWith(
      hoverOverItemId: targetItemId,
      isFolderHover: folderHover,
    );
    notifyListeners();
  }

  /// 清除悬停状态
  void clearHover() {
    _drag = _drag.copyWith(hoverOverItemId: null, isFolderHover: false);
    notifyListeners();
  }

  /// 取消拖拽
  void cancelDrag() {
    _previewItems = null;
    _drag = DragState.empty;
    notifyListeners();
  }

  /// 提交排序
  void commitReorder() {
    if (_drag.draggingId == null ||
        _previewItems == null ||
        _drag.hoverIndex == null) {
      cancelDrag();
      return;
    }

    final before = List<HomeItem>.from(_items);
    final dragging = before.firstWhere(
      (e) => e.id == _drag.draggingId,
      orElse: () => PlaceholderItem(),
    );
    if (dragging is! AppItem) {
      cancelDrag();
      return;
    }

    // 移除占位符，插入真实item
    final next = _previewItems!
        .where((e) => e.type != HomeItemType.placeholder)
        .toList();

    final idx = _drag.hoverIndex!.clamp(0, next.length);
    next.insert(idx, dragging);

    _history.push(ReorderCommand(before, next));
    _items = next;

    cancelDrag();
  }

  /// 提交合并到文件夹
  void commitMergeToFolder(String targetId) {
    if (_drag.draggingId == null) return;

    final before = List<HomeItem>.from(_items);
    final dragging = before.firstWhere(
      (e) => e.id == _drag.draggingId,
      orElse: () => PlaceholderItem(),
    );
    if (dragging is! AppItem || dragging.id == targetId) {
      cancelDrag();
      return;
    }

    final target = before.firstWhere(
      (e) => e.id == targetId,
      orElse: () => PlaceholderItem(),
    );

    List<HomeItem> next = List.of(before);

    // 移除拖拽的item
    next.removeWhere((e) => e.id == dragging.id);

    HomeItem merged;
    if (target is AppItem) {
      // App + App -> 新建文件夹
      merged = FolderItem(
        id: 'folder_${target.id}_${dragging.id}',
        title: '文件夹',
        children: [target, dragging],
      );
      final tIndex = next.indexWhere((e) => e.id == target.id);
      if (tIndex >= 0) {
        next[tIndex] = merged;
      }
    } else if (target is FolderItem) {
      // App + Folder -> 添加到文件夹
      final tIndex = next.indexWhere((e) => e.id == target.id);
      if (tIndex >= 0) {
        merged = FolderItem(
          id: target.id,
          title: target.title,
          children: [...target.children, dragging],
        );
        next[tIndex] = merged;
      } else {
        cancelDrag();
        return;
      }
    } else {
      cancelDrag();
      return;
    }

    _history.push(MergeToFolderCommand(before, next));
    _items = next;

    cancelDrag();
  }

  /// 撤销
  void undo() {
    final cmd = _history.popUndo();
    if (cmd == null) return;
    _items = cmd.undo(_items);
    notifyListeners();
  }

  /// 添加应用
  void addItem(AppItem item) {
    _items.add(item);
    notifyListeners();
  }

  /// 添加文件夹
  void addFolder(FolderItem folder) {
    _items.add(folder);
    notifyListeners();
  }

  /// 从文件夹移除应用（解散文件夹时用到）
  void removeAppFromFolder(String folderId, String appId) {
    final index = _items.indexWhere((e) => e.id == folderId);
    if (index >= 0 && _items[index] is FolderItem) {
      final folder = _items[index] as FolderItem;
      final newChildren = folder.children.where((c) => c.id != appId).toList();
      if (newChildren.isEmpty) {
        // 如果文件夹空了，移除文件夹
        _items.removeAt(index);
      } else if (newChildren.length == 1) {
        // 只剩一个应用，解散文件夹
        _items[index] = newChildren.first;
      } else {
        _items[index] = folder.copyWith(children: newChildren);
      }
      notifyListeners();
    }
  }

  /// 编辑应用
  void editItem(String id, {String? title, IconData? icon, Color? color}) {
    final index = _items.indexWhere((e) => e.id == id);
    if (index >= 0 && _items[index] is AppItem) {
      final item = _items[index] as AppItem;
      _items[index] = item.copyWith(title: title, icon: icon, color: color);
      notifyListeners();
    }
  }
}
