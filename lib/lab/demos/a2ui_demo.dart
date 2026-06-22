// A2UI 最小案例：静态 JSON → Flutter UI
// 完整链路：SurfaceController.handleMessage(A2uiMessage) → Surface widget
// 真实场景中 A2UI 消息由 AI Agent 流式产生，此 demo 把一串写死的 JSON 一次性灌入。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import '../lab_container.dart';

class A2uiDemo extends DemoPage {
  @override
  String get title => 'A2UI 渲染';

  @override
  String get description => 'Google A2UI 协议：静态 JSON → Flutter UI';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const A2uiDemoPage();
}

class A2uiDemoPage extends StatefulWidget {
  const A2uiDemoPage({super.key});

  @override
  State<A2uiDemoPage> createState() => _A2uiDemoPageState();
}

class _A2uiDemoPageState extends State<A2uiDemoPage> {
  static const String _surfaceId = 'demo_surface';

  late final SurfaceController _controller;
  late final StreamSubscription<SurfaceUpdate> _surfaceSub;
  late final StreamSubscription<ChatMessage> _submitSub;
  String? _lastSubmit;
  int _renderTick = 0;

  // 三段示例：基础结构、列表/卡片、按钮交互
  static final List<List<Map<String, dynamic>>> _scenarios = [
    _basicScenario,
    _cardScenario,
    _formScenario,
  ];

  @override
  void initState() {
    super.initState();
    _controller = SurfaceController(catalogs: [BasicCatalogItems.asCatalog()]);
    _surfaceSub = _controller.surfaceUpdates.listen((_) {
      if (mounted) setState(() => _renderTick++);
    });
    _submitSub = _controller.onSubmit.listen((msg) {
      if (mounted) setState(() => _lastSubmit = msg.text);
    });
    // 默认灌入第一个场景
    _loadScenario(0);
  }

  void _loadScenario(int index) {
    setState(() {
      _lastSubmit = null;
      _renderTick++;
    });
    // 清空旧 surface 后再灌新消息
    _controller.handleMessage(const DeleteSurface(surfaceId: _surfaceId));
    final messages = _scenarios[index]
        .map((json) => A2uiMessage.fromJson(json))
        .toList();
    for (final m in messages) {
      _controller.handleMessage(m);
    }
  }

  @override
  void dispose() {
    _surfaceSub.cancel();
    _submitSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceCtx = _controller.activeSurfaceIds.contains(_surfaceId)
        ? _controller.contextFor(_surfaceId)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('A2UI 渲染'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: List.generate(_scenarios.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.tonal(
                    onPressed: () => _loadScenario(i),
                    child: Text('场景 ${i + 1}'),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: surfaceCtx == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Surface(surfaceContext: surfaceCtx),
                  ),
          ),
          if (_lastSubmit != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Text(
                '按钮回调: $_lastSubmit',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===== 场景 1：基础结构 — Text + Column ============================
  static final List<Map<String, dynamic>> _basicScenario = [
    {
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': _surfaceId,
        'catalogId': 'https://a2ui.org/specification/v0_9/basic_catalog.json',
      },
    },
    {
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': _surfaceId,
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['title', 'body', 'hint'],
          },
          {
            'id': 'title',
            'component': 'Text',
            'text': 'A2UI 静态 JSON → Flutter UI',
            'variant': 'h2',
          },
          {
            'id': 'body',
            'component': 'Text',
            'text': '下面这棵 UI 是从一串 A2UI 协议消息渲染出来的，'
                '没有调用任何 AI 后端。',
          },
          {
            'id': 'hint',
            'component': 'Text',
            'text': '切换顶部场景看不同组件。',
            'variant': 'caption',
          },
        ],
      },
    },
  ];

  // ===== 场景 2：列表 + 卡片 ========================================
  static final List<Map<String, dynamic>> _cardScenario = [
    {
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': _surfaceId,
        'catalogId': 'https://a2ui.org/specification/v0_9/basic_catalog.json',
      },
    },
    {
      'version': 'v0.9',
      'updateDataModel': {
        'surfaceId': _surfaceId,
        'path': '/',
        'value': {
          'places': [
            {'name': '红螺寺', 'desc': '北京怀柔，登山祈福。'},
            {'name': '莫干山', 'desc': '浙江德清，竹林民宿密集。'},
            {'name': '婺源', 'desc': '江西上饶，春季油菜花海。'},
          ],
        },
      },
    },
    {
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': _surfaceId,
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['header', 'places_list'],
          },
          {
            'id': 'header',
            'component': 'Text',
            'text': '推荐目的地',
            'variant': 'h3',
          },
          {
            'id': 'places_list',
            'component': 'List',
            'data': '/places',
            'template': 'place_card',
          },
          {
            'id': 'place_card',
            'component': 'Card',
            'child': 'place_inner',
          },
          {
            'id': 'place_inner',
            'component': 'Column',
            'children': ['place_name', 'place_desc'],
          },
          {
            'id': 'place_name',
            'component': 'Text',
            'text': {'path': 'name'},
            'variant': 'h5',
          },
          {
            'id': 'place_desc',
            'component': 'Text',
            'text': {'path': 'desc'},
          },
        ],
      },
    },
  ];

  // ===== 场景 3：按钮 + 输入框交互 =================================
  static final List<Map<String, dynamic>> _formScenario = [
    {
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': _surfaceId,
        'catalogId': 'https://a2ui.org/specification/v0_9/basic_catalog.json',
      },
    },
    {
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': _surfaceId,
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['title', 'name_label', 'name_field', 'submit_btn'],
          },
          {
            'id': 'title',
            'component': 'Text',
            'text': '预订 Demo',
            'variant': 'h3',
          },
          {
            'id': 'name_label',
            'component': 'Text',
            'text': '姓名',
          },
          {
            'id': 'name_field',
            'component': 'TextField',
            'label': '请输入姓名',
          },
          {
            'id': 'submit_btn',
            'component': 'Button',
            'child': 'submit_text',
            'action': {
              'event': {
                'name': 'submit_form',
                'context': {
                  'name': {'path': 'name'},
                },
              },
            },
          },
          {
            'id': 'submit_text',
            'component': 'Text',
            'text': '提交',
          },
        ],
      },
    },
  ];
}

void registerA2uiDemo() {
  demoRegistry.register(A2uiDemo());
}
