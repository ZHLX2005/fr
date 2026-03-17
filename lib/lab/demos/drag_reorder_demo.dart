import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 拖拽排序Demo - 类似手机App图标拖拽排序
class DragReorderDemo extends DemoPage {
  @override
  String get title => '拖拽排序';

  @override
  String get description => 'App图标风格拖拽排序';

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
  final List<_AppItem> _items = [];
  int _nextId = 1;
  int? _draggingIndex;
  int? _targetIndex;

  @override
  void initState() {
    super.initState();
    _items.addAll([
      _AppItem(id: _nextId++, title: '微信', icon: Icons.chat, color: const Color(0xFF07C160)),
      _AppItem(id: _nextId++, title: 'QQ', icon: Icons.message, color: const Color(0xFF12B7F5)),
      _AppItem(id: _nextId++, title: '淘宝', icon: Icons.shopping_bag, color: const Color(0xFFFF6A00)),
      _AppItem(id: _nextId++, title: '抖音', icon: Icons.music_video, color: const Color(0xFF000000)),
      _AppItem(id: _nextId++, title: '京东', icon: Icons.local_mall, color: const Color(0xFFE4393C)),
      _AppItem(id: _nextId++, title: '拼多多', icon: Icons.thumb_up, color: const Color(0xFFE22018)),
      _AppItem(id: _nextId++, title: '美团', icon: Icons.fastfood, color: const Color(0xFFFF6B00)),
      _AppItem(id: _nextId++, title: '支付宝', icon: Icons.payment, color: const Color(0xFF1677FF)),
      _AppItem(id: _nextId++, title: '银行', icon: Icons.account_balance, color: const Color(0xFF2196F3)),
    ]);
  }

  void _addItem() async {
    final result = await _showEditDialog(context, null);
    if (result != null) {
      setState(() {
        _items.add(_AppItem(
          id: _nextId++,
          title: result.title,
          icon: result.icon,
          color: result.color,
        ));
      });
    }
  }

  void _editItem(_AppItem item) async {
    final result = await _showEditDialog(context, item);
    if (result != null) {
      setState(() {
        item.title = result.title;
        item.icon = result.icon;
        item.color = result.color;
      });
    }
  }

  void _deleteItem(_AppItem item) {
    setState(() {
      _items.removeWhere((i) => i.id == item.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除: ${item.title}'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: '撤销',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _items.add(item);
            });
          },
        ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  void _handleDragStarted(int index) {
    setState(() {
      _draggingIndex = index;
    });
  }

  void _handleDragEnd() {
    setState(() {
      _draggingIndex = null;
      _targetIndex = null;
    });
  }

  void _handleDragOver(int index) {
    if (_draggingIndex != null && _draggingIndex != index) {
      setState(() {
        _targetIndex = index;
      });
    }
  }

  void _handleDragAccept(int oldIndex, int newIndex) {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _draggingIndex = null;
      _targetIndex = null;
    });
  }

  Future<_EditResult?> _showEditDialog(BuildContext context, _AppItem? item) async {
    final titleController = TextEditingController(text: item?.title ?? '');
    IconData selectedIcon = item?.icon ?? Icons.apps;
    Color selectedColor = item?.color ?? Colors.blue;

    return showDialog<_EditResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? '添加应用' : '编辑应用'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                const Text('选择图标:', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _icons.map((icon) {
                    final isSelected = selectedIcon == icon;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          selectedIcon = icon;
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? selectedColor.withValues(alpha: 0.2) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? selectedColor : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Icon(icon, color: isSelected ? selectedColor : Colors.grey[600], size: 24),
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
                      onTap: () {
                        setDialogState(() {
                          selectedColor = color;
                        });
                      },
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
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(context, _EditResult(title: title, icon: selectedIcon, color: selectedColor));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('拖拽排序'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addItem,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apps, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('暂无应用', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                        const SizedBox(height: 8),
                        Text('点击右上角添加', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                      ],
                    ),
                  )
                : _buildGrid(),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, size: 18, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Text(
                  '长按拖动排序 • 点击编辑 • 向左滑动删除',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildGrid() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _DraggableAppItem(
            key: ValueKey(item.id),
            item: item,
            index: index,
            isDragging: _draggingIndex == index,
            isTarget: _targetIndex == index,
            onEdit: () => _editItem(item),
            onDelete: () => _deleteItem(item),
            onDragStarted: () => _handleDragStarted(index),
            onDragEnd: _handleDragEnd,
            onDragOver: () => _handleDragOver(index),
            onDragAccept: (oldIndex) => _handleDragAccept(oldIndex, index),
          );
        },
      ),
    );
  }
}

/// 应用数据
class _AppItem {
  int id;
  String title;
  IconData icon;
  Color color;

  _AppItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
  });
}

/// 编辑结果
class _EditResult {
  String title;
  IconData icon;
  Color color;

  _EditResult({required this.title, required this.icon, required this.color});
}

/// 可拖拽的应用图标组件
class _DraggableAppItem extends StatefulWidget {
  final _AppItem item;
  final int index;
  final bool isDragging;
  final bool isTarget;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;
  final VoidCallback onDragOver;
  final void Function(int oldIndex) onDragAccept;

  const _DraggableAppItem({
    super.key,
    required this.item,
    required this.index,
    required this.isDragging,
    required this.isTarget,
    required this.onEdit,
    required this.onDelete,
    required this.onDragStarted,
    required this.onDragEnd,
    required this.onDragOver,
    required this.onDragAccept,
  });

  @override
  State<_DraggableAppItem> createState() => _DraggableAppItemState();
}

class _DraggableAppItemState extends State<_DraggableAppItem> with SingleTickerProviderStateMixin {
  double _offsetX = 0;
  bool _isExpanded = false;
  static const double _actionWidth = 60;
  _AppItem? _draggingItem;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<int>(
      data: widget.index,
      delay: const Duration(milliseconds: 200),
      onDragStarted: () {
        widget.onDragStarted();
        setState(() {
          _draggingItem = widget.item;
        });
      },
      onDragEnd: (_) {
        widget.onDragEnd();
        setState(() {
          _draggingItem = null;
        });
      },
      onDraggableCanceled: (_, __) {
        widget.onDragEnd();
        setState(() {
          _draggingItem = null;
        });
      },
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 80,
          height: 90,
          child: _buildAppIcon(isDragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildAppIcon(),
      ),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) {
          widget.onDragOver();
          return true;
        },
        onAcceptWithDetails: (details) {
          widget.onDragAccept(details.data);
        },
        builder: (context, candidateData, rejectedData) {
          return _buildItemContent();
        },
      ),
    );
  }

  Widget _buildItemContent() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _offsetX += details.delta.dx;
          _offsetX = _offsetX.clamp(-_actionWidth, 0);
        });
      },
      onHorizontalDragEnd: (details) {
        if (_offsetX < -_actionWidth * 0.5) {
          setState(() {
            _offsetX = -_actionWidth;
            _isExpanded = true;
          });
        } else {
          setState(() {
            _offsetX = 0;
            _isExpanded = false;
          });
        }
      },
      onTap: () {
        if (_isExpanded) {
          setState(() {
            _offsetX = 0;
            _isExpanded = false;
          });
        } else {
          widget.onEdit();
        }
      },
      child: SizedBox(
        child: Stack(
          children: [
            // 删除按钮
            if (_isExpanded)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _offsetX = 0;
                      _isExpanded = false;
                    });
                    widget.onDelete();
                  },
                  child: Container(
                    width: _actionWidth,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete, color: Colors.white, size: 24),
                        SizedBox(height: 2),
                        Text('删除', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            // 应用图标
            Transform.translate(
              offset: Offset(_offsetX, 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                child: widget.isTarget
                    ? Transform.scale(
                        scale: 0.95,
                        child: _buildAppIcon(isHighlight: true),
                      )
                    : _buildAppIcon(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIcon({bool isDragging = false, bool isHighlight = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isHighlight
            ? Border.all(color: widget.item.color, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: isDragging
                ? widget.item.color.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: isDragging ? 0.2 : 0.08),
            blurRadius: isDragging ? 16 : 4,
            offset: Offset(0, isDragging ? 8.0 : 2.0),
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
              color: widget.item.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: widget.item.color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              widget.item.icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.item.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

void registerDragReorderDemo() {
  demoRegistry.register(DragReorderDemo());
}
