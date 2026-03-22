import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../lab_container.dart';

/// Web Bookmark Demo
class WebBookmarkDemo extends DemoPage {
  @override
  String get title => 'Web Bookmarks';

  @override
  String get description => 'Bookmark and manage websites';

  @override
  Widget buildPage(BuildContext context) {
    return const _WebBookmarkPage();
  }
}

/// Icon name to IconData constant mapping
class BookmarkIcons {
  static const Map<String, IconData> _iconMap = {
    'public': Icons.public,
    'search': Icons.search,
    'code': Icons.code,
    'play_circle_filled': Icons.play_circle_filled,
    'flutter_dash': Icons.flutter_dash,
    'edit': Icons.edit,
    'video_library': Icons.video_library,
    'shopping_bag': Icons.shopping_bag,
    'music_video': Icons.music_video,
    'new_releases': Icons.new_releases,
    'article': Icons.article,
    'school': Icons.school,
    'business': Icons.business,
    'gamepad': Icons.gamepad,
    'alternate_email': Icons.alternate_email,
  };

  static IconData getIcon(String name) {
    return _iconMap[name] ?? Icons.public;
  }

  static String getName(IconData icon) {
    for (final entry in _iconMap.entries) {
      if (entry.value == icon) {
        return entry.key;
      }
    }
    return 'public';
  }

  static List<String> get availableNames => _iconMap.keys.toList();
}

/// Bookmark Item Model
class BookmarkItem {
  final String id;
  final String name;
  final String url;
  final String iconName;
  final Color color;

  IconData get icon => BookmarkIcons.getIcon(iconName);

  BookmarkItem({
    required this.id,
    required this.name,
    required this.url,
    required this.iconName,
    required this.color,
  });

  BookmarkItem.withIcon({
    required this.id,
    required this.name,
    required this.url,
    required IconData icon,
    required this.color,
  }) : iconName = BookmarkIcons.getName(icon);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'iconName': iconName,
      'colorValue': color.value,
    };
  }

  static BookmarkItem fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      iconName: json['iconName'] as String? ?? 'public',
      color: Color(json['colorValue'] as int),
    );
  }

  BookmarkItem copyWith({
    String? id,
    String? name,
    String? url,
    String? iconName,
    Color? color,
  }) {
    return BookmarkItem(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      iconName: iconName ?? this.iconName,
      color: color ?? this.color,
    );
  }
}

/// Bookmark Controller
class BookmarkController extends ChangeNotifier {
  static const String _storageKey = 'web_bookmarks';
  static const String _settingsKey = 'web_bookmark_settings';

  List<BookmarkItem> _items = [];
  bool _useExternalBrowser = false;
  BookmarkItem? _draggingItem;
  int? _hoverIndex;

  List<BookmarkItem> get items => _items;
  bool get useExternalBrowser => _useExternalBrowser;
  BookmarkItem? get draggingItem => _draggingItem;
  int? get hoverIndex => _hoverIndex;

  List<BookmarkItem> get displayItems {
    if (_draggingItem != null && _hoverIndex != null) {
      final list = List<BookmarkItem>.from(_items);
      final clamped = _hoverIndex!.clamp(0, list.length);
      list.insert(clamped, _draggingItem!);
      return list;
    }
    return _items;
  }

  BookmarkController() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _useExternalBrowser = prefs.getBool(_settingsKey) ?? false;

    final itemsJson = prefs.getString(_storageKey);
    if (itemsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(itemsJson);
        _items = decoded.map((e) => BookmarkItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        _items = _getDefaultBookmarks();
      }
    } else {
      _items = _getDefaultBookmarks();
    }
    notifyListeners();
  }

  List<BookmarkItem> _getDefaultBookmarks() {
    return [
      BookmarkItem(
        id: '1',
        name: 'Google',
        url: 'https://www.google.com',
        iconName: 'search',
        color: const Color(0xFF4285F4),
      ),
      BookmarkItem(
        id: '2',
        name: 'GitHub',
        url: 'https://github.com',
        iconName: 'code',
        color: const Color(0xFF24292E),
      ),
      BookmarkItem(
        id: '3',
        name: 'Bilibili',
        url: 'https://www.bilibili.com',
        iconName: 'play_circle_filled',
        color: const Color(0xFF00A1D6),
      ),
      BookmarkItem(
        id: '4',
        name: 'Flutter',
        url: 'https://flutter.dev',
        iconName: 'flutter_dash',
        color: const Color(0xFF02569B),
      ),
      BookmarkItem(
        id: '5',
        name: 'YouTube',
        url: 'https://www.youtube.com',
        iconName: 'video_library',
        color: const Color(0xFFFF0000),
      ),
      BookmarkItem(
        id: '6',
        name: 'Twitter',
        url: 'https://twitter.com',
        iconName: 'alternate_email',
        color: const Color(0xFF1DA1F2),
      ),
    ];
  }

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final itemsJson = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, itemsJson);
  }

  void startDrag(BookmarkItem item) {
    _draggingItem = item;
    _hoverIndex = null;
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void updateHoverIndex(int index) {
    _hoverIndex = index;
    notifyListeners();
  }

  void cancelDrag() {
    _draggingItem = null;
    _hoverIndex = null;
    notifyListeners();
  }

  void commitReorder(int oldIndex, int newIndex) {
    if (_draggingItem == null || _hoverIndex == null) {
      cancelDrag();
      return;
    }

    final item = _draggingItem!;
    final clampedIndex = _hoverIndex!.clamp(0, _items.length);

    _items.removeWhere((e) => e.id == item.id);
    _items.insert(clampedIndex, item);

    _draggingItem = null;
    _hoverIndex = null;

    _saveToStorage();
    notifyListeners();
  }

  Future<void> setUseExternalBrowser(bool value) async {
    _useExternalBrowser = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_settingsKey, value);
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
      create: (_) => BookmarkController(),
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
          Consumer<BookmarkController>(
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
      body: Consumer<BookmarkController>(
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
              childAspectRatio: 0.9,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final originalIndex = controller.items.indexWhere((e) => e.id == item.id);

              return _buildBookmarkCard(
                context,
                controller,
                item,
                index,
                originalIndex,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBookmarkDialog(context),
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBookmarkCard(
    BuildContext context,
    BookmarkController controller,
    BookmarkItem item,
    int displayIndex,
    int originalIndex,
  ) {
    final isDragging = controller.draggingItem?.id == item.id;
    final isHover = controller.hoverIndex == displayIndex;

    return LongPressDraggable<BookmarkItem>(
      data: item,
      delay: const Duration(milliseconds: 200),
      onDragStarted: () {
        controller.startDrag(item);
      },
      onDraggableCanceled: (_, __) {
        controller.cancelDrag();
      },
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: Transform.scale(
            scale: 1.1,
            child: SizedBox(
              width: 80,
              height: 90,
              child: _BookmarkCard(item: item, isDragging: true),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _BookmarkCard(item: item),
      ),
      child: DragTarget<BookmarkItem>(
        onWillAcceptWithDetails: (details) {
          if (details.data.id == item.id) return false;
          controller.updateHoverIndex(displayIndex);
          return true;
        },
        onAcceptWithDetails: (details) {
          final draggedIndex = controller.items.indexWhere((e) => e.id == details.data.id);
          if (draggedIndex >= 0) {
            controller.commitReorder(draggedIndex, displayIndex);
          }
        },
        onLeave: (_) {
          controller.updateHoverIndex(-1);
        },
        builder: (context, candidateData, rejectedData) {
          return GestureDetector(
            onTap: () => _openBookmark(context, item),
            onLongPress: () => _showBookmarkOptions(context, item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: isHover
                    ? Border.all(color: const Color(0xFF007AFF), width: 2)
                    : null,
              ),
              child: _BookmarkCard(item: item),
            ),
          );
        },
      ),
    );
  }

  void _openBookmark(BuildContext context, BookmarkItem item) async {
    final controller = Provider.of<BookmarkController>(context, listen: false);

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

  void _showBookmarkOptions(BuildContext context, BookmarkItem item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                _showEditBookmarkDialog(context, item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, BookmarkItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bookmark'),
        content: Text('Delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<BookmarkController>(context, listen: false).deleteItem(item.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBrowserSettingDialog(BuildContext context, BookmarkController controller) {
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

  void _showAddBookmarkDialog(BuildContext context) {
    final controller = Provider.of<BookmarkController>(context, listen: false);
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    String selectedIconName = 'public';
    Color selectedColor = Colors.blue;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Bookmark'),
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
                const SizedBox(height: 16),
                const Text('Select Icon:', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableIconNames.map((iconName) {
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
                final name = nameController.text.trim();
                var url = urlController.text.trim();
                if (name.isEmpty || url.isEmpty) return;

                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }

                controller.addItem(BookmarkItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  url: url,
                  iconName: selectedIconName,
                  color: selectedColor,
                ));
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditBookmarkDialog(BuildContext context, BookmarkItem item) {
    final controller = Provider.of<BookmarkController>(context, listen: false);
    final nameController = TextEditingController(text: item.name);
    final urlController = TextEditingController(text: item.url);
    String selectedIconName = item.iconName;
    Color selectedColor = item.color;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                const SizedBox(height: 16),
                const Text('Select Icon:', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableIconNames.map((iconName) {
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
        ),
      ),
    );
  }

  static const List<String> _availableIconNames = [
    'public',
    'search',
    'code',
    'play_circle_filled',
    'flutter_dash',
    'edit',
    'video_library',
    'shopping_bag',
    'music_video',
    'new_releases',
    'article',
    'school',
    'business',
    'gamepad',
  ];

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
  final BookmarkItem item;
  final bool isDragging;

  const _BookmarkCard({required this.item, this.isDragging = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDragging
                ? item.color.withAlpha(102)
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
              color: item.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: item.color.withAlpha(77),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(item.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              item.name,
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
}

/// WebView Page
class _WebViewPage extends StatefulWidget {
  final BookmarkItem bookmark;

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
