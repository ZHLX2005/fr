import 'package:flutter/material.dart';
import '../models/word.dart';

/// 单词详情页 - 全屏展示单词详细信息
class WordDetailPage extends StatelessWidget {
  final Word word;
  final VoidCallback? onComplete; // 学习完成后的回调

  const WordDetailPage({super.key, required this.word, this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '单词详情',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // 单词主体
              Text(
                word.text,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              // 音标
              Text(
                word.phonetic,
                style: TextStyle(fontSize: 20, color: Colors.blue.shade300),
              ),
              const SizedBox(height: 40),
              // 释义卡片
              _DetailCard(
                title: '释义',
                content: word.definition,
                icon: Icons.menu_book_outlined,
                color: Colors.blue,
              ),
              const SizedBox(height: 20),
              // 例句卡片
              _DetailCard(
                title: '例句',
                content: word.example,
                icon: Icons.format_quote_outlined,
                color: Colors.green,
              ),
              const Spacer(),
              // 完成按钮
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    onComplete?.call();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    '我学会了',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 跳过按钮
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '稍后再说',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情卡片组件
class _DetailCard extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;
  final Color color;

  const _DetailCard({
    required this.title,
    required this.content,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
