import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bookmark_item.dart';

/// 索引映射器 - 处理 displayIndex 和 bookmarkIndex 之间的转换
class IndexMapper {
  final Map<int, int> _displayToBookmark = {};
  final Map<int, int> _bookmarkToDisplay = {};

  void rebuild(List<BookmarkItem> displayItems) {
    _displayToBookmark.clear();
    _bookmarkToDisplay.clear();
    int bookmarkIdx = 0;
    for (int displayIdx = 0; displayIdx < displayItems.length; displayIdx++) {
      final item = displayItems[displayIdx];
      if (item is SingleBookmark && item is! BookmarkPlaceholder) {
        _displayToBookmark[displayIdx] = bookmarkIdx;
        _bookmarkToDisplay[bookmarkIdx] = displayIdx;
        bookmarkIdx++;
      } else {
        _displayToBookmark[displayIdx] = -1; // Folder 或 Placeholder，不参与排序
      }
    }
  }

  int? toBookmarkIndex(int displayIndex) {
    final idx = _displayToBookmark[displayIndex];
    return (idx != null && idx >= 0) ? idx : null;
  }

  int? toDisplayIndex(int bookmarkIndex) => _bookmarkToDisplay[bookmarkIndex];

  int get bookmarkCount => _bookmarkToDisplay.length;
}

/// Bookmark Controller/Provider
class BookmarkProvider with ChangeNotifier {
  static const String _storageKey = 'web_bookmarks';
  static const String _settingsKey = 'web_bookmark_settings';
  static const String _editModeDelayKey = 'edit_mode_delay_ms';

  List<BookmarkItem> _items = [];
  bool _useExternalBrowser = false;
  SingleBookmark? _draggingBookmark;
  int? _hoverBookmarkIndex;
  int _editModeDelayMs = 800; // 默认 800ms

  // 索引映射器
  final IndexMapper indexMapper = IndexMapper();

  List<BookmarkItem> get items => _items;
  bool get useExternalBrowser => _useExternalBrowser;
  SingleBookmark? get draggingBookmark => _draggingBookmark;
  int? get hoverBookmarkIndex => _hoverBookmarkIndex;
  int get editModeDelayMs => _editModeDelayMs;

  // 兼容旧接口
  BookmarkItem? get draggingItem => _draggingBookmark;
  int? get hoverIndex => _hoverBookmarkIndex;

  List<BookmarkItem> get displayItems {
    if (_draggingBookmark != null && _hoverBookmarkIndex != null) {
      final list = <BookmarkItem>[];
      final bookmarks = _items.whereType<SingleBookmark>().toList();

      // 构建显示列表：保持 Folder 位置，在 hover 位置插入占位符
      int bookmarkIdx = 0;
      for (final item in _items) {
        if (item is BookmarkFolder) {
          list.add(item);
        } else if (item is SingleBookmark) {
          // 跳过正在拖动的 bookmark
          if (item.id == _draggingBookmark!.id) {
            bookmarkIdx++;
            continue;
          }

          // 在 hover 位置前插入占位符
          if (bookmarkIdx == _hoverBookmarkIndex) {
            list.add(BookmarkPlaceholder());
          }

          list.add(item);
          bookmarkIdx++;
        }
      }

      // 边界：hover 在末尾
      if (_hoverBookmarkIndex == bookmarks.length - 1) {
        // 检查最后一个是否是拖动的 item
        final lastBookmark = bookmarks.last;
        if (lastBookmark.id != _draggingBookmark!.id) {
          list.add(BookmarkPlaceholder());
        }
      }

      // 同步索引映射
      indexMapper.rebuild(list);
      return list;
    }

    // 同步索引映射（无拖动状态）
    indexMapper.rebuild(_items);
    return _items;
  }

  BookmarkProvider() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _useExternalBrowser = prefs.getBool(_settingsKey) ?? false;
      _editModeDelayMs = prefs.getInt(_editModeDelayKey) ?? 800;

      final itemsJson = prefs.getString(_storageKey);
      if (itemsJson != null) {
        final List<dynamic> decoded = jsonDecode(itemsJson);
        _items = decoded.map((e) {
          final json = e as Map<String, dynamic>;
          final type = json['type'] as String? ?? 'bookmark';
          if (type == 'folder') {
            return BookmarkFolder.fromJson(json);
          } else {
            return SingleBookmark.fromJson(json);
          }
        }).toList();
      } else {
        _items = _getDefaultBookmarks();
      }
    } catch (e) {
      debugPrint('加载收藏失败: $e');
      _items = _getDefaultBookmarks();
    }
    notifyListeners();
  }

  List<BookmarkItem> _getDefaultBookmarks() {
    return [
      SingleBookmark(
        id: '1',
        name: 'Google',
        url: 'https://www.google.com',
        iconName: 'search',
        color: const Color(0xFF4285F4),
      ),
      SingleBookmark(
        id: '2',
        name: 'GitHub',
        url: 'https://github.com',
        iconName: 'code',
        color: const Color(0xFF24292E),
      ),
      BookmarkFolder(
        id: 'folder_default',
        name: 'Videos',
        children: [
          SingleBookmark(
            id: '3',
            name: 'Bilibili',
            url: 'https://www.bilibili.com',
            iconName: 'play_circle_filled',
            color: const Color(0xFF00A1D6),
          ),
          SingleBookmark(
            id: '4',
            name: 'YouTube',
            url: 'https://www.youtube.com',
            iconName: 'video_library',
            color: const Color(0xFFFF0000),
          ),
        ],
      ),
      SingleBookmark(
        id: '5',
        name: 'Flutter',
        url: 'https://flutter.dev',
        iconName: 'flutter_dash',
        color: const Color(0xFF02569B),
      ),
    ];
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final itemsJson = jsonEncode(_items.map((e) {
        if (e is BookmarkFolder) {
          return e.toJson();
        } else if (e is SingleBookmark) {
          return e.toJson();
        }
        return null;
      }).where((e) => e != null).toList());
      await prefs.setString(_storageKey, itemsJson);
    } catch (e) {
      debugPrint('保存收藏失败: $e');
    }
  }

  void startDrag(BookmarkItem item) {
    if (item is! SingleBookmark) return;
    _draggingBookmark = item as SingleBookmark;
    _hoverBookmarkIndex = null;
    notifyListeners();
  }

  void updateHoverIndex(int bookmarkIndex) {
    if (bookmarkIndex == _hoverBookmarkIndex) return; // 未变化
    _hoverBookmarkIndex = bookmarkIndex;
    notifyListeners();
  }

  void cancelDrag() {
    _draggingBookmark = null;
    _hoverBookmarkIndex = null;
    notifyListeners();
  }

  void commitReorder() {
    if (_draggingBookmark == null || _hoverBookmarkIndex == null) {
      cancelDrag();
      return;
    }

    final item = _draggingBookmark!;
    final targetIndex = _hoverBookmarkIndex!;

    // 获取所有 SingleBookmark
    final bookmarks = _items.whereType<SingleBookmark>().toList();
    final currentIndex = bookmarks.indexWhere((b) => b.id == item.id);
    if (currentIndex < 0) {
      cancelDrag();
      return;
    }

    // 从原位置移除
    _items.removeWhere((b) => b.id == item.id);

    // 在目标位置插入
    final insertIdx = targetIndex.clamp(0, _items.length);
    _items.insert(insertIdx, item);

    // 保存并通知
    _saveToStorage();

    // 清理状态
    _draggingBookmark = null;
    _hoverBookmarkIndex = null;

    notifyListeners();
  }

  // 保留旧方法以兼容
  void commitReorderWithIndexes(int oldIndex, int newIndex) {
    commitReorder();
  }

  void commitMergeToFolder(String targetId) {
    if (_draggingBookmark == null) return;

    final dragging = _draggingBookmark!;
    if (dragging.id == targetId) {
      cancelDrag();
      return;
    }

    final targetIndex = _items.indexWhere((e) => e.id == targetId);
    if (targetIndex < 0) {
      cancelDrag();
      return;
    }

    final target = _items[targetIndex];

    List<BookmarkItem> newItems = List.from(_items);
    newItems.removeWhere((e) => e.id == dragging.id);

    if (target is SingleBookmark) {
      // Create new folder from two bookmarks
      final folder = BookmarkFolder(
        id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Folder',
        children: [target, dragging as SingleBookmark],
      );
      newItems[targetIndex] = folder;
    } else if (target is BookmarkFolder) {
      // Add to existing folder
      final updatedFolder = BookmarkFolder(
        id: target.id,
        name: target.name,
        children: [...target.children, dragging as SingleBookmark],
      );
      newItems[targetIndex] = updatedFolder;
    }

    _items = newItems;
    _saveToStorage();
    cancelDrag();
  }

  Future<void> setUseExternalBrowser(bool value) async {
    _useExternalBrowser = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_settingsKey, value);
    notifyListeners();
  }

  Future<void> setEditModeDelayMs(int ms) async {
    _editModeDelayMs = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_editModeDelayKey, ms);
    notifyListeners();
  }

  Future<void> addItem(BookmarkItem item) async {
    _items.add(item);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> editItem(String id, BookmarkItem newItem) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _items[index] = newItem;
      await _saveToStorage();
      notifyListeners();
    }
  }

  Future<void> deleteItem(String id) async {
    _items.removeWhere((e) => e.id == id);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> removeFromFolder(String folderId, String bookmarkId) async {
    final index = _items.indexWhere((e) => e.id == folderId);
    if (index >= 0 && _items[index] is BookmarkFolder) {
      final folder = _items[index] as BookmarkFolder;
      final newChildren = folder.children.where((c) => c.id != bookmarkId).toList();

      if (newChildren.isEmpty) {
        _items.removeAt(index);
      } else if (newChildren.length == 1) {
        _items[index] = newChildren.first;
      } else {
        _items[index] = folder.copyWith(children: newChildren);
      }
      await _saveToStorage();
      notifyListeners();
    }
  }

  List<SingleBookmark> getSingleBookmarks() {
    return _items.whereType<SingleBookmark>().toList();
  }

  /// Reorder items from flutter_reorderable_grid_view
  void reorderItems(List<BookmarkItem> newItems) {
    _items = newItems;
    _saveToStorage();
    notifyListeners();
  }
}
