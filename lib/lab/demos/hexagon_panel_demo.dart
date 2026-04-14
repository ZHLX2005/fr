import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 六边形能力分析 Demo
class HexagonPanelDemo extends DemoPage {
  @override
  String get title => '六边形分析';

  @override
  String get description => '六边形雷达图展示综合能力或文件分析';

  @override
  Widget buildPage(BuildContext context) {
    return const _HexagonPanelPage();
  }
}

class _HexagonPanelPage extends StatefulWidget {
  const _HexagonPanelPage();

  @override
  State<_HexagonPanelPage> createState() => _HexagonPanelPageState();
}

class _HexagonPanelPageState extends State<_HexagonPanelPage> {
  // 示例数据 - 可以编辑
  List<HexagonItem> _items = [
    HexagonItem(label: '技术能力', value: 0.85, color: const Color(0xFF6366F1)),
    HexagonItem(label: '产品思维', value: 0.7, color: const Color(0xFF8B5CF6)),
    HexagonItem(label: '设计能力', value: 0.6, color: const Color(0xFFEC4899)),
    HexagonItem(label: '沟通协作', value: 0.9, color: const Color(0xFF14B8A6)),
    HexagonItem(label: '项目管理', value: 0.75, color: const Color(0xFFF59E0B)),
    HexagonItem(label: '创新能力', value: 0.65, color: const Color(0xFFEF4444)),
  ];

  String _title = '综合能力分析';
  String? _selectedItemLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // 六边形图表
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Center(
                    child: GestureDetector(
                      onTapUp: (details) {
                        // 点击检测
                        final center = Offset(size / 2, size / 2);
                        final tapPos = details.localPosition;
                        final dist = (tapPos - center).distance;
                        if (dist < size / 2 - 20) {
                          setState(() {
                            _selectedItemLabel = null;
                          });
                        }
                      },
                      child: CustomPaint(
                        size: Size(size, size),
                        painter: HexagonRadarPainter(
                          items: _items,
                          selectedLabel: _selectedItemLabel,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showEditDialog,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('编辑数据'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showPresetDialog,
                    icon: const Icon(Icons.dashboard_customize, size: 18),
                    label: const Text('预设模板'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 说明文字
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '点击六边形上的标签可查看详情，点击空白处取消选择',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showEditDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditDataSheet(
        items: _items,
        title: _title,
        onSave: (items, title) {
          setState(() {
            _items = items;
            _title = title;
          });
        },
      ),
    );
  }

  void _showPresetDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择预设模板',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('综合能力分析'),
              subtitle: const Text('技术、产品、设计、沟通、项目、创新'),
              onTap: () {
                setState(() {
                  _items = [
                    HexagonItem(
                      label: '技术能力',
                      value: 0.85,
                      color: const Color(0xFF6366F1),
                    ),
                    HexagonItem(
                      label: '产品思维',
                      value: 0.7,
                      color: const Color(0xFF8B5CF6),
                    ),
                    HexagonItem(
                      label: '设计能力',
                      value: 0.6,
                      color: const Color(0xFFEC4899),
                    ),
                    HexagonItem(
                      label: '沟通协作',
                      value: 0.9,
                      color: const Color(0xFF14B8A6),
                    ),
                    HexagonItem(
                      label: '项目管理',
                      value: 0.75,
                      color: const Color(0xFFF59E0B),
                    ),
                    HexagonItem(
                      label: '创新能力',
                      value: 0.65,
                      color: const Color(0xFFEF4444),
                    ),
                  ];
                  _title = '综合能力分析';
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('文件分析'),
              subtitle: const Text('大小、创建时间、修改频率、重要性、活跃度、共享性'),
              onTap: () {
                setState(() {
                  _items = [
                    HexagonItem(
                      label: '文件大小',
                      value: 0.4,
                      color: const Color(0xFF22C55E),
                    ),
                    HexagonItem(
                      label: '创建时间',
                      value: 0.8,
                      color: const Color(0xFF3B82F6),
                    ),
                    HexagonItem(
                      label: '修改频率',
                      value: 0.6,
                      color: const Color(0xFF8B5CF6),
                    ),
                    HexagonItem(
                      label: '重要性',
                      value: 0.9,
                      color: const Color(0xFFEF4444),
                    ),
                    HexagonItem(
                      label: '活跃度',
                      value: 0.7,
                      color: const Color(0xFFF59E0B),
                    ),
                    HexagonItem(
                      label: '共享性',
                      value: 0.5,
                      color: const Color(0xFF06B6D4),
                    ),
                  ];
                  _title = '文件分析';
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology),
              title: const Text('性格分析'),
              subtitle: const Text('外向、内向、理性、感性、独立、合作'),
              onTap: () {
                setState(() {
                  _items = [
                    HexagonItem(
                      label: '外向性',
                      value: 0.7,
                      color: const Color(0xFFF97316),
                    ),
                    HexagonItem(
                      label: '内向性',
                      value: 0.5,
                      color: const Color(0xFF6366F1),
                    ),
                    HexagonItem(
                      label: '理性思维',
                      value: 0.8,
                      color: const Color(0xFF3B82F6),
                    ),
                    HexagonItem(
                      label: '感性思维',
                      value: 0.6,
                      color: const Color(0xFFEC4899),
                    ),
                    HexagonItem(
                      label: '独立性',
                      value: 0.75,
                      color: const Color(0xFF14B8A6),
                    ),
                    HexagonItem(
                      label: '合作性',
                      value: 0.85,
                      color: const Color(0xFF22C55E),
                    ),
                  ];
                  _title = '性格分析';
                });
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 六边形数据项
class HexagonItem {
  String label;
  double value; // 0.0 - 1.0
  Color color;

  HexagonItem({required this.label, required this.value, required this.color});
}

/// 六边形雷达图Painter
class HexagonRadarPainter extends CustomPainter {
  final List<HexagonItem> items;
  final String? selectedLabel;

  HexagonRadarPainter({required this.items, this.selectedLabel});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    final sides = items.length;

    // 绘制背景网格层（渐变）
    _drawBackgroundLayers(canvas, center, radius);

    // 绘制网格线
    _drawGridLines(canvas, center, radius, sides);

    // 绘制数据区域（渐变填充）
    _drawDataArea(canvas, center, radius, sides);

    // 绘制顶点标签和数据点
    _drawLabelsAndPoints(canvas, center, radius, sides);
  }

  void _drawBackgroundLayers(Canvas canvas, Offset center, double radius) {
    // 绘制多层渐变背景
    for (int i = 5; i > 0; i--) {
      final layerRadius = radius * (i / 5);
      final path = _createHexagonPath(center, layerRadius, items.length);

      final gradient = RadialGradient(
        colors: [
          Colors.blue.withOpacity(0.02 * i),
          Colors.purple.withOpacity(0.02 * i),
        ],
      );

      final paint = Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: layerRadius),
        )
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }
  }

  void _drawGridLines(Canvas canvas, Offset center, double radius, int sides) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 绘制同心六边形
    for (int i = 1; i <= 5; i++) {
      final layerRadius = radius * (i / 5);
      final path = _createHexagonPath(center, layerRadius, sides);
      canvas.drawPath(path, gridPaint);
    }

    // 绘制从中心到顶点的线
    for (int i = 0; i < sides; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final endPoint = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, endPoint, gridPaint);
    }
  }

  void _drawDataArea(Canvas canvas, Offset center, double radius, int sides) {
    if (items.isEmpty) return;

    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final value = items[i].value.clamp(0.0, 1.0);
      final point = Offset(
        center.dx + radius * value * math.cos(angle),
        center.dy + radius * value * math.sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    // 渐变填充
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.blue.withOpacity(0.3),
        Colors.purple.withOpacity(0.3),
        Colors.pink.withOpacity(0.3),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // 边框
    final borderPaint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, borderPaint);
  }

  void _drawLabelsAndPoints(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
  ) {
    for (int i = 0; i < sides; i++) {
      final item = items[i];
      final angle = (math.pi / 3) * i - math.pi / 2;
      final value = item.value.clamp(0.0, 1.0);

      // 数据点
      final point = Offset(
        center.dx + radius * value * math.cos(angle),
        center.dy + radius * value * math.sin(angle),
      );

      // 绘制数据点和连线
      final isSelected = selectedLabel == item.label;

      // 连线
      final linePaint = Paint()
        ..color = item.color.withOpacity(0.6)
        ..strokeWidth = isSelected ? 3 : 2
        ..style = PaintingStyle.stroke;

      final lineEnd = Offset(
        center.dx + radius * 1.2 * math.cos(angle),
        center.dy + radius * 1.2 * math.sin(angle),
      );

      canvas.drawLine(point, lineEnd, linePaint);

      // 数据点（渐变）
      final pointGradient = RadialGradient(
        colors: [item.color, item.color.withOpacity(0.5)],
      );

      final pointPaint = Paint()
        ..shader = pointGradient.createShader(
          Rect.fromCircle(center: point, radius: isSelected ? 10 : 8),
        );

      canvas.drawCircle(point, isSelected ? 10 : 8, pointPaint);

      // 外圈
      final outerPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(point, isSelected ? 10 : 8, outerPaint);

      // 标签
      final labelPoint = Offset(
        center.dx + radius * 1.3 * math.cos(angle),
        center.dy + radius * 1.3 * math.sin(angle),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: TextStyle(
            color: isSelected ? item.color : Colors.black87,
            fontSize: isSelected ? 14 : 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final labelOffset = Offset(
        labelPoint.dx - textPainter.width / 2,
        labelPoint.dy - textPainter.height / 2,
      );

      // 标签背景
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: labelPoint,
          width: textPainter.width + 12,
          height: textPainter.height + 6,
        ),
        const Radius.circular(4),
      );

      final bgPaint = Paint()
        ..color = isSelected ? item.color.withOpacity(0.15) : Colors.white;

      canvas.drawRRect(bgRect, bgPaint);

      textPainter.paint(canvas, labelOffset);

      // 绘制数值
      final valueTextPainter = TextPainter(
        text: TextSpan(
          text: '${(item.value * 100).toInt()}%',
          style: TextStyle(
            color: item.color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      valueTextPainter.layout();

      final valueOffset = Offset(
        point.dx - valueTextPainter.width / 2,
        point.dy - valueTextPainter.height / 2 - 18,
      );
      valueTextPainter.paint(canvas, valueOffset);
    }
  }

  Path _createHexagonPath(Offset center, double radius, int sides) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant HexagonRadarPainter oldDelegate) {
    return items != oldDelegate.items ||
        selectedLabel != oldDelegate.selectedLabel;
  }
}

/// 编辑数据Sheet
class _EditDataSheet extends StatefulWidget {
  final List<HexagonItem> items;
  final String title;
  final Function(List<HexagonItem>, String) onSave;

  const _EditDataSheet({
    required this.items,
    required this.title,
    required this.onSave,
  });

  @override
  State<_EditDataSheet> createState() => _EditDataSheetState();
}

class _EditDataSheetState extends State<_EditDataSheet> {
  late TextEditingController _titleController;
  late List<HexagonItem> _items;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _items = widget.items
        .map((e) => HexagonItem(label: e.label, value: e.value, color: e.color))
        .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '编辑数据',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '数值 (0-100%)',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ...List.generate(_items.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _items[index].color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: Text(_items[index].label)),
                    Expanded(
                      flex: 3,
                      child: Slider(
                        value: _items[index].value,
                        onChanged: (v) {
                          setState(() {
                            _items[index].value = v;
                          });
                        },
                        activeColor: _items[index].color,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('${(_items[index].value * 100).toInt()}%'),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onSave(_items, _titleController.text);
                  Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void registerHexagonPanelDemo() {
  demoRegistry.register(HexagonPanelDemo());
}
