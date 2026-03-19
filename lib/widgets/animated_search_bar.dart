import 'dart:math';
import 'package:flutter/material.dart';

/// 展开式搜索栏组件
class AnimatedSearchBar extends StatefulWidget {
  final String? hintText;
  final ValueChanged<String>? onSearch;
  final double width;
  final double height;
  final Color? backgroundColor;
  final Color? primaryColor;

  const AnimatedSearchBar({
    super.key,
    this.hintText,
    this.onSearch,
    this.width = 320,
    this.height = 56,
    this.backgroundColor,
    this.primaryColor,
  });

  @override
  State<AnimatedSearchBar> createState() => _AnimatedSearchBarState();
}

class _AnimatedSearchBarState extends State<AnimatedSearchBar>
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
    final primaryColor = widget.primaryColor ?? theme.colorScheme.primary;
    final bgColor = widget.backgroundColor ?? Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: _isExpanded ? widget.width : 56,
      height: widget.height,
      decoration: BoxDecoration(
        color: bgColor,
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
                backgroundColor: primaryColor,
                child: const Icon(
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
                cursorColor: primaryColor,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  labelText: widget.hintText ?? '搜索...',
                  labelStyle: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                  hintText: widget.hintText ?? '输入关键词搜索',
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
                  widget.onSearch?.call(value);
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
                        color: primaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
