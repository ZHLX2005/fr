import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
        onPressed: () => _showAddOptions(context),
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildReorderableGrid(BookmarkProvider controller) {
    final allItems = controller.items;

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
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        if (item is BookmarkFolder) {
          return _FolderCard(
            key: ValueKey(item.id),
            folder: item,
            onTap: () => _openFolder(context, item),
          );
        }
        // SingleBookmark
        final bookmark = item as SingleBookmark;
        return LongPressDraggable<SingleBookmark>(
          data: bookmark,
          delay: Duration(milliseconds: controller.editModeDelayMs),
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 80,
              height: 80,
              child: _BookmarkCard(
                bookmark: bookmark,
                isEditMode: false,
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _BookmarkCard(
              bookmark: bookmark,
              isEditMode: _isEditMode,
            ),
          ),
          onDragStarted: () {
            HapticFeedback.lightImpact();
            controller.startDrag(bookmark);
          },
          onDragEnd: (_) => controller.cancelDrag(),
          child: DragTarget<SingleBookmark>(
            onWillAcceptWithDetails: (details) => details.data.id != bookmark.id,
            onAcceptWithDetails: (details) {
              controller.commitMergeToFolder(bookmark.id);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovering = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: isHovering
                      ? Border.all(color: Colors.blue, width: 2)
                      : null,
                ),
                child: _BookmarkCard(
                  key: ValueKey(bookmark.id),
                  bookmark: bookmark,
                  isEditMode: _isEditMode,
                  onTap: () => _openBookmark(context, bookmark),
                  onLongPress: () {
                    _enterEditMode();
                    _showEditBookmarkDialog(context, controller, bookmark);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openFolder(BuildContext context, BookmarkFolder folder) {
    final controller = context.read<BookmarkProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FolderDetailPage(
          folder: folder,
          controller: controller,
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

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bookmark_add),
              title: const Text('添加书签'),
              onTap: () {
                Navigator.pop(context);
                _showAddDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('创建文件夹'),
              onTap: () {
                Navigator.pop(context);
                _showCreateFolderDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = Provider.of<BookmarkProvider>(context, listen: false);
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建文件夹'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              controller.addItem(BookmarkFolder(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                children: [],
              ));
              Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
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
    String? fetchedIconUrl;
    bool saveIconLocally = true;

    Future<void> fetchIconForUrl(String url, StateSetter dialogSetState) async {
      if (url.isEmpty) return;

      dialogSetState(() {
        isFetchingIcon = true;
        fetchedIconUrl = null;
      });

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

        if (response.statusCode != 200) {
          dialogSetState(() => isFetchingIcon = false);
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

        // 5. 验证并下载 icon
        try {
          final iconResponse = await http.get(Uri.parse(iconUrl!)).timeout(const Duration(seconds: 5));
          if (iconResponse.statusCode == 200 && iconResponse.bodyBytes.isNotEmpty) {
            dialogSetState(() {
              isFetchingIcon = false;
              fetchedIconUrl = iconUrl;
            });
          } else {
            dialogSetState(() => isFetchingIcon = false);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Icon not accessible')),
              );
            }
          }
        } catch (e) {
          dialogSetState(() => isFetchingIcon = false);
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
                  // Icon 预览区域
                  if (fetchedIconUrl != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: selectedColor.withAlpha(51),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Image.network(
                            fetchedIconUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              BookmarkIcons.getIcon(selectedIconName),
                              color: selectedColor,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fetchedIconUrl!,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Text('Save Icon:', style: TextStyle(fontSize: 12)),
                                  Switch(
                                    value: saveIconLocally,
                                    onChanged: (v) => setState(() => saveIconLocally = v),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Select Icon:', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: BookmarkIcons.availableNames.map((iconName) {
                      final isSelected = selectedIconName == iconName && fetchedIconUrl == null;
                      final icon = BookmarkIcons.getIcon(iconName);
                      return GestureDetector(
                        onTap: () => setState(() {
                          selectedIconName = iconName;
                          fetchedIconUrl = null;
                        }),
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
                onPressed: () async {
                  final title = titleController.text.trim();
                  var url = urlController.text.trim();
                  if (title.isEmpty || url.isEmpty) return;

                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }

                  String? iconUrlToSave;
                  // 如果用户选择保存图标到本地
                  if (saveIconLocally && fetchedIconUrl != null) {
                    try {
                      final iconResponse = await http.get(Uri.parse(fetchedIconUrl!)).timeout(const Duration(seconds: 5));
                      if (iconResponse.statusCode == 200) {
                        // 保存到本地文件
                        final directory = await _getIconDirectory();
                        final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
                        final file = File('${directory.path}/$fileName');
                        await file.writeAsBytes(iconResponse.bodyBytes);
                        iconUrlToSave = file.path;
                      }
                    } catch (e) {
                      // 下载失败，使用URL
                      iconUrlToSave = fetchedIconUrl;
                    }
                  }

                  controller.addItem(SingleBookmark(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: title,
                    url: url,
                    iconName: selectedIconName,
                    color: selectedColor,
                    iconType: iconUrlToSave != null
                        ? (saveIconLocally ? BookmarkIconType.local : BookmarkIconType.network)
                        : BookmarkIconType.icon,
                    iconUrl: iconUrlToSave,
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

  Future<Directory> _getIconDirectory() async {
    final directory = Directory('${(await getApplicationDocumentsDirectory()).path}/bookmark_icons');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Download image from URL and save to local directory
  Future<String?> _downloadImageToLocal(String imageUrl) async {
    try {
      var url = imageUrl.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        return null;
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      final directory = await _getIconDirectory();
      final extension = _getImageExtension(url) ?? 'png';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// Get image extension from URL
  String? _getImageExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'jpg';
    if (path.endsWith('.gif')) return 'gif';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.bmp')) return 'bmp';
    return 'png';
  }

  void _showEditBookmarkDialog(BuildContext context, BookmarkProvider controller, SingleBookmark item) {
    final nameController = TextEditingController(text: item.name);
    final urlController = TextEditingController(text: item.url);
    String selectedIconName = item.iconName;
    Color selectedColor = item.color;
    BookmarkIconType selectedIconType = item.iconType;
    String? iconUrl = item.iconUrl;
    final iconUrlController = TextEditingController(text: item.iconUrl ?? '');
    bool isFetchingIcon = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Bookmark'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 16),

                  // Icon 类型选择
                  const Text('Icon Source', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _IconTypeSelector(
                    selectedType: selectedIconType,
                    onTypeChanged: (type) => setState(() => selectedIconType = type),
                  ),

                  const SizedBox(height: 16),

                  // 根据类型显示不同输入
                  _buildIconInputSection(
                    iconType: selectedIconType,
                    iconUrlController: iconUrlController,
                    selectedIconName: selectedIconName,
                    selectedColor: selectedColor,
                    isFetchingIcon: isFetchingIcon,
                    iconUrl: iconUrl,
                    onIconUrlChanged: (url) => setState(() => iconUrl = url),
                    onIconNameChanged: (name) => setState(() => selectedIconName = name),
                    onFetchStart: () => setState(() => isFetchingIcon = true),
                    onFetchEnd: (url) => setState(() {
                      isFetchingIcon = false;
                      if (url != null) {
                        iconUrl = url;
                        iconUrlController.text = url;
                      }
                    }),
                    onAutoFetch: () => _fetchIconFromUrl(urlController.text, (result) {
                      if (result != null) {
                        setState(() {
                          isFetchingIcon = false;
                          iconUrl = result;
                          iconUrlController.text = result;
                        });
                      } else {
                        setState(() => isFetchingIcon = false);
                      }
                    }),
                  ),

                  // 预览
                  if (selectedIconType != BookmarkIconType.icon && iconUrl != null && iconUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildIconPreview(iconUrl!, selectedIconType, selectedIconName, selectedColor),
                  ],

                  const SizedBox(height: 16),

                  // Material Icon 选择
                  if (selectedIconType == BookmarkIconType.icon) ...[
                    const Text('Select Icon', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: BookmarkIcons.availableNames.map((iconName) {
                        final isSelected = selectedIconName == iconName;
                        final icon = BookmarkIcons.getIcon(iconName);
                        return GestureDetector(
                          onTap: () => setState(() {
                            selectedIconName = iconName;
                          }),
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
                  ],

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
                onPressed: () async {
                  final name = nameController.text.trim();
                  var url = urlController.text.trim();
                  if (name.isEmpty || url.isEmpty) return;

                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }

                  String? finalIconUrl;
                  if (selectedIconType == BookmarkIconType.network || selectedIconType == BookmarkIconType.local) {
                    finalIconUrl = iconUrlController.text.trim();
                    if (finalIconUrl.isEmpty) finalIconUrl = null;
                  }

                  controller.editItem(
                    item.id,
                    item.copyWith(
                      name: name,
                      url: url,
                      iconName: selectedIconName,
                      color: selectedColor,
                      iconType: selectedIconType,
                      iconUrl: finalIconUrl,
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

  Widget _buildIconInputSection({
    required BookmarkIconType iconType,
    required TextEditingController iconUrlController,
    required String selectedIconName,
    required Color selectedColor,
    required bool isFetchingIcon,
    required String? iconUrl,
    required Function(String) onIconUrlChanged,
    required Function(String) onIconNameChanged,
    required VoidCallback onFetchStart,
    required Function(String?) onFetchEnd,
    required VoidCallback onAutoFetch,
  }) {
    switch (iconType) {
      case BookmarkIconType.network:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: iconUrlController,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                hintText: 'https://example.com/icon.png',
                border: OutlineInputBorder(),
              ),
              onChanged: onIconUrlChanged,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isFetchingIcon ? null : onAutoFetch,
                icon: isFetchingIcon
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download),
                label: const Text('Auto Fetch from Page URL'),
              ),
            ),
          ],
        );
      case BookmarkIconType.local:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: iconUrlController,
              decoration: const InputDecoration(
                labelText: 'Local File Path',
                hintText: '/path/to/icon.png',
                border: OutlineInputBorder(),
              ),
              onChanged: onIconUrlChanged,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isFetchingIcon
                    ? null
                    : () async {
                        final url = iconUrlController.text.trim();
                        if (url.isEmpty) return;
                        onFetchStart();
                        try {
                          final localPath = await _downloadImageToLocal(url);
                          onFetchEnd(localPath);
                        } catch (e) {
                          onFetchEnd(null);
                        }
                      },
                icon: isFetchingIcon
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: const Text('Download & Save'),
              ),
            ),
          ],
        );
      case BookmarkIconType.icon:
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildIconPreview(String iconUrl, BookmarkIconType type, String iconName, Color color) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color.withAlpha(51),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildBookmarkIconWidget(SingleBookmark(
            id: '',
            name: '',
            url: '',
            iconName: iconName,
            color: color,
            iconType: type,
            iconUrl: iconUrl,
          )),
        ),
      ),
    );
  }

  Future<void> _fetchIconFromUrl(String url, Function(String?) onResult) async {
    if (url.isEmpty) {
      onResult(null);
      return;
    }

    try {
      var fetchUrl = url;
      if (!fetchUrl.startsWith('http://') && !fetchUrl.startsWith('https://')) {
        fetchUrl = 'https://$fetchUrl';
      }

      final uri = Uri.tryParse(fetchUrl);
      if (uri == null || uri.host.isEmpty) {
        onResult(null);
        return;
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        onResult(null);
        return;
      }

      final html = response.body;
      final patterns = [
        RegExp(r'''<link[^>]+rel=["']?(?:shortcut )?icon["']?[^>]+href=["']([^"']+)["']''', caseSensitive: false),
        RegExp(r'''<link[^>]+href=["']([^"']+)["'][^>]+rel=["']?(?:shortcut )?icon["']?''', caseSensitive: false),
        RegExp(r'''<meta[^>]+itemprop=["']?image["']?[^>]+content=["']([^"']+)["']''', caseSensitive: false),
      ];

      String? iconUrl;
      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          iconUrl = match.group(1);
          break;
        }
      }

      iconUrl ??= '${uri.scheme}://${uri.host}/favicon.ico';

      if (iconUrl.startsWith('//')) {
        iconUrl = '${uri.scheme}:$iconUrl';
      } else if (iconUrl.startsWith('/')) {
        iconUrl = '${uri.scheme}://${uri.host}$iconUrl';
      } else if (!iconUrl.startsWith('http')) {
        iconUrl = '${uri.scheme}://${uri.host}/$iconUrl';
      }

      onResult(iconUrl);
    } catch (e) {
      onResult(null);
    }
  }

  Widget _buildPreviewIcon(String iconUrl, BookmarkIconType type, String selectedIconName, Color selectedColor) {
    if (type == BookmarkIconType.local) {
      return Image.file(
        File(iconUrl),
        width: 64,
        height: 64,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          BookmarkIcons.getIcon(selectedIconName),
          color: selectedColor,
          size: 32,
        ),
      );
    }
    return Image.network(
      iconUrl,
      width: 64,
      height: 64,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        BookmarkIcons.getIcon(selectedIconName),
        color: selectedColor,
        size: 32,
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

  /// Icon type selector with three equal options
  Widget _IconTypeSelector({
    required BookmarkIconType selectedType,
    required Function(BookmarkIconType) onTypeChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: _IconTypeOption(
            icon: Icons.public,
            label: 'Icon',
            isSelected: selectedType == BookmarkIconType.icon,
            onTap: () => onTypeChanged(BookmarkIconType.icon),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _IconTypeOption(
            icon: Icons.link,
            label: 'URL',
            isSelected: selectedType == BookmarkIconType.network,
            onTap: () => onTypeChanged(BookmarkIconType.network),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _IconTypeOption(
            icon: Icons.folder_open,
            label: 'Local',
            isSelected: selectedType == BookmarkIconType.local,
            onTap: () => onTypeChanged(BookmarkIconType.local),
          ),
        ),
      ],
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

/// Icon type option button
class _IconTypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _IconTypeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF007AFF).withAlpha(26) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF007AFF) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF007AFF) : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? const Color(0xFF007AFF) : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Folder Card Widget
class _FolderCard extends StatelessWidget {
  final BookmarkFolder folder;
  final VoidCallback? onTap;

  const _FolderCard({
    super.key,
    required this.folder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<SingleBookmark>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final controller = Provider.of<BookmarkProvider>(context, listen: false);
        // 直接添加到文件夹
        final updatedFolder = folder.copyWith(
          children: [...folder.children, details.data],
        );
        controller.editItem(folder.id, updatedFolder);
        // 从主列表移除
        controller.deleteItem(details.data.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isHovering
                  ? Border.all(color: Colors.amber, width: 2.5)
                  : Border.all(color: Colors.amber.withAlpha(77), width: 1),
              boxShadow: [
                BoxShadow(
                  color: isHovering
                      ? Colors.amber.withAlpha(51)
                      : Colors.black.withAlpha(20),
                  blurRadius: isHovering ? 12 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isHovering ? Colors.amber : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isHovering ? Icons.folder_open : Icons.folder,
                    color: isHovering ? Colors.white : Colors.amber.shade700,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    folder.name,
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
                const SizedBox(height: 2),
                Text(
                  '${folder.children.length}项',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (isHovering)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '松开放入',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Folder Detail Page
class _FolderDetailPage extends StatelessWidget {
  final BookmarkFolder folder;
  final BookmarkProvider controller;

  const _FolderDetailPage({
    required this.folder,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // 从provider获取最新的folder数据
    final currentFolder = controller.items
        .whereType<BookmarkFolder>()
        .firstWhere((f) => f.id == folder.id, orElse: () => folder);
    final children = currentFolder.children;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(currentFolder.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: children.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('文件夹为空', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('拖拽书签到此处', style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: children.length,
              itemBuilder: (context, index) {
                final item = children[index];
                return _BookmarkCard(
                  key: ValueKey(item.id),
                  bookmark: item,
                  isEditMode: false,
                  onTap: () => _openBookmarkInFolder(context, item, controller),
                );
              },
            ),
    );
  }

  void _openBookmarkInFolder(BuildContext context, SingleBookmark item, BookmarkProvider controller) async {
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
  final SingleBookmark bookmark;
  final bool isEditMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _BookmarkCard({
    super.key,
    required this.bookmark,
    required this.isEditMode,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return _EditModeWrapper(
      isActive: isEditMode,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
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
                child: _buildBookmarkIconWidget(bookmark),
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

/// Helper function to build icon widget
Widget _buildBookmarkIconWidget(SingleBookmark bookmark) {
  switch (bookmark.iconType) {
    case BookmarkIconType.local:
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(bookmark.iconUrl!),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(bookmark.icon, color: Colors.white, size: 28),
        ),
      );
    case BookmarkIconType.network:
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          bookmark.iconUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(bookmark.icon, color: Colors.white, size: 28),
        ),
      );
    case BookmarkIconType.icon:
    default:
      return Icon(bookmark.icon, color: Colors.white, size: 28);
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
