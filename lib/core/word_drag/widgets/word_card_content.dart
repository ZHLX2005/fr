import 'package:flutter/material.dart';
import '../models/word.dart';

/// 单词卡片内容
///
/// 模仿 photoo PhotoCard 风格：
/// - 白色/浅灰色背景
/// - 深色文字
/// - 简洁清晰的设计
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use available width from parent (card width)
        final availableWidth = constraints.maxWidth;

        return Container(
          width: availableWidth,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 单词（自动缩小到单行）
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  word.text,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(height: 8),

              // 音标
              Text(
                word.phonetic,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 20),

              // 释义
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  word.definition,
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    height: 1.5,
                  ),
                ),
              ),

              // 例句
              if (showDetails) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.format_quote,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '例句',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
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
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 底部提示
              const Spacer(),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swipe, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '上滑查看详情',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
