import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import '../lab_container.dart';
import '../models/bookmark_item.dart';
import '../providers/bookmark_provider.dart';

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
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _gridViewKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookmarkProvider(),
      child: _BookmarkGridView(
        scrollController: _scrollController,
        gridViewKey: _gridViewKey,
      ),
    );
  }
}

/// Bookmark Grid View using flutter_reorderable_grid_view
class _BookmarkGridView extends StatefulWidget {
  final ScrollController scrollController;
  final GlobalKey gridViewKey;

  const _BookmarkGridView({
    required this.scrollController,
    required this.gridViewKey,
  });

  @override
  State<_BookmarkGridView> createState() => _BookmarkGridViewState();
}

class _BookmarkGridViewState extends State<_BookmarkGridView> {
  bool _isEditMode = false;
  Timer? _editModeTimer;

  @override
  void dispose() {
    _editModeTimer?.cancel();
    super.dispose();
  }

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
    });
  }

  void _exitEditMode() {
    setState(() {
      _isEditMode = false;
    });
  }

  void _startEditModeTimer(Duration delay, VoidCallback onEditMode) {
    _editModeTimer?.cancel();
    _editModeTimer = Timer(delay, () {
      if (mounted) {
        onEditMode();
      }
    });
  }

  void _cancelEditModeTimer() {
    _editModeTimer?.cancel();
    _editModeTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BookmarkProvider>();
    final items = controller.items;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Web Bookmarks'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(controller.useExternalBrowser
                ? Icons.open_in_browser
                : Icons.web),
            onPressed: () => _showBrowserSettingDialog(context, controller),
            tooltip: 'Browser Setting',
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_isEditMode) {
            _exitEditMode();
          }
        },
        behavior: HitTestBehavior.translucent,
        child: items.isEmpty
            ? const Center(
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
              )
            : _buildReorderableGrid(controller),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildReorderableGrid(BookmarkProvider controller) {
    final bookmarks = controller.items.whereType<SingleBookmark>().toList();

    return ReorderableBuilder<SingleBookmark>.builder(
      key: Key(widget.gridViewKey.toString()),
      scrollController: widget.scrollController,
      longPressDelay: const Duration(milliseconds: 300),
      onDragStarted: (index) {
        HapticFeedback.lightImpact();
        _startEditModeTimer(Duration(milliseconds: controller.editModeDelayMs), () {
          final item = bookmarks[index];
          _enterEditMode();
          _showEditBookmarkDialog(context, controller, item);
        });
      },
      onUpdatedDraggedChild: (index) {
        _cancelEditModeTimer();
      },
      onDragEnd: (index) {
        _cancelEditModeTimer();
      },
      onReorder: (reorderedListFunction) {
        final reorderedItems = reorderedListFunction(bookmarks);
        controller.reorderItems(reorderedItems);
      },
      itemCount: bookmarks.length,
      childBuilder: (itemBuilder) {
        return GridView.builder(
          key: widget.gridViewKey,
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: bookmarks.length,
          itemBuilder: (context, index) {
            final item = bookmarks[index];
            return itemBuilder(
              _BookmarkCard(
                key: ValueKey(item.id),
                bookmark: item,
                isEditMode: _isEditMode,
                onTap: () => _openBookmark(context, item),
              ),
              index,
            );
          },
        );
      },
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

  void _showBrowserSettingDialog(BuildContext context, BookmarkProvider controller) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Browser', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<bool>(
                  title: const Text('In-App Browser'),
                  value: false,
                  groupValue: controller.useExternalBrowser,
                  onChanged: (value) {
                    controller.setUseExternalBrowser(value!);
                    Navigator.pop(context);
                  },
                ),
                RadioListTile<bool>(
                  title: const Text('External Browser'),
                  value: true,
                  groupValue: controller.useExternalBrowser,
                  onChanged: (value) {
                    controller.setUseExternalBrowser(value!);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Edit Mode Delay: ${controller.editModeDelayMs}ms',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: controller.editModeDelayMs.toDouble(),
                  min: 300,
                  max: 2000,
                  divisions: 17,
                  label: '${controller.editModeDelayMs}ms',
                  onChanged: (value) {
                    controller.setEditModeDelayMs(value.toInt());
                    setState(() {});
                  },
                ),
                const Text(
                  'Long press duration before entering edit mode',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    String selectedIconName = 'public';
    Color selectedColor = Colors.blue;
    bool isFetchingIcon = false;

    Future<void> fetchIconForUrl(String url, StateSetter dialogSetState) async {
      if (url.isEmpty) return;

      dialogSetState(() => isFetchingIcon = true);

      try {
        var fetchUrl = url;
        if (!fetchUrl.startsWith('http://') && !fetchUrl.startsWith('https://')) {
          fetchUrl = 'https://$fetchUrl';
        }

        final uri = Uri.tryParse(fetchUrl);
        if (uri == null || uri.host.isEmpty) {
          dialogSetState(() => isFetchingIcon = false);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid URL')),
            );
          }
          return;
        }

        // 1. 获取网页 HTML
        final response = await http.get(uri).timeout(const Duration(seconds: 8));
        dialogSetState(() => isFetchingIcon = false);

        if (response.statusCode != 200) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to fetch page')),
            );
          }
          return;
        }

        // 2. 用正则提取 icon URL
        String? iconUrl;
        final html = response.body;

        // 尝试多种 icon 选择器
        final patterns = [
          RegExp(r'''<link[^>]+rel=["']?(?:shortcut )?icon["']?[^>]+href=["']([^"']+)["']''', caseSensitive: false),
          RegExp(r'''<link[^>]+href=["']([^"']+)["'][^>]+rel=["']?(?:shortcut )?icon["']?''', caseSensitive: false),
          RegExp(r'''<meta[^>]+itemprop=["']?image["']?[^>]+content=["']([^"']+)["']''', caseSensitive: false),
        ];

        for (final pattern in patterns) {
          final match = pattern.firstMatch(html);
          if (match != null) {
            iconUrl = match.group(1);
            break;
          }
        }

        // 3. 如果没找到，使用默认的 favicon.ico
        iconUrl ??= '${uri.scheme}://${uri.host}/favicon.ico';

        // 4. 如果是相对路径，转为绝对路径
        if (iconUrl.startsWith('//')) {
          iconUrl = '${uri.scheme}:$iconUrl';
        } else if (iconUrl.startsWith('/')) {
          iconUrl = '${uri.scheme}://${uri.host}$iconUrl';
        } else if (!iconUrl.startsWith('http')) {
          iconUrl = '${uri.scheme}://${uri.host}/$iconUrl';
        }

        // 5. 验证 icon URL 是否可访问
        try {
          final iconResponse = await http.get(Uri.parse(iconUrl!)).timeout(const Duration(seconds: 5));
          if (iconResponse.statusCode == 200 && iconResponse.bodyBytes.isNotEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Found icon: $iconUrl')),
              );
            }
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Icon not accessible, please select manually')),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Icon error: $e')),
            );
          }
        }
      } catch (e) {
        dialogSetState(() => isFetchingIcon = false);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Bookmark'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
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
                  var url = urlController.text.trim();
                  if (title.isEmpty || url.isEmpty) return;

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

        final uri = Uri.tryParse(fetchUrl);
        if (uri == null || uri.host.isEmpty) {
          dialogSetState(() => isFetchingIcon = false);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid URL')),
            );
          }
          return;
        }

        // 1. 获取网页 HTML
        final response = await http.get(uri).timeout(const Duration(seconds: 8));
        dialogSetState(() => isFetchingIcon = false);

        if (response.statusCode != 200) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to fetch page')),
            );
          }
          return;
        }

        // 2. 用正则提取 icon URL
        String? iconUrl;
        final html = response.body;

        // 尝试多种 icon 选择器
        final patterns = [
          RegExp(r'''<link[^>]+rel=["']?(?:shortcut )?icon["']?[^>]+href=["']([^"']+)["']''', caseSensitive: false),
          RegExp(r'''<link[^>]+href=["']([^"']+)["'][^>]+rel=["']?(?:shortcut )?icon["']?''', caseSensitive: false),
          RegExp(r'''<meta[^>]+itemprop=["']?image["']?[^>]+content=["']([^"']+)["']''', caseSensitive: false),
        ];

        for (final pattern in patterns) {
          final match = pattern.firstMatch(html);
          if (match != null) {
            iconUrl = match.group(1);
            break;
          }
        }

        // 3. 如果没找到，使用默认的 favicon.ico
        iconUrl ??= '${uri.scheme}://${uri.host}/favicon.ico';

        // 4. 如果是相对路径，转为绝对路径
        if (iconUrl.startsWith('//')) {
          iconUrl = '${uri.scheme}:$iconUrl';
        } else if (iconUrl.startsWith('/')) {
          iconUrl = '${uri.scheme}://${uri.host}$iconUrl';
        } else if (!iconUrl.startsWith('http')) {
          iconUrl = '${uri.scheme}://${uri.host}/$iconUrl';
        }

        // 5. 验证 icon URL 是否可访问
        try {
          final iconResponse = await http.get(Uri.parse(iconUrl!)).timeout(const Duration(seconds: 5));
          if (iconResponse.statusCode == 200 && iconResponse.bodyBytes.isNotEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Found icon: $iconUrl')),
              );
            }
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Icon not accessible, please select manually')),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Icon error: $e')),
            );
          }
        }
      } catch (e) {
        dialogSetState(() => isFetchingIcon = false);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
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
                      onPressed: () {
                        Navigator.pop(context);
                        _showDeleteConfirmation(context, controller, item.id);
                      },
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

  void _showDeleteConfirmation(BuildContext context, BookmarkProvider controller, String itemId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个书签吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              controller.deleteItem(itemId);
              Navigator.pop(context);
              _exitEditMode();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已删除')),
              );
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
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

/// Bookmark Card Widget
class _BookmarkCard extends StatelessWidget {
  final SingleBookmark bookmark;
  final bool isEditMode;
  final VoidCallback? onTap;

  const _BookmarkCard({
    super.key,
    required this.bookmark,
    required this.isEditMode,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _EditModeWrapper(
      isActive: isEditMode,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 4,
                offset: const Offset(0, 2),
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
        ),
      ),
    );
  }
}

/// Edit Mode Wrapper - adds shake animation
class _EditModeWrapper extends StatefulWidget {
  final Widget child;
  final bool isActive;

  const _EditModeWrapper({
    required this.child,
    required this.isActive,
  });

  @override
  State<_EditModeWrapper> createState() => _EditModeWrapperState();
}

class _EditModeWrapperState extends State<_EditModeWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void didUpdateWidget(_EditModeWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: 0.02 * (2 * _controller.value - 1),
          child: widget.child,
        );
      },
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
