import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 拖拽排序Demo - 支持长按拖动、删除、添加、编辑
class DragReorderDemo extends DemoPage {
  @override
  String get title => '拖拽排序';

  @override
  String get description => '长按拖动排序、删除、编辑';

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
  final List<_ItemData> _items = [];
  int _nextId = 1;

  @override
  void initState() {
    super.initState();
    // 初始化一些示例数据
    _items.addAll([
      _ItemData(id: _nextId++, title: '工作安排', color: Colors.blue),
      _ItemData(id: _nextId++, title: '学习计划', color: Colors.green),
      _ItemData(id: _nextId++, title: '健身计划', color: Colors.orange),
      _ItemData(id: _nextId++, title: '阅读清单', color: Colors.purple),
      _ItemData(id: _nextId++, title: '购物列表', color: Colors.red),
    ]);
  }

  void _addItem() async {
    final result = await _showEditDialog(context, null);
    if (result != null) {
      setState(() {
        _items.add(_ItemData(
          id: _nextId++,
          title: result.title,
          color: result.color,
        ));
      });
    }
  }

  void _editItem(_ItemData item) async {
    final result = await _showEditDialog(context, item);
    if (result != null) {
      setState(() {
        item.title = result.title;
        item.color = result.color;
      });
    }
  }

  void _deleteItem(_ItemData item) {
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

  Future<_EditResult?> _showEditDialog(BuildContext context, _ItemData? item) async {
    final titleController = TextEditingController(text: item?.title ?? '');
    Color selectedColor = item?.color ?? Colors.blue;

    return showDialog<_EditResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? '添加项目' : '编辑项目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(context, _EditResult(title: title, color: selectedColor));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  static const List<Color> _colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.amber,
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
      body: _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无数据',
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右上角添加项目',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final double elevation = Tween<double>(begin: 0, end: 8)
                        .animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ))
                        .value;
                    return Material(
                      elevation: elevation,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final item = _items[index];
                return _DraggableItem(
                  key: ValueKey(item.id),
                  item: item,
                  onEdit: () => _editItem(item),
                  onDelete: () => _deleteItem(item),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

/// 项目数据
class _ItemData {
  int id;
  String title;
  Color color;

  _ItemData({
    required this.id,
    required this.title,
    required this.color,
  });
}

/// 编辑结果
class _EditResult {
  String title;
  Color color;

  _EditResult({required this.title, required this.color});
}

/// 可拖拽的项目组件
class _DraggableItem extends StatelessWidget {
  final _ItemData item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DraggableItem({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.drag_handle,
              color: item.color,
            ),
          ),
          title: Text(
            item.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 22),
                color: Colors.grey[600],
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 22),
                color: Colors.red[400],
                onPressed: onDelete,
              ),
              ReorderableDragStartListener(
                index: 0,
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.drag_indicator, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void registerDragReorderDemo() {
  demoRegistry.register(DragReorderDemo());
}
