import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class ImageWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: ImageType(src: ''), icon: Icons.image, label: '🖼', category: BlockTypeCategory.media),
  ];

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    final imgType = block.type as ImageType;
    final src = imgType.src;
    final caption = imgType.caption;
    final width = imgType.width;
    final height = imgType.height;

    if (src.isEmpty) {
      return GestureDetector(
        onTap: callbacks.onTapAddImage,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              Icon(Icons.image_outlined, size: 32, color: Colors.grey[400]),
              const SizedBox(height: 4),
              Text('点击以添加图片',
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final isNetwork = src.startsWith('http://') || src.startsWith('https://');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: isNetwork
              ? Image.network(
                  src,
                  width: width,
                  height: height,
                  fit: width != null || height != null ? BoxFit.cover : null,
                  errorBuilder: (context, error, stackTrace) =>
                      _imageErrorPlaceholder(),
                )
              : Image.file(
                  File(src),
                  width: width,
                  height: height,
                  fit: width != null || height != null ? BoxFit.cover : null,
                  errorBuilder: (context, error, stackTrace) =>
                      _imageErrorPlaceholder(),
                ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(caption,
              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
      ],
    );
  }

  Widget _imageErrorPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.broken_image, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Text('加载失败', style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}
