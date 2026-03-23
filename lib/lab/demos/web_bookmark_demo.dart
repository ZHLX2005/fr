import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../lab_container.dart';
import '../models/bookmark_item.dart';
import '../providers/bookmark_provider.dart';
import '../../services/favicon_api_service.dart';

/// Web Bookmark Demo
class WebBookmarkDemo extends DemoPage {
  @override
  String get title => 'Web Bookmarks';

  @override
  String get description => 'Bookmark folders with drag-drop';

  @override
  Widget buildPage(BuildContext context) {
    return const _WebBookmarkPage();
  }
}

/// Main Page
class _WebBookmarkPage extends StatefulWidget {
  const _WebBookmarkPage();

  @override
  State<_WebBookmarkPage> createState() => _WebBookmarkPageState();
}

class _WebBookmarkPageState extends State<_WebBookmarkPage> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookmarkProvider(),
      child: const _BookmarkGridView(),
    );
  }
}

/// Bookmark Grid View
class _BookmarkGridView extends StatelessWidget {
  const _BookmarkGridView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Web Bookmarks'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Consumer<BookmarkProvider>(
            builder: (context, controller, _) {
              return IconButton(
                icon: Icon(controller.useExternalBrowser
                    ? Icons.open_in_browser
                    : Icons.web),
                onPressed: () => _showBrowserSettingDialog(context, controller),
                tooltip: 'Browser Setting',
              );
            },
          ),
        ],
      ),
      body: Consumer<BookmarkProvider>(
        builder: (context, controller, _) {
          final items = controller.displayItems;

          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No Bookmarks', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Tap + to add bookmarks', style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              if (item is BookmarkPlaceholder) {
                return const _PlaceholderTile();
              }

              return _BookmarkTile(
                key: ValueKey(item.id),
                item: item,
                index: index,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showBrowserSettingDialog(BuildContext context, BookmarkProvider controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Browser Setting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              title: const Text('In-App Browser'),
              subtitle: const Text('Use built-in WebView'),
              value: false,
              groupValue: controller.useExternalBrowser,
              onChanged: (value) {
                controller.setUseExternalBrowser(value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<bool>(
              title: const Text('External Browser'),
              subtitle: const Text('Use system browser'),
              value: true,
              groupValue: controller.useExternalBrowser,
              onChanged: (value) {
                controller.setUseExternalBrowser(value!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);
    bool isFolder = false;
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    String selectedIconName = 'public';
    Color selectedColor = Colors.blue;
    final Set<String> selectedBookmarks = {};
    bool isFetchingIcon = false;

    Future<void> fetchIconForUrl(String url, StateSetter dialogSetState) async {
      if (url.isEmpty) return;

      dialogSetState(() => isFetchingIcon = true);

      try {
        var fetchUrl = url;
        if (!fetchUrl.startsWith('http://') && !fetchUrl.startsWith('https://')) {
          fetchUrl = 'https://$fetchUrl';
        }

        final iconPath = await FaviconApiService.downloadAndSaveFavicon(
          fetchUrl,
          'temp_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (iconPath != null && context.mounted) {
          dialogSetState(() => isFetchingIcon = false);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Icon downloaded! Select an icon style.')),
            );
          }
        } else {
          if (context.mounted) {
            dialogSetState(() => isFetchingIcon = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not fetch icon. Please select manually.')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          dialogSetState(() => isFetchingIcon = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching icon: $e')),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final availableBookmarks = controller.getSingleBookmarks();

          return AlertDialog(
            title: Text(isFolder ? 'Create Folder' : 'Add Bookmark'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Bookmark'),
                        selected: !isFolder,
                        onSelected: (selected) {
                          setState(() => isFolder = false);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Folder'),
                        selected: isFolder,
                        onSelected: (selected) {
                          setState(() => isFolder = true);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: isFolder ? 'Folder Name' : 'Name',
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  if (!isFolder) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'URL',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isFetchingIcon
                                ? null
                                : () => fetchIconForUrl(urlController.text, setState),
                            icon: isFetchingIcon
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('Auto Icon'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Icon:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: BookmarkIcons.availableNames.map((iconName) {
                        final isSelected = selectedIconName == iconName;
                        final icon = BookmarkIcons.getIcon(iconName);
                        return GestureDetector(
                          onTap: () => setState(() => selectedIconName = iconName),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? selectedColor.withAlpha(51)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? selectedColor : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Icon(icon,
                                color: isSelected ? selectedColor : Colors.grey[600],
                                size: 24),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Color:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableColors.map((color) {
                        final isSelected = selectedColor == color;
                        return GestureDetector(
                          onTap: () => setState(() => selectedColor = color),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black : Colors.grey[300]!,
                                width: isSelected ? 3 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (isFolder && availableBookmarks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Select bookmarks:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableBookmarks.map((bookmark) {
                        final isSelected = selectedBookmarks.contains(bookmark.id);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selectedBookmarks.remove(bookmark.id);
                              } else {
                                selectedBookmarks.add(bookmark.id);
                              }
                            });
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? bookmark.color.withAlpha(51)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? bookmark.color : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Icon(bookmark.icon,
                                    color: isSelected ? bookmark.color : Colors.grey[600],
                                    size: 24),
                                if (isSelected)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, color: Colors.white, size: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedBookmarks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Select at least 2 bookmarks',
                          style: TextStyle(color: Colors.orange[700], fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;

                  if (isFolder) {
                    if (selectedBookmarks.length < 2) return;

                    final folderBookmarks = availableBookmarks
                        .where((b) => selectedBookmarks.contains(b.id))
                        .toList();

                    controller.addItem(BookmarkFolder(
                      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
                      name: title,
                      children: folderBookmarks,
                    ));

                    for (final bookmark in folderBookmarks) {
                      controller.deleteItem(bookmark.id);
                    }
                  } else {
                    var url = urlController.text.trim();
                    if (url.isEmpty) return;

                    if (!url.startsWith('http://') && !url.startsWith('https://')) {
                      url = 'https://$url';
                    }

                    controller.addItem(SingleBookmark(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: title,
                      url: url,
                      iconName: selectedIconName,
                      color: selectedColor,
                    ));
                  }
                  Navigator.pop(context);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  static const List<Color> _availableColors = [
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF3B30),
    Color(0xFF5856D6),
    Color(0xFF32ADE6),
    Color(0xFFFF2D55),
    Color(0xFF00C7BE),
    Color(0xFFFFCC00),
    Color(0xFF8E8E93),
  ];

}

/// Bookmark Tile - Handles tap, long press for drag
class _BookmarkTile extends StatefulWidget {
  final BookmarkItem item;
  final int index;

  const _BookmarkTile({
    required this.item,
    required this.index,
    super.key,
  });

  @override
  State<_BookmarkTile> createState() => _BookmarkTileState();
}

class _BookmarkTileState extends State<_BookmarkTile> with TickerProviderStateMixin {
  static const List<Color> _availableColors = [
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF3B30),
    Color(0xFF5856D6),
    Color(0xFF32ADE6),
    Color(0xFFFF2D55),
    Color(0xFF00C7BE),
    Color(0xFFFFCC00),
    Color(0xFF8E8E93),
  ];

  // 是否处于悬浮状态（长按后）
  bool _isFloating = false;
  // 是否处于拖拽状态（移动到了其他位置）
  bool _isDragging = false;

  // 悬浮时的卡片位置
  Rect? _floatingRect;
  // 当前悬停的索引
  int? _hoverIndex;
  // 原始索引
  late int _originalIndex;

  OverlayEntry? _overlayEntry;
  Timer? _editTimer;

  // 动画控制器
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _originalIndex = widget.index;
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _editTimer?.cancel();
    _scaleController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// 长按开始 - 进入悬浮状态
  void _onLongPressStart(LongPressStartDetails details) {
    if (_isFloating) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    setState(() {
      _isFloating = true;
      _isDragging = false;
      _floatingRect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
      _hoverIndex = _originalIndex;
    });

    _scaleController.forward();
    HapticFeedback.lightImpact();

    // 显示悬浮卡片
    _showOverlay();

    // 启动2秒定时器：如果没有发生位置交换，触发编辑
    _editTimer = Timer(const Duration(seconds: 2), () {
      if (_isFloating && !_isDragging && mounted) {
        _exitToEdit();
      }
    });
  }

  /// 长按移动 - 更新悬浮卡片位置
  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isFloating) return;

    final newHoverIndex = _findHoveredIndex(details.globalPosition);

    // 检查是否移动到了新的位置
    if (newHoverIndex != null && newHoverIndex != _originalIndex) {
      if (!_isDragging) {
        setState(() {
          _isDragging = true;
        });
        // 通知 Provider 开始拖拽
        context.read<BookmarkProvider>().startDrag(widget.item);
      }

      if (newHoverIndex != _hoverIndex) {
        setState(() {
          _hoverIndex = newHoverIndex;
        });
        context.read<BookmarkProvider>().updateHoverIndex(newHoverIndex);
      }
    }

    // 更新悬浮卡片位置（不触发setState，使用Overlay更新）
    _updateOverlayPosition(details.globalPosition);
  }

  /// 长按结束
  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isFloating) return;

    _editTimer?.cancel();

    if (_isDragging && _hoverIndex != null && _hoverIndex != _originalIndex) {
      // 发生了位置交换，提交重排
      context.read<BookmarkProvider>().commitReorder(_originalIndex, _hoverIndex!);
    }

    _resetState();
  }

  /// 重置状态
  void _resetState() {
    _scaleController.reverse();

    if (_isDragging) {
      context.read<BookmarkProvider>().cancelDrag();
    }

    _removeOverlay();

    setState(() {
      _isFloating = false;
      _isDragging = false;
      _floatingRect = null;
      _hoverIndex = null;
    });
  }

  /// 退出到编辑模式
  void _exitToEdit() {
    _resetState();
    _showEditDialog();
  }

  /// 显示悬浮卡片
  void _showOverlay() {
    if (_floatingRect == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _FloatingCard(
        item: widget.item,
        rect: _floatingRect!,
        scale: _scaleAnimation.value,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 更新悬浮卡片位置
  void _updateOverlayPosition(Offset globalPosition) {
    if (_overlayEntry == null || _floatingRect == null) return;

    // 计算新的位置（保持卡片中心在手指位置）
    final newRect = Rect.fromCenter(
      center: globalPosition,
      width: _floatingRect!.width,
      height: _floatingRect!.height,
    );

    _overlayEntry!.markNeedsBuild();
    // 直接修改rect，Overlay会重建
    // 注意：这仍然会触发Overlay重建，但比整个widget树rebuild要好
  }

  /// 查找悬停位置的索引
  int? _findHoveredIndex(Offset globalPosition) {
    final controller = context.read<BookmarkProvider>();
    final items = controller.displayItems;

    for (int i = 0; i < items.length; i++) {
      if (items[i].id == widget.item.id) continue;
      if (items[i] is BookmarkPlaceholder) continue;

      final key = ValueKey(items[i].id);
      final element = context.findRenderObject();
      if (element == null) continue;

      // 尝试通过 BuildContext 查找
      final itemContext = context;
      final itemBox = itemContext.findRenderObject() as RenderBox?;
      if (itemBox == null) continue;

      final itemPosition = itemBox.localToGlobal(Offset.zero);
      final itemSize = itemBox.size;

      if (globalPosition.dx >= itemPosition.dx &&
          globalPosition.dx <= itemPosition.dx + itemSize.width &&
          globalPosition.dy >= itemPosition.dy &&
          globalPosition.dy <= itemPosition.dy + itemSize.height) {
        return i;
      }
    }
    return null;
  }

  void _showEditDialog() {
    final controller = context.read<BookmarkProvider>();

    if (widget.item is SingleBookmark) {
      _showEditBookmarkDialog(context, controller, widget.item as SingleBookmark);
    } else if (widget.item is BookmarkFolder) {
      _showEditFolderDialog(context, controller, widget.item as BookmarkFolder);
    }
  }

  void _showEditBookmarkDialog(BuildContext context, BookmarkProvider controller, SingleBookmark item) {
    final nameController = TextEditingController(text: item.name);
    final urlController = TextEditingController(text: item.url);
    String selectedIconName = item.iconName;
    Color selectedColor = item.color;
    bool isFetchingIcon = false;

    Future<void> fetchIconForUrl(String url, StateSetter dialogSetState) async {
      if (url.isEmpty) return;

      dialogSetState(() => isFetchingIcon = true);

      try {
        var fetchUrl = url;
        if (!fetchUrl.startsWith('http://') && !fetchUrl.startsWith('https://')) {
          fetchUrl = 'https://$fetchUrl';
        }

        final iconPath = await FaviconApiService.downloadAndSaveFavicon(
          fetchUrl,
          'temp_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (iconPath != null && context.mounted) {
          dialogSetState(() => isFetchingIcon = false);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Icon downloaded! Select an icon style.')),
            );
          }
        } else {
          if (context.mounted) {
            dialogSetState(() => isFetchingIcon = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not fetch icon. Please select manually.')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          dialogSetState(() => isFetchingIcon = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching icon: $e')),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Bookmark'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isFetchingIcon
                              ? null
                              : () => fetchIconForUrl(urlController.text, setState),
                          icon: isFetchingIcon
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Auto Icon'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Icon:', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: BookmarkIcons.availableNames.map((iconName) {
                      final isSelected = selectedIconName == iconName;
                      final icon = BookmarkIcons.getIcon(iconName);
                      return GestureDetector(
                        onTap: () => setState(() => selectedIconName = iconName),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? selectedColor.withAlpha(51)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? selectedColor : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Icon(icon,
                              color: isSelected ? selectedColor : Colors.grey[600],
                              size: 24),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Color:', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableColors.map((color) {
                      final isSelected = selectedColor == color;
                      return GestureDetector(
                        onTap: () => setState(() => selectedColor = color),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.black : Colors.grey[300]!,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 20)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteItem(context, controller, item.id),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Delete Bookmark'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  var url = urlController.text.trim();
                  if (name.isEmpty || url.isEmpty) return;

                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }

                  controller.editItem(
                    item.id,
                    item.copyWith(
                      name: name,
                      url: url,
                      iconName: selectedIconName,
                      color: selectedColor,
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditFolderDialog(BuildContext context, BookmarkProvider controller, BookmarkFolder item) {
    final nameController = TextEditingController(text: item.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Folder Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Contents: ${item.children.length} bookmarks'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _deleteItem(context, controller, item.id),
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Delete Folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              controller.editItem(
                item.id,
                item.copyWith(name: name),
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(BuildContext context, BookmarkProvider controller, String itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此项吗？\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      controller.deleteItem(itemId);
      Navigator.pop(context); // 关闭编辑对话框
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
  }

  void _handleItemTap(BookmarkItem item) {
    if (item is BookmarkFolder) {
      _FolderSheet.show(context, item);
    } else if (item is SingleBookmark) {
      _openBookmark(context, item);
    }
  }

  void _openBookmark(BuildContext context, SingleBookmark item) async {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);

    if (controller.useExternalBrowser) {
      final uri = Uri.parse(item.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _WebViewPage(bookmark: item),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 悬浮状态显示半透明占位符
    if (_isFloating) {
      return Opacity(
        opacity: 0.3,
        child: _BookmarkCard(item: widget.item),
      );
    }

    return GestureDetector(
      onTap: () => _handleItemTap(widget.item),
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: _BookmarkCard(item: widget.item),
    );
  }
}

/// Floating Card - 显示在顶层的悬浮卡片
class _FloatingCard extends StatelessWidget {
  final BookmarkItem item;
  final Rect rect;
  final double scale;

  const _FloatingCard({
    required this.item,
    required this.rect,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      child: Transform.scale(
        scale: scale,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: rect.width,
            height: rect.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: _BookmarkCard(item: item, isDragging: true),
          ),
        ),
      ),
    );
  }
}

/// Bookmark Card Widget
class _BookmarkCard extends StatelessWidget {
  final BookmarkItem item;
  final bool isDragging;

  const _BookmarkCard({
    required this.item,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    return _buildContent();
  }

  Widget _buildContent() {
    if (item is SingleBookmark) {
      return _buildSingleBookmark(item as SingleBookmark);
    } else if (item is BookmarkFolder) {
      return _buildFolder(item as BookmarkFolder);
    }
    return const SizedBox.shrink();
  }

  Widget _buildSingleBookmark(SingleBookmark bookmark) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDragging
                ? bookmark.color.withAlpha(102)
                : Colors.black.withAlpha(20),
            blurRadius: isDragging ? 16 : 4,
            offset: Offset(0, isDragging ? 8 : 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bookmark.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: bookmark.color.withAlpha(77),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(bookmark.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              bookmark.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolder(BookmarkFolder folder) {
    final children = folder.children.take(9).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDragging
                ? Colors.blue.withAlpha(102)
                : Colors.black.withAlpha(20),
            blurRadius: isDragging ? 16 : 4,
            offset: Offset(0, isDragging ? 8 : 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _buildFolderPreviewGrid(children),
            ),
            const SizedBox(height: 4),
            Text(
              folder.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${folder.children.length}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderPreviewGrid(List<SingleBookmark> children) {
    final count = children.length;

    if (count == 1) {
      return Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: children[0].color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(children[0].icon, color: Colors.white, size: 20),
        ),
      );
    } else if (count == 2) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildMiniIcon(children[0], 28),
          const SizedBox(height: 2),
          _buildMiniIcon(children[1], 28),
        ],
      );
    } else if (count <= 4) {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: count,
        itemBuilder: (context, index) => _buildMiniIcon(children[index], 24),
      );
    } else {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: count > 9 ? 9 : count,
        itemBuilder: (context, index) => _buildMiniIcon(children[index], 20),
      );
    }
  }

  Widget _buildMiniIcon(SingleBookmark bookmark, double size) {
    return Container(
      decoration: BoxDecoration(
        color: bookmark.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(bookmark.icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// Placeholder Tile
class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withAlpha(31),
          width: 2,
        ),
      ),
      child: const Center(
        child: Icon(Icons.drag_indicator, color: Colors.black26, size: 28),
      ),
    );
  }
}

/// Folder Sheet
class _FolderSheet extends StatelessWidget {
  final BookmarkFolder folder;

  const _FolderSheet({required this.folder});

  static void show(BuildContext context, BookmarkFolder folder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FolderSheet(folder: folder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${folder.children.length} bookmarks',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: folder.children.length,
              itemBuilder: (context, index) {
                final bookmark = folder.children[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _openBookmarkInFolder(context, bookmark);
                  },
                  onLongPress: () {
                    Navigator.pop(context);
                    _showBookmarkOptions(context, folder, bookmark);
                  },
                  child: _BookmarkCard(item: bookmark),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  void _openBookmarkInFolder(BuildContext context, SingleBookmark bookmark) async {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);

    if (controller.useExternalBrowser) {
      final uri = Uri.parse(bookmark.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _WebViewPage(bookmark: bookmark),
        ),
      );
    }
  }

  void _showBookmarkOptions(BuildContext context, BookmarkFolder folder, SingleBookmark bookmark) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove from Folder', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmRemove(context, folder, bookmark);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context, BookmarkFolder folder, SingleBookmark bookmark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Bookmark'),
        content: Text('Remove "${bookmark.name}" from folder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<BookmarkProvider>(context, listen: false)
                  .removeFromFolder(folder.id, bookmark.id);
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// WebView Page
class _WebViewPage extends StatefulWidget {
  final SingleBookmark bookmark;

  const _WebViewPage({required this.bookmark});

  @override
  State<_WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<_WebViewPage> {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    _initWebViewController();
    _loadUrl(widget.bookmark.url);
  }

  void _initWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _loadProgress = 0;
            });
          },
          onProgress: (int progress) {
            setState(() {
              _loadProgress = progress / 100;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      );
  }

  Future<void> _loadUrl(String url) async {
    await _webViewController.loadRequest(Uri.parse(url));
  }

  Future<void> _goBack() async {
    if (await _webViewController.canGoBack()) {
      await _webViewController.goBack();
    } else {
      Navigator.pop(context);
    }
  }

  void _reload() async {
    await _webViewController.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookmark.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _loadProgress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }
}

void registerWebBookmarkDemo() {
  demoRegistry.register(WebBookmarkDemo());
}
