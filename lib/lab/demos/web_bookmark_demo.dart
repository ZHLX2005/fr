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

class _BookmarkTileState extends State<_BookmarkTile> {
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

  // 卡片尺寸
  Size? _cardSize;
  // 卡片初始位置
  Offset? _cardPosition;

  @override
  void initState() {
    super.initState();
    // 在下一帧获取卡片尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureCard();
    });
  }

  void _measureCard() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      setState(() {
        _cardSize = renderBox.size;
        _cardPosition = renderBox.localToGlobal(Offset.zero);
      });
    }
  }

  void _handleTap() {
    final item = widget.item;
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onLongPressStart: (details) => _startDrag(details),
      onLongPressMoveUpdate: (details) => _updateDrag(details),
      onLongPressEnd: (details) => _endDrag(details),
      child: _BookmarkCard(item: widget.item),
    );
  }

  // 拖拽状态
  Offset? _dragStartPosition;
  Offset? _currentDragPosition;
  bool _isDragging = false;
  OverlayEntry? _overlayEntry;
  Timer? _editTimer;

  void _startDrag(LongPressStartDetails details) {
    HapticFeedback.lightImpact();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    setState(() {
      _dragStartPosition = details.globalPosition;
      _currentDragPosition = details.globalPosition;
      _isDragging = true;
    });

    // 显示悬浮卡片
    _showOverlay(position, size);

    // 启动2秒定时器
    _editTimer = Timer(const Duration(seconds: 2), () {
      if (_isDragging && mounted) {
        _cancelDrag();
        _showEditDialog();
      }
    });
  }

  void _showOverlay(Offset position, Size size) {
    _overlayEntry?.remove();

    _overlayEntry = OverlayEntry(
      builder: (context) => _FloatingCard(
        item: widget.item,
        position: position,
        size: size,
        offset: _currentDragPosition! - _dragStartPosition!,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateDrag(LongPressMoveUpdateDetails details) {
    if (!_isDragging) return;

    setState(() {
      _currentDragPosition = details.globalPosition;
    });

    // 更新 Overlay
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }

    // 检测悬停位置
    _updateHoverIndex(details.globalPosition);
  }

  void _updateHoverIndex(Offset globalPosition) {
    // 简化处理：当拖动时通知 provider 更新显示
    // provider 会自动在 hoverIndex 位置显示占位符
    final controller = context.read<BookmarkProvider>();
    if (!_isDragging) return;

    // 通知 provider 开始拖动（即使 hoverIndex 没变也需要）
    if (controller.draggingItem == null) {
      controller.startDrag(widget.item);
    }
  }

  void _endDrag(LongPressEndDetails details) {
    _editTimer?.cancel();

    _cancelDrag();
  }

  void _cancelDrag() {
    _editTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;

    setState(() {
      _isDragging = false;
      _dragStartPosition = null;
      _currentDragPosition = null;
    });
  }
}

/// Floating Card - 显示在顶层的悬浮卡片
class _FloatingCard extends StatelessWidget {
  final BookmarkItem item;
  final Offset position;
  final Size size;
  final Offset offset;

  const _FloatingCard({
    required this.item,
    required this.position,
    required this.size,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    final left = position.dx + offset.dx;
    final top = position.dy + offset.dy;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: 1.05,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: size.width,
            height: size.height,
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
