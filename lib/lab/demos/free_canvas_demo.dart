import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../lab_container.dart';

/// 自由拖拽画布 Demo
class FreeCanvasDemo extends DemoPage {
  @override
  String get title => '自由画布';

  @override
  String get description => '自由拖拽图片和节点';

  @override
  Widget buildPage(BuildContext context) {
    return const _FreeCanvasPage();
  }
}

/// 画布节点数据模型
class CanvasNode {
  String id;
  Offset position;
  Size size;
  String? imagePath; // 图片路径，为空则显示背景色
  Color backgroundColor;
  String text;

  CanvasNode({
    required this.id,
    required this.position,
    this.size = const Size(120, 120),
    this.imagePath,
    this.backgroundColor = Colors.white,
    this.text = '',
  });

  CanvasNode copyWith({
    String? id,
    Offset? position,
    Size? size,
    String? imagePath,
    Color? backgroundColor,
    String? text,
  }) {
    return CanvasNode(
      id: id ?? this.id,
      position: position ?? this.position,
      size: size ?? this.size,
      imagePath: imagePath ?? this.imagePath,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      text: text ?? this.text,
    );
  }
}

class _FreeCanvasPage extends StatefulWidget {
  const _FreeCanvasPage();

  @override
  State<_FreeCanvasPage> createState() => _FreeCanvasPageState();
}

class _FreeCanvasPageState extends State<_FreeCanvasPage> {
  final List<CanvasNode> _nodes = [];
  String? _selectedNodeId;
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _addNode() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    final node = CanvasNode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: const Offset(50, 50),
      imagePath: image?.path,
      backgroundColor: Colors.grey[200]!,
    );

    setState(() {
      _nodes.add(node);
      _selectedNodeId = node.id;
    });
  }

  void _addTextNode() {
    final node = CanvasNode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: const Offset(50, 50),
      backgroundColor: Colors.blue[50]!,
      text: '双击编辑文字',
    );

    setState(() {
      _nodes.add(node);
      _selectedNodeId = node.id;
    });
  }

  void _deleteSelectedNode() {
    if (_selectedNodeId == null) return;
    setState(() {
      _nodes.removeWhere((n) => n.id == _selectedNodeId);
      _selectedNodeId = null;
    });
  }

  void _updateNodePosition(String id, Offset delta) {
    setState(() {
      final index = _nodes.indexWhere((n) => n.id == id);
      if (index != -1) {
        _nodes[index].position += delta;
      }
    });
  }

  void _updateNodeSize(String id, Size newSize) {
    setState(() {
      final index = _nodes.indexWhere((n) => n.id == id);
      if (index != -1) {
        _nodes[index].size = newSize;
      }
    });
  }

  void _showNodeEditor(CanvasNode node) {
    final textController = TextEditingController(text: node.text);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑节点'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: '节点文字',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final index = _nodes.indexWhere((n) => n.id == node.id);
                if (index != -1) {
                  _nodes[index].text = textController.text;
                }
              });
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自由画布'),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: _addTextNode,
            tooltip: '添加文字节点',
          ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: _addNode,
            tooltip: '添加图片节点',
          ),
          if (_selectedNodeId != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedNode,
              tooltip: '删除节点',
            ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              _transformController.value = Matrix4.identity();
              setState(() {
                _scale = 1.0;
                _canvasOffset = Offset.zero;
              });
            },
            tooltip: '重置视图',
          ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transformController,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.1,
        maxScale: 4.0,
        onInteractionUpdate: (details) {
          setState(() {});
        },
        child: SizedBox(
          width: 4000,
          height: 4000,
          child: Stack(
            children: [
              // 网格背景
              CustomPaint(
                size: const Size(4000, 4000),
                painter: _GridPainter(),
              ),
              // 所有节点
              ..._nodes.map((node) => _buildNodeWidget(node)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeWidget(CanvasNode node) {
    final isSelected = _selectedNodeId == node.id;

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedNodeId = node.id;
          });
        },
        onDoubleTap: () {
          if (node.text.isNotEmpty || node.imagePath == null) {
            _showNodeEditor(node);
          }
        },
        onPanUpdate: (details) {
          _updateNodePosition(node.id, details.delta);
        },
        child: Container(
          width: node.size.width,
          height: node.size.height,
          decoration: BoxDecoration(
            color: node.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 内容
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: node.imagePath != null
                    ? Image.file(
                        File(node.imagePath!),
                        fit: BoxFit.cover,
                        width: node.size.width,
                        height: node.size.height,
                        errorBuilder: (_, __, ___) => _buildTextContent(node),
                      )
                    : _buildTextContent(node),
              ),
              // 缩放手柄（选中时显示）
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final newWidth = (node.size.width + details.delta.dx)
                          .clamp(60.0, 400.0);
                      final newHeight = (node.size.height + details.delta.dy)
                          .clamp(60.0, 400.0);
                      _updateNodeSize(node.id, Size(newWidth, newHeight));
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.open_in_full,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // 删除按钮（选中时显示）
              if (isSelected)
                Positioned(
                  right: 4,
                  top: 4,
                  child: GestureDetector(
                    onTap: _deleteSelectedNode,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent(CanvasNode node) {
    return Container(
      width: node.size.width,
      height: node.size.height,
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          node.text.isEmpty ? '双击编辑' : node.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: node.text.isEmpty ? Colors.grey : Colors.black,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// 网格背景绘制器
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 1;

    const gridSize = 50.0;

    // 垂直线
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // 水平线
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 注册Demo
void registerFreeCanvasDemo() {
  demoRegistry.register(FreeCanvasDemo());
}
