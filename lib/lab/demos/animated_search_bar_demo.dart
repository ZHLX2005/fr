import 'dart:math';
import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 展开式搜索栏 Demo
class AnimatedSearchBarDemo extends DemoPage {
  @override
  String get title => '动画搜索栏';

  @override
  String get description => '展开式搜索栏动画效果';

  @override
  Widget buildPage(BuildContext context) {
    return const _AnimatedSearchBarPage();
  }
}

class _AnimatedSearchBarPage extends StatefulWidget {
  const _AnimatedSearchBarPage();

  @override
  State<_AnimatedSearchBarPage> createState() => _AnimatedSearchBarPageState();
}

class _AnimatedSearchBarPageState extends State<_AnimatedSearchBarPage>
    with SingleTickerProviderStateMixin {
  late TextEditingController _textEditingController;
  late AnimationController _animationController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _textEditingController = TextEditingController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSearchBar() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _textEditingController.clear();
        _animationController.reverse();
      }
    });
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
                const Text(
                  '动画搜索栏',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('使用说明'),
                        content: const Text(
                          '点击搜索图标展开搜索栏\n'
                          '再次点击收起搜索栏\n'
                          '麦克风图标会旋转动画',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // 搜索栏展示区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surface,
                    Colors.blue.withOpacity(0.1),
                  ],
                ),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: _isExpanded ? 320 : 60,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        spreadRadius: -5.0,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // 搜索按钮
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: InkWell(
                          onTap: _toggleSearchBar,
                          borderRadius: BorderRadius.circular(25),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: theme.colorScheme.primary,
                            child: Icon(
                              Icons.search,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      // 搜索输入框
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: _isExpanded ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: TextField(
                            controller: _textEditingController,
                            cursorRadius: const Radius.circular(10.0),
                            cursorWidth: 2.0,
                            cursorColor: theme.colorScheme.primary,
                            style: const TextStyle(fontSize: 16),
                            decoration: InputDecoration(
                              floatingLabelBehavior: FloatingLabelBehavior.never,
                              labelText: '搜索...',
                              labelStyle: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                              hintText: '输入关键词搜索',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20.0),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                            ),
                            onSubmitted: (value) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('搜索: $value')),
                              );
                            },
                          ),
                        ),
                      ),
                      // 麦克风按钮（带旋转动画）
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Visibility(
                            visible: _isExpanded,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: AnimatedBuilder(
                                animation: _animationController,
                                builder: (context, child) {
                                  return Transform.rotate(
                                    angle: _animationController.value * 2 * pi,
                                    child: child,
                                  );
                                },
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.grey[200],
                                  child: Icon(
                                    Icons.mic,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 底部说明
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  '展开式搜索栏',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isExpanded ? '点击图标收起搜索栏' : '点击图标展开搜索栏',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '点击搜索按钮体验动画',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void registerAnimatedSearchBarDemo() {
  demoRegistry.register(AnimatedSearchBarDemo());
}
