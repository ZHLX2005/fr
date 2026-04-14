import 'package:flutter/material.dart';
import '../models/home_item.dart';
import '../models/home_controller.dart';

/// 应用图标组件
class HomeTile extends StatelessWidget {
  final HomeItem item;
  final bool isDraggingFeedback;
  final VoidCallback? onTap;

  const HomeTile({
    super.key,
    required this.item,
    this.isDraggingFeedback = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
    if (item is AppItem) {
      return _buildAppTile(item as AppItem);
    } else if (item is FolderItem) {
      return _buildFolderTile(item as FolderItem);
    }
    return const SizedBox.shrink();
  }

  Widget _buildAppTile(AppItem app) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDraggingFeedback
                ? app.color.withAlpha(102)
                : Colors.black.withAlpha(20),
            blurRadius: isDraggingFeedback ? 16 : 4,
            offset: Offset(0, isDraggingFeedback ? 8 : 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: app.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: app.color.withAlpha(77),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(app.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            app.title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(FolderItem folder) {
    // 获取前9个应用
    final children = folder.children.take(9).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDraggingFeedback
                ? Colors.blue.withAlpha(102)
                : Colors.black.withAlpha(20),
            blurRadius: isDraggingFeedback ? 16 : 4,
            offset: Offset(0, isDraggingFeedback ? 8 : 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 文件夹内容网格（显示前9个小图标）
            Expanded(child: _buildFolderPreviewGrid(children)),
            const SizedBox(height: 4),
            Text(
              folder.title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${folder.children.length}',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建文件夹预览网格（前9个图标）
  Widget _buildFolderPreviewGrid(List<AppItem> children) {
    final count = children.length;

    if (count == 1) {
      // 1个图标：居中显示
      return Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: children[0].color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(children[0].icon, color: Colors.white, size: 20),
        ),
      );
    } else if (count == 2) {
      // 2个图标：上下排列
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildMiniIcon(children[0], 28),
          const SizedBox(height: 2),
          _buildMiniIcon(children[1], 28),
        ],
      );
    } else if (count <= 4) {
      // 4个图标：2x2
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: count,
        itemBuilder: (context, index) => _buildMiniIcon(children[index], 24),
      );
    } else {
      // 5-9个图标：3x3
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: count > 9 ? 9 : count,
        itemBuilder: (context, index) => _buildMiniIcon(children[index], 20),
      );
    }
  }

  /// 构建小图标
  Widget _buildMiniIcon(AppItem app, double size) {
    return Container(
      decoration: BoxDecoration(
        color: app.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(app.icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// 占位符组件
class PlaceholderTile extends StatelessWidget {
  const PlaceholderTile({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withAlpha(31),
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: const Center(
        child: Icon(Icons.drag_indicator, color: Colors.black26, size: 28),
      ),
    );
  }
}

/// 文件夹合并目标组件
class ItemMergeTarget extends StatelessWidget {
  final HomeController controller;
  final HomeItem targetItem;
  final Widget child;

  const ItemMergeTarget({
    super.key,
    required this.controller,
    required this.targetItem,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<HomeItem>(
      onWillAcceptWithDetails: (details) {
        if (details.data.id == targetItem.id) return false;
        final canMerge =
            (targetItem is AppItem || targetItem is FolderItem) &&
            (details.data is AppItem);
        controller.updateHoverOverItem(targetItem.id, folderHover: canMerge);
        return canMerge;
      },
      onLeave: (_) {
        controller.clearHover();
      },
      onAcceptWithDetails: (details) {
        controller.commitMergeToFolder(targetItem.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHover =
            controller.drag.hoverOverItemId == targetItem.id &&
            controller.drag.isFolderHover;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isHover
                ? Border.all(color: Colors.blueAccent, width: 3)
                : null,
          ),
          child: child,
        );
      },
    );
  }
}

/// 文件夹展示底部Sheet
class FolderSheet extends StatelessWidget {
  final FolderItem folder;

  const FolderSheet({super.key, required this.folder});

  static void show(BuildContext context, FolderItem folder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FolderSheet(folder: folder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动把手
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 文件夹标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${folder.children.length} 个应用',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 文件夹内容网格
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: folder.children.length,
              itemBuilder: (context, index) {
                final app = folder.children[index];
                return HomeTile(item: app);
              },
            ),
          ),
          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
