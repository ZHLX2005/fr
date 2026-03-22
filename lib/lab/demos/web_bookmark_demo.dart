import 'dart:async';
import 'dart:io';
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
              final originalIndex = controller.items.indexWhere((e) => e.id == item.id);

              if (item is BookmarkPlaceholder) {
                return const _PlaceholderTile();
              }

              return _LongPressDraggableTile(
                key: ValueKey(item.id),
                item: item,
                index: index,
                originalIndex: originalIndex,
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

    // Local helper function for fetching icon
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

/// 长按拖拽卡片组件 - 支持长按2秒后弹出编辑框
class _LongPressDraggableTile extends StatefulWidget {
  final BookmarkItem item;
  final int index;
  final int originalIndex;

  const _LongPressDraggableTile({
    required this.item,
    required this.index,
    required this.originalIndex,
    super.key,
  });

  @override
  State<_LongPressDraggableTile> createState() => _LongPressDraggableTileState();
}

class _LongPressDraggableTileState extends State<_LongPressDraggableTile> {
  Timer? _longPressTimer;
  bool _hasDragStarted = false;
  Offset? _startPosition;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _startPosition = details.globalPosition;
    _hasDragStarted = false;

    // 启动2秒定时器
    _longPressTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_hasDragStarted) {
        // 2秒后没有拖动，弹出编辑框
        _showEditDialog();
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // 检测是否真的发生了位置变化（拖动）
    if (_startPosition != null) {
      final currentPosition = details.globalPosition;
      final distance = (currentPosition - _startPosition!).distance;
      if (distance > 10) {
        _hasDragStarted = true;
        _longPressTimer?.cancel();
      }
    }
  }

  void _onDragEnd(DraggableDetails details) {
    _longPressTimer?.cancel();
    if (!_hasDragStarted) {
      // 没有真正拖动，可能是长按触发
      // 但定时器会处理这个情况
    }
  }

  void _showEditDialog() {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);

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

    // Local helper function for fetching icon
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
                    children: _BookmarkGridView._availableColors.map((color) {
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

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);

    return LongPressDraggable<BookmarkItem>(
      data: widget.item,
      delay: const Duration(milliseconds: 200),
      onDragStarted: () {
        controller.startDrag(widget.item);
        HapticFeedback.lightImpact();
      },
      onDragUpdate: _onDragUpdate,
      onDragEnd: _onDragEnd,
      onDraggableCanceled: (_, __) {
        controller.cancelDrag();
        _longPressTimer?.cancel();
      },
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.95,
          child: Transform.scale(
            scale: 1.05,
            child: SizedBox(
              width: 80,
              height: 90,
              child: _BookmarkCard(item: widget.item, isDragging: true),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.0,
        child: _BookmarkCard(item: widget.item),
      ),
      child: _buildTileWithTarget(context, controller, widget.item, widget.index),
    );
  }

  Widget _buildTileWithTarget(
    BuildContext context,
    BookmarkProvider controller,
    BookmarkItem item,
    int displayIndex,
  ) {
    VoidCallback? onTap;
    if (item is BookmarkFolder) {
      onTap = () => _FolderSheet.show(context, item);
    } else if (item is SingleBookmark) {
      onTap = () => _openBookmark(context, item);
    }

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      behavior: HitTestBehavior.opaque,
      child: _ItemMergeTarget(
        controller: controller,
        targetItem: item,
        child: DragTarget<BookmarkItem>(
          onWillAcceptWithDetails: (details) {
            if (details.data.id == item.id) return false;
            final canMerge = item is SingleBookmark || item is BookmarkFolder;
            if (canMerge && details.data is SingleBookmark) {
              controller.updateHoverIndex(displayIndex);
            }
            return canMerge;
          },
          onAcceptWithDetails: (details) {
            controller.commitMergeToFolder(item.id);
          },
          onLeave: (_) {
            controller.updateHoverIndex(-1);
          },
          builder: (context, candidateData, rejectedData) {
            return _BookmarkCard(item: item, onTap: onTap);
          },
        ),
      ),
    );
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
}

/// Bookmark Card Widget
class _BookmarkCard extends StatelessWidget {
  final BookmarkItem item;
  final bool isDragging;
  final VoidCallback? onTap;

  const _BookmarkCard({
    required this.item,
    this.isDragging = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _buildContent(),
    );
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

/// Item Merge Target
class _ItemMergeTarget extends StatelessWidget {
  final BookmarkProvider controller;
  final BookmarkItem targetItem;
  final Widget child;

  const _ItemMergeTarget({
    required this.controller,
    required this.targetItem,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<BookmarkItem>(
      onWillAcceptWithDetails: (details) {
        if (details.data.id == targetItem.id) return false;
        final canMerge = (targetItem is SingleBookmark || targetItem is BookmarkFolder) &&
            (details.data is SingleBookmark);
        return canMerge;
      },
      onLeave: (_) {
        controller.updateHoverIndex(-1);
      },
      onAcceptWithDetails: (details) {
        controller.commitMergeToFolder(targetItem.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHover = controller.draggingItem != null &&
            controller.hoverIndex != null;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isHover ? Border.all(color: Colors.blueAccent, width: 3) : null,
          ),
          child: child,
        );
      },
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
