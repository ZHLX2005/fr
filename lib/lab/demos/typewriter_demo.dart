import 'dart:async';
import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 打字机效果 Demo
class TypewriterDemo extends DemoPage {
  @override
  String get title => '打字机';

  @override
  String get description => '文字逐字显示动画效果';

  @override
  Widget buildPage(BuildContext context) {
    return const _TypewriterPage();
  }
}

class _TypewriterPage extends StatefulWidget {
  const _TypewriterPage();

  @override
  State<_TypewriterPage> createState() => _TypewriterPageState();
}

class _TypewriterPageState extends State<_TypewriterPage> {
  // 预设文本
  final List<TextPreset> _presets = [
    TextPreset(
      title: '心灵鸡汤',
      texts: ['人生就像一场旅行，\n不必在乎目的地，\n在乎的是沿途的风景，\n和看风景的心情。'],
    ),
    TextPreset(title: '诗句', texts: ['床前明月光，\n疑是地上霜。\n举头望明月，\n低头思故乡。']),
    TextPreset(
      title: '代码感悟',
      texts: ['代码是写给人看的，\n顺便能在机器上运行。\n\n—— Donald Knuth'],
    ),
    TextPreset(
      title: '心灵语录',
      texts: ['每一次挫折，都是成长的契机。\n\n每一次失败，都是成功的铺垫。\n\n相信自己，你可以的！'],
    ),
  ];

  int _currentPresetIndex = 0;
  String _displayText = '';
  bool _isTyping = false;
  bool _showCursor = true;
  Timer? _cursorTimer;

  // 打字速度
  double _speed = 50; // 毫秒/字

  @override
  void initState() {
    super.initState();
    _startCursorBlink();
    _startTyping();
  }

  void _startCursorBlink() {
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _showCursor = !_showCursor;
        });
      }
    });
  }

  void _startTyping() async {
    if (_isTyping) return;

    setState(() {
      _isTyping = true;
      _displayText = '';
    });

    final texts = _presets[_currentPresetIndex].texts;

    for (final fullText in texts) {
      for (int i = 0; i <= fullText.length; i++) {
        if (!mounted || !_isTyping) return;

        setState(() {
          _displayText = fullText.substring(0, i);
        });

        await Future.delayed(Duration(milliseconds: _speed.round()));

        // 遇到换行符暂停更久
        if (i < fullText.length && fullText[i] == '\n') {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // 每段文字之间暂停
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() {
      _isTyping = false;
    });
  }

  void _nextPreset() {
    setState(() {
      _currentPresetIndex = (_currentPresetIndex + 1) % _presets.length;
    });
    _startTyping();
  }

  void _restart() {
    _startTyping();
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    super.dispose();
  }

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _presets[_currentPresetIndex].title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _restart,
                      tooltip: '重新播放',
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _nextPreset,
                      tooltip: '下一个',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 打字区域
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surface,
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 打字内容
                  Expanded(
                    child: SingleChildScrollView(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: SelectableText.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: _displayText,
                                style: const TextStyle(
                                  fontSize: 20,
                                  height: 2,
                                  color: Colors.black87,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              WidgetSpan(
                                child: AnimatedOpacity(
                                  opacity: _showCursor ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 100),
                                  child: Container(
                                    width: 2,
                                    height: 24,
                                    margin: const EdgeInsets.only(left: 2),
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 速度控制
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '打字速度',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${_speed.round()}ms/字',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _speed,
                          min: 20,
                          max: 200,
                          divisions: 18,
                          onChanged: (v) {
                            setState(() {
                              _speed = v;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TextPreset {
  final String title;
  final List<String> texts;

  TextPreset({required this.title, required this.texts});
}

void registerTypewriterDemo() {
  demoRegistry.register(TypewriterDemo());
}
