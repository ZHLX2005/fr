import 'package:flutter/material.dart';
import '../models/word.dart';

/// 单词卡片内容
///
/// 支持两种模式：
/// - 简洁模式：只显示单词和释义
/// - 详情模式：显示单词、音标、释义、例句
class WordCardContent extends StatelessWidget {
  final Word word;
  final bool showDetails;
  final bool isDragging;

  const WordCardContent({
    super.key,
    required this.word,
    this.showDetails = false,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: showDetails ? 340 : 300,
      padding: EdgeInsets.all(showDetails ? 28 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: showDetails
              ? [Colors.deepPurple.shade500, Colors.purple.shade600]
              : [Colors.indigo.shade400, Colors.purple.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(showDetails ? 28 : 24),
        boxShadow: [
          BoxShadow(
            color: (showDetails ? Colors.deepPurple : Colors.purple)
                .withValues(alpha: isDragging ? 0.5 : 0.3),
            blurRadius: isDragging ? 30 : 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 单词
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontSize: showDetails ? 42 : 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
            child: Text(word.text),
          ),
          const SizedBox(height: 8),

          // 音标
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showDetails ? 1.0 : 0.8,
            child: Text(
              word.phonetic,
              style: TextStyle(
                fontSize: showDetails ? 18 : 16,
                color: Colors.white.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 释义
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              word.definition,
              style: TextStyle(
                fontSize: showDetails ? 20 : 18,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),

          // 详情模式：例句
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: showDetails
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.format_quote,
                                color: Colors.white.withValues(alpha: 0.6),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '例句',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            word.example,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // 底部提示
          const SizedBox(height: 20),
          Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: showDetails ? 0.0 : 0.5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.swipe,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    showDetails ? '' : '上滑查看详情',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
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
