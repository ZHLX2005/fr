import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import '../models/home_item.dart';
import '../models/home_controller.dart';
import '../widgets/home_widgets.dart';

/// 桌面式拖拽排序Demo
class DragReorderDemo extends DemoPage {
  @override
  String get title => '桌面拖拽';

  @override
  String get description => '手机桌面风格拖拽排序';

  @override
  Widget buildPage(BuildContext context) {
    return const _DragReorderPage();
  }
}

class _DragReorderPage extends StatefulWidget {
  const _DragReorderPage();

  @override
  State<_DragReorderPage> createState() => _DragReorderPageState();
}

class _DragReorderPageState extends State<_DragReorderPage> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeController(),
      child: const _HomeGridView(),
    );
  }
}

class _HomeGridView extends StatelessWidget {
  const _HomeGridView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('桌面拖拽'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Consumer<HomeController>(
            builder: (context, controller, _) {
              return IconButton(
                icon: const Icon(Icons.undo),
                onPressed: controller.canUndo ? controller.undo : null,
                tooltip: '撤销',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context),
            tooltip: '添加',
          ),
        ],
      ),
      body: Consumer<HomeController>(
        builder: (context, controller, _) {
          final items = controller.visibleItems;

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

              // 占位符
              if (item is PlaceholderItem) {
                return const PlaceholderTile();
              }

              // 应用/文件夹 - 可拖拽
              return _buildDraggableTile(context, controller, item, index);
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

  Widget _buildDraggableTile(
    BuildContext context,
    HomeController controller,
    HomeItem item,
    int index,
  ) {
    return LongPressDraggable<HomeItem>(
      data: item,
      delay: const Duration(milliseconds: 200),
      onDragStarted: () {
        HapticFeedback.lightImpact();
        controller.startDrag(item.id);
      },
      onDragEnd: (_) {
        // 如果没有被 accept，最终会走 cancel
      },
      onDraggableCanceled: (_, __) {
        controller.cancelDrag();
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
              child: HomeTile(
                item: item,
                isDraggingFeedback: true,
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.0,
        child: HomeTile(item: item),
      ),
      child: _buildTileWithTarget(context, controller, item),
    );
  }

  Widget _buildTileWithTarget(
    BuildContext context,
    HomeController controller,
    HomeItem item,
  ) {
    // 文件夹点击打开
    VoidCallback? onTap;
    if (item is FolderItem) {
      onTap = () => FolderSheet.show(context, item as FolderItem);
    }

    // 应用/文件夹拖到其他图标上触发合并
    return ItemMergeTarget(
      controller: controller,
      targetItem: item,
      child: DragTarget<HomeItem>(
        onWillAcceptWithDetails: (details) {
          controller.updateHoverIndex(_findItemIndex(controller, item));
          return true;
        },
        onAcceptWithDetails: (_) {
          controller.commitReorder();
        },
        builder: (context, candidateData, rejectedData) {
          return HomeTile(
            item: item,
            onTap: onTap,
          );
        },
      ),
    );
  }

  int _findItemIndex(HomeController controller, HomeItem item) {
    return controller.visibleItems.indexWhere((e) => e.id == item.id);
  }

  void _showAddDialog(BuildContext context) {
    final controller = context.read<HomeController>();

    // 选择类型：应用或文件夹
    bool isFolder = false;

    final titleController = TextEditingController();
    IconData selectedIcon = Icons.apps;
    Color selectedColor = Colors.blue;

    // 选择要放入文件夹的应用（创建文件夹时）
    final Set<String> selectedApps = {};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final availableApps = controller.items.whereType<AppItem>().toList();

          return AlertDialog(
            title: Text(isFolder ? '创建文件夹' : '添加应用'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 切换类型
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('应用'),
                        selected: !isFolder,
                        onSelected: (selected) {
                          setState(() {
                            isFolder = false;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('文件夹'),
                        selected: isFolder,
                        onSelected: (selected) {
                          setState(() {
                            isFolder = true;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: isFolder ? '文件夹名称' : '应用名称',
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),

                  if (!isFolder) ...[
                    const SizedBox(height: 16),
                    const Text('选择图标:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _icons.map((icon) {
                        final isSelected = selectedIcon == icon;
                        return GestureDetector(
                          onTap: () => setState(() => selectedIcon = icon),
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
                    const Text('选择颜色:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _colors.map((color) {
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
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  if (isFolder && availableApps.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('选择应用放入文件夹:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableApps.map((app) {
                        final isSelected = selectedApps.contains(app.id);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selectedApps.remove(app.id);
                              } else {
                                selectedApps.add(app.id);
                              }
                            });
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? app.color.withAlpha(51)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? app.color : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Icon(app.icon,
                                    color: isSelected ? app.color : Colors.grey[600],
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
                                      child: const Icon(Icons.check,
                                          color: Colors.white, size: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedApps.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '请至少选择2个应用',
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
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;

                  if (isFolder) {
                    // 创建文件夹
                    if (selectedApps.length < 2) return;

                    final folderApps = availableApps
                        .where((app) => selectedApps.contains(app.id))
                        .toList();

                    controller.addFolder(FolderItem(
                      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
                      title: title,
                      children: folderApps,
                    ));

                    // 从桌面移除已放入文件夹的应用
                    for (final app in folderApps) {
                      controller.items.removeWhere((e) => e.id == app.id);
                    }
                  } else {
                    // 创建应用
                    controller.addItem(AppItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: title,
                      icon: selectedIcon,
                      color: selectedColor,
                    ));
                  }
                  Navigator.pop(context);
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  static const List<IconData> _icons = [
    Icons.chat,
    Icons.message,
    Icons.shopping_bag,
    Icons.music_video,
    Icons.local_mall,
    Icons.fastfood,
    Icons.payment,
    Icons.account_balance,
    Icons.favorite,
    Icons.photo_camera,
    Icons.music_note,
    Icons.videogame_asset,
    Icons.movie,
    Icons.book,
    Icons.school,
    Icons.fitness_center,
  ];

  static const List<Color> _colors = [
    Color(0xFF07C160),
    Color(0xFF12B7F5),
    Color(0xFFFF6A00),
    Color(0xFFE4393C),
    Color(0xFF1677FF),
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.amber,
    Colors.indigo,
  ];
}

void registerDragReorderDemo() {
  demoRegistry.register(DragReorderDemo());
}
