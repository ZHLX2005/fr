import 'package:flutter/material.dart';
import '../models/body_region.dart';
import '../painters/body_block_painter.dart';
import '../widgets/tissue_legend.dart';
import '../widgets/record_sheet.dart';

enum MapMode { overview, subRegion }

class BodyMapPage extends StatefulWidget {
  final String title;
  final List<BlockRegion> regions;

  const BodyMapPage({super.key, this.title = '全身', required this.regions});

  @override
  State<BodyMapPage> createState() => _BodyMapPageState();
}

class _BodyMapPageState extends State<BodyMapPage> {
  MapMode _mode = MapMode.overview;
  String? _highlighted;

  BlockRegion? _hitTest(Offset localPos, Size canvasSize) {
    final sx = BodyBlockPainter.refW / canvasSize.width;
    final sy = BodyBlockPainter.refH / canvasSize.height;
    final mapped = Offset(localPos.dx * sx, localPos.dy * sy);
    for (final r in widget.regions.reversed) {
      if (r.hitTest(mapped)) return r;
    }
    return null;
  }

  void _onTap(Offset localPos, Size canvasSize) {
    final hit = _hitTest(localPos, canvasSize);
    if (hit == null) return;

    if (_mode == MapMode.overview || !hit.hasChildren) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => RecordSheet(bodyPart: hit),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BodyMapPage(title: hit.label, regions: hit.children),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: Column(
        children: [
          // 模式切换
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SegmentedButton<MapMode>(
              segments: const [
                ButtonSegment(
                  value: MapMode.overview,
                  icon: Icon(Icons.description),
                  label: Text('概览'),
                ),
                ButtonSegment(
                  value: MapMode.subRegion,
                  icon: Icon(Icons.zoom_in),
                  label: Text('子图'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          // 图例
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: TissueLegend(),
          ),
          // 人体色块图
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final canvasW = (h / 2 < w) ? h / 2 : w;
                  final canvasH = canvasW * 2;
                  final canvasSize = Size(canvasW, canvasH);

                  return Center(
                    child: SizedBox(
                      width: canvasW,
                      height: canvasH,
                      child: GestureDetector(
                        onTapUp: (d) => _onTap(d.localPosition, canvasSize),
                        onLongPressStart: (d) {
                          final hit = _hitTest(d.localPosition, canvasSize);
                          setState(() => _highlighted = hit?.id);
                        },
                        onLongPressEnd: (_) =>
                            setState(() => _highlighted = null),
                        child: CustomPaint(
                          size: canvasSize,
                          painter: BodyBlockPainter(
                            regions: widget.regions,
                            highlightedId: _highlighted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
