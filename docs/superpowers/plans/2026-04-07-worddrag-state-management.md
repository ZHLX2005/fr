# WordDrag 状态管理重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用 ChangeNotifier 重构 WordDrag 状态管理，实现状态驱动 UI 刷新，事件驱动状态变更。

**Architecture:**
- 使用 ChangeNotifier + ChangeNotifierProvider 管理 WordDrag 状态
- 所有交互逻辑集中在 WordDragNotifier 中处理
- WordDragPage 作为 ConsumerWidget 只负责 UI 渲染
- 事件通过方法调用分发到 Notifier

**Tech Stack:** Flutter + ChangeNotifier (内置)

---

## 文件结构

```
lib/core/word_drag/
├── word_drag.dart                    # 导出
├── models/
│   └── word.dart                     # [不变] 单词数据模型
├── pages/
│   ├── word_drag_page.dart          # [重构] 使用 ConsumerWidget
│   └── word_detail_page.dart         # [不变] 详情页
├── widgets/
│   ├── draggable_word_card.dart     # [重构] 简化为纯 UI + 手势转发
│   ├── word_card_content.dart       # [不变] 卡片内容
│   └── delete_zone.dart             # [删除] 合并到 word_drag_page
└── providers/                        # [新建]
    ├── word_drag_state.dart         # 状态数据类
    └── word_drag_notifier.dart      # ChangeNotifier
```

---

## Task 1: 创建状态数据类

**Files:**
- Create: `lib/core/word_drag/providers/word_drag_state.dart`

- [ ] **Step 1: 创建状态数据类**

```dart
// lib/core/word_drag/providers/word_drag_state.dart

/// 区域类型枚举
enum ZoneType { none, mark, delete }

/// WordDrag 状态数据类（不可变）
class WordDragState {
  final List<Word> words;
  final int currentIndex;

  // 拖动状态
  final Offset cardOffset;
  final bool isDragging;

  // 区域状态
  final ZoneType activeZone;      // 当前激活的区域类型
  final double markZoneOpacity;
  final double deleteZoneOpacity;

  // 提示状态
  final bool showMarkSuccessHint;    // 左滑标记"稍后复习"成功
  final bool showMarkNewSuccessHint; // 标新成功
  final bool showDeleteSuccessHint;  // 删除成功

  // 是否显示详情页
  final bool showDetails;

  // 构造默认值
  const WordDragState({
    required this.words,
    this.currentIndex = 0,
    this.cardOffset = Offset.zero,
    this.isDragging = false,
    this.activeZone = ZoneType.none,
    this.markZoneOpacity = 0.0,
    this.deleteZoneOpacity = 0.0,
    this.showMarkSuccessHint = false,
    this.showMarkNewSuccessHint = false,
    this.showDeleteSuccessHint = false,
    this.showDetails = false,
  });

  // 便捷构造：从示例单词创建
  factory WordDragState.initial() {
    return WordDragState(words: List.from(Word.sampleWords));
  }

  // copyWith 方法
  WordDragState copyWith({
    List<Word>? words,
    int? currentIndex,
    Offset? cardOffset,
    bool? isDragging,
    ZoneType? activeZone,
    double? markZoneOpacity,
    double? deleteZoneOpacity,
    bool? showMarkSuccessHint,
    bool? showMarkNewSuccessHint,
    bool? showDeleteSuccessHint,
    bool? showDetails,
  }) {
    return WordDragState(
      words: words ?? this.words,
      currentIndex: currentIndex ?? this.currentIndex,
      cardOffset: cardOffset ?? this.cardOffset,
      isDragging: isDragging ?? this.isDragging,
      activeZone: activeZone ?? this.activeZone,
      markZoneOpacity: markZoneOpacity ?? this.markZoneOpacity,
      deleteZoneOpacity: deleteZoneOpacity ?? this.deleteZoneOpacity,
      showMarkSuccessHint: showMarkSuccessHint ?? this.showMarkSuccessHint,
      showMarkNewSuccessHint: showMarkNewSuccessHint ?? this.showMarkNewSuccessHint,
      showDeleteSuccessHint: showDeleteSuccessHint ?? this.showDeleteSuccessHint,
      showDetails: showDetails ?? this.showDetails,
    );
  }

  /// 当前单词
  Word? get currentWord {
    if (words.isEmpty || currentIndex >= words.length) return null;
    return words[currentIndex];
  }

  /// 是否在标新区
  bool get isInMarkZone => activeZone == ZoneType.mark;

  /// 是否在删除区
  bool get isInDeleteZone => activeZone == ZoneType.delete;

  /// 是否在任意区域
  bool get isInAnyZone => activeZone != ZoneType.none;

  /// 是否有下一个单词
  bool get hasNextWord => words.isNotEmpty && currentIndex < words.length;
}
```

- [ ] **Step 2: 验证文件语法**

Run: `dart analyze lib/core/word_drag/providers/word_drag_state.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/core/word_drag/providers/word_drag_state.dart
git commit -m "feat(word_drag): 添加 WordDragState 数据类"
```

---

## Task 2: 创建 WordDragNotifier

**Files:**
- Create: `lib/core/word_drag/providers/word_drag_notifier.dart`

- [ ] **Step 1: 创建 WordDragNotifier**

```dart
// lib/core/word_drag/providers/word_drag_notifier.dart

/// WordDragNotifier - 状态管理器
/// 处理所有事件，驱动状态变更
class WordDragNotifier extends ChangeNotifier {
  WordDragState _state = WordDragState.initial();

  WordDragState get state => _state;

  // ========== 拖动事件 ==========

  void onDragStart() {
    _state = _state.copyWith(
      isDragging: true,
      cardOffset: Offset.zero,
    );
    notifyListeners();
  }

  void onDragUpdate(Offset delta, Size screenSize) {
    _state = _state.copyWith(
      cardOffset: _state.cardOffset + delta,
    );

    // 计算区域状态
    _updateZoneState(screenSize);
    notifyListeners();
  }

  void onDragEnd(Size screenSize) {
    // 如果在区域内且区域操作被激活，强制触发区域操作
    if (_state.isInAnyZone) {
      // 计算释放时的区域
      final zone = _checkZoneAtRelease(screenSize);
      if (zone != ZoneType.none) {
        // 强制滑出并触发操作
        _triggerZoneAction(zone);
        return;
      }
    }

    // 计算滑动方向
    final direction = _calculateSwipeDirection(screenSize);
    _handleSwipeDirection(direction);
  }

  // ========== 区域检测 ==========

  void _updateZoneState(Size screenSize) {
    final cardCenter = _getCardCenter(screenSize);

    // 标新区：右侧上方
    final markZoneRect = Rect.fromLTWH(
      screenSize.width - 100,
      screenSize.height * 0.15,
      80,
      screenSize.height * 0.25,
    ).inflate(30);

    // 删除区：右侧下方
    final deleteZoneRect = Rect.fromLTWH(
      screenSize.width - 100,
      screenSize.height * 0.6,
      80,
      screenSize.height * 0.25,
    ).inflate(30);

    final inMark = markZoneRect.contains(cardCenter);
    final inDelete = deleteZoneRect.contains(cardCenter);

    ZoneType activeZone = ZoneType.none;
    double markOpacity = 0.0;
    double deleteOpacity = 0.0;

    if (_state.cardOffset.dx > 20) {
      // 右滑
      if (_state.cardOffset.dy < -30) {
        // 右上 - 标新
        activeZone = ZoneType.mark;
        markOpacity = _calculateZoneOpacity(_state.cardOffset, screenSize);
      } else if (_state.cardOffset.dy > 30) {
        // 右下 - 删除
        activeZone = ZoneType.delete;
        deleteOpacity = _calculateZoneOpacity(_state.cardOffset, screenSize);
      } else {
        // 正右 - 两个都显示一点
        markOpacity = 0.5;
        deleteOpacity = 0.5;
      }
    }

    _state = _state.copyWith(
      activeZone: activeZone,
      markZoneOpacity: markOpacity,
      deleteZoneOpacity: deleteOpacity,
    );
  }

  ZoneType _checkZoneAtRelease(Size screenSize) {
    final cardCenter = _getCardCenter(screenSize);

    final markZoneRect = Rect.fromLTWH(
      screenSize.width - 100,
      screenSize.height * 0.15,
      80,
      screenSize.height * 0.25,
    ).inflate(30);

    final deleteZoneRect = Rect.fromLTWH(
      screenSize.width - 100,
      screenSize.height * 0.6,
      80,
      screenSize.height * 0.25,
    ).inflate(30);

    if (markZoneRect.contains(cardCenter)) return ZoneType.mark;
    if (deleteZoneRect.contains(cardCenter)) return ZoneType.delete;
    return ZoneType.none;
  }

  double _calculateZoneOpacity(Offset offset, Size screenSize) {
    final horizontalProgress =
        (offset.dx / (screenSize.width * 0.4)).clamp(0.0, 1.0);
    final verticalProgress =
        (offset.dy.abs() / (screenSize.height * 0.2)).clamp(0.0, 1.0);
    return horizontalProgress * (1 - verticalProgress * 0.5);
  }

  Offset _getCardCenter(Size screenSize) {
    return screenSize.center(Offset.zero) + _state.cardOffset;
  }

  SwipeDirection _calculateSwipeDirection(Size screenSize) {
    final thresholdX = screenSize.width * 0.25;
    final thresholdY = screenSize.height * 0.15;

    if (_state.cardOffset.dy < -thresholdY &&
        _state.cardOffset.dy.abs() > _state.cardOffset.dx.abs() * 1.5) {
      return SwipeDirection.up;
    } else if (_state.cardOffset.dx > thresholdX) {
      return SwipeDirection.right;
    } else if (_state.cardOffset.dx < -thresholdX) {
      return SwipeDirection.left;
    }
    return SwipeDirection.none;
  }

  void _handleSwipeDirection(SwipeDirection direction) {
    switch (direction) {
      case SwipeDirection.up:
        // 上滑 → 详情页
        _navigateToDetail();
        break;
      case SwipeDirection.right:
        // 右滑 → 详情页
        _navigateToDetail();
        break;
      case SwipeDirection.left:
        // 左滑 → 稍后复习
        _markAsReviewed();
        break;
      case SwipeDirection.none:
        // 回弹
        _springBack();
        break;
    }
  }

  // ========== 区域操作 ==========

  void _triggerZoneAction(ZoneType zone) {
    // 这个方法由外部调用，返回需要触发的回调类型
    // 实际回调由 WordDragPage 处理
  }

  void onZoneConfirmed() {
    // 用户在区域内释放，确认执行操作
    if (_state.isInMarkZone) {
      _markAsNew();
    } else if (_state.isInDeleteZone) {
      _deleteWord();
    }
  }

  void _markAsNew() {
    if (!_state.hasNextWord) return;

    setState(() {
      final word = _state.words.removeAt(_state.currentIndex);
      _state.words.add(word);
      _ensureValidIndex();
      _resetZoneAndHints();
      _state = _state.copyWith(showMarkNewSuccessHint: true);
    });

    _hideHintAfterDelay(showMarkNewSuccessHint: true);
    notifyListeners();
  }

  void _deleteWord() {
    if (!_state.hasNextWord) return;

    setState(() {
      _state.words.removeAt(_state.currentIndex);
      _ensureValidIndex();
      _resetZoneAndHints();
      _state = _state.copyWith(showDeleteSuccessHint: true);
    });

    _hideHintAfterDelay(showDeleteSuccessHint: true);
    notifyListeners();
  }

  void _markAsReviewed() {
    if (!_state.hasNextWord) return;

    setState(() {
      final word = _state.words.removeAt(_state.currentIndex);
      _state.words.add(word);
      _ensureValidIndex();
      _resetZoneAndHints();
      _state = _state.copyWith(showMarkSuccessHint: true);
    });

    _hideHintAfterDelay(showMarkSuccessHint: true);
    notifyListeners();
  }

  // ========== 导航 ==========

  void _navigateToDetail() {
    // 这个方法触发详情页导航
    // 导航逻辑由 WordDragPage 处理
    _onNavigateToDetail?.call();
  }

  VoidCallback? _onNavigateToDetail;

  void setNavigateCallback(VoidCallback callback) {
    _onNavigateToDetail = callback;
  }

  // ========== 辅助方法 ==========

  void _springBack() {
    _state = _state.copyWith(
      isDragging: false,
      cardOffset: Offset.zero,
      activeZone: ZoneType.none,
      markZoneOpacity: 0.0,
      deleteZoneOpacity: 0.0,
    );
    notifyListeners();
  }

  void _resetZoneAndHints() {
    _state = _state.copyWith(
      isDragging: false,
      cardOffset: Offset.zero,
      activeZone: ZoneType.none,
      markZoneOpacity: 0.0,
      deleteZoneOpacity: 0.0,
    );
  }

  void _ensureValidIndex() {
    if (_state.words.isNotEmpty && _state.currentIndex >= _state.words.length) {
      _state = _state.copyWith(currentIndex: _state.words.length - 1);
    }
  }

  void _hideHintAfterDelay({
    bool showMarkSuccessHint = false,
    bool showMarkNewSuccessHint = false,
    bool showDeleteSuccessHint = false,
  }) {
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _state = _state.copyWith(
          showMarkSuccessHint: showMarkSuccessHint ? false : _state.showMarkSuccessHint,
          showMarkNewSuccessHint: showMarkNewSuccessHint ? false : _state.showMarkNewSuccessHint,
          showDeleteSuccessHint: showDeleteSuccessHint ? false : _state.showDeleteSuccessHint,
        );
      });
      notifyListeners();
    });
  }

  // ========== 外部调用 ==========

  void onDetailPageComplete() {
    setState(() {
      _resetZoneAndHints();
      _state = _state.copyWith(showDetails: false);
    });
    notifyListeners();
  }

  void resetWords() {
    _state = WordDragState.initial();
    notifyListeners();
  }

  // 转发拖动回调给 DraggableWordCard
  void forwardDragEventsTo(DraggableWordCardController controller) {
    controller.onDragStart = onDragStart;
    controller.onDragUpdate = (delta) => onDragUpdate(delta, controller.screenSize);
    controller.onDragEnd = () => onDragEnd(controller.screenSize);
  }
}

/// 拖动方向枚举
enum SwipeDirection { none, up, left, right }
```

- [ ] **Step 2: 验证文件语法**

Run: `dart analyze lib/core/word_drag/providers/word_drag_notifier.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/core/word_drag/providers/word_drag_notifier.dart
git commit -m "feat(word_drag): 添加 WordDragNotifier 状态管理器"
```

---

## Task 3: 创建 DraggableWordCardController

**Files:**
- Create: `lib/core/word_drag/providers/draggable_word_card_controller.dart`

- [ ] **Step 1: 创建控制器**

```dart
// lib/core/word_drag/providers/draggable_word_card_controller.dart

import 'package:flutter/material.dart';

/// DraggableWordCard 的控制器
/// 用于将手势事件转发给 WordDragNotifier
class DraggableWordCardController {
  Size screenSize = Size.zero;

  VoidCallback? onDragStart;
  void Function(Offset delta)? onDragUpdate;
  VoidCallback? onDragEnd;

  void handleDragStart(DragStartDetails details) {
    onDragStart?.call();
  }

  void handleDragUpdate(DragUpdateDetails details) {
    onDragUpdate?.call(details.delta);
  }

  void handleDragEnd(DragEndDetails details) {
    onDragEnd?.call();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/word_drag/providers/draggable_word_card_controller.dart
git commit -m "feat(word_drag): 添加 DraggableWordCardController"
```

---

## Task 4: 重构 DraggableWordCard

**Files:**
- Modify: `lib/core/word_drag/widgets/draggable_word_card.dart`

- [ ] **Step 1: 简化 DraggableWordCard**

将现有的 DraggableWordCard 简化为纯 UI 组件，移除所有状态管理逻辑：

```dart
// lib/core/word_drag/widgets/draggable_word_card.dart

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 弹性单词卡片 - 纯 UI 组件
/// 状态管理由 WordDragNotifier 处理
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  final DraggableWordCardController controller;
  final bool isInZone;           // 是否在区域内（用于高亮）
  final double zoneOpacity;      // 区域透明度

  const DraggableWordCard({
    super.key,
    required this.child,
    required this.controller,
    this.isInZone = false,
    this.zoneOpacity = 0.0,
  });

  @override
  State<DraggableWordCard> createState() => _DraggableWordCardState();
}

class _DraggableWordCardState extends State<DraggableWordCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<Offset>? _animation;

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _controller.addListener(_onAnimationUpdate);

    // 注册控制器回调
    widget.controller.screenSize = MediaQuery.of(context).size;
    widget.controller.onDragStart = _onPanStart;
    widget.controller.onDragUpdate = _onPanUpdate;
    widget.controller.onDragEnd = _onPanEnd;
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationUpdate() {
    if (_animation != null && _controller.isAnimating) {
      setState(() {
        _dragOffset = _animation!.value;
      });
    }
  }

  void _onPanStart() {
    _controller.stop();
    setState(() {
      _isDragging = true;
      _dragOffset = Offset.zero;
    });
  }

  void _onPanUpdate(Offset delta) {
    setState(() {
      _dragOffset += delta;
    });
  }

  void _onPanEnd() {
    _isDragging = false;
    widget.controller.onDragEnd?.call();
  }

  void _springBack() {
    _animation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _controller
      ..value = 0.0
      ..animateTo(1.0, duration: const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 弹性阻尼
    final dampingX = _calculateDamping(_dragOffset.dx, screenWidth);
    final dampingY = _calculateDamping(_dragOffset.dy, screenHeight);

    final dampedOffset = Offset(
      _dragOffset.dx * dampingX,
      _dragOffset.dy * dampingY,
    );

    // 旋转
    final rotation = dampedOffset.dx * 0.0015;

    // 缩放
    final distance = dampedOffset.distance;
    final maxDistance = screenWidth * 0.8;
    final scale = 1.0 - (distance / maxDistance * 0.08);

    // 透明度
    final opacity = (scale * 1.2).clamp(0.6, 1.0);

    return GestureDetector(
      onPanStart: (_) => widget.controller.onDragStart?.call(),
      onPanUpdate: (details) => widget.controller.onDragUpdate?.call(details.delta),
      onPanEnd: (_) => widget.controller.onDragEnd?.call(),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(_dragOffset.dx, _dragOffset.dy)
          ..rotateZ(rotation)
          ..scale(scale.clamp(0.85, 1.0)),
        child: Opacity(
          opacity: opacity,
          child: widget.child,
        ),
      ),
    );
  }

  double _calculateDamping(double offset, double maxExtent) {
    final absOffset = offset.abs();
    if (absOffset > maxExtent) {
      final excess = absOffset - maxExtent;
      final dampedExcess = excess / (excess + maxExtent * 0.3);
      return 1.0 - dampedExcess * 0.5;
    }
    return 1.0;
  }
}
```

- [ ] **Step 2: 验证编译**

Run: `flutter build web --release 2>&1 | tail -5`
Expected: √ Built build\web

- [ ] **Step 3: Commit**

```bash
git add lib/core/word_drag/widgets/draggable_word_card.dart
git commit -m "refactor(word_drag): 简化 DraggableWordCard 为纯 UI 组件"
```

---

## Task 5: 重构 WordDragPage

**Files:**
- Modify: `lib/core/word_drag/pages/word_drag_page.dart`

- [ ] **Step 1: 重构为 ConsumerWidget**

```dart
// lib/core/word_drag/pages/word_drag_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/word_drag_notifier.dart';
import '../providers/draggable_word_card_controller.dart';
import '../widgets/draggable_word_card.dart';
import '../widgets/word_card_content.dart';
import 'word_detail_page.dart';

/// 单词拖拽背词页面
/// 使用 ChangeNotifier 模式管理状态
class WordDragPage extends StatelessWidget {
  const WordDragPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WordDragNotifier(),
      child: const _WordDragPageContent(),
    );
  }
}

class _WordDragPageContent extends StatefulWidget {
  const _WordDragPageContent();

  @override
  State<_WordDragPageContent> createState() => _WordDragPageContentState();
}

class _WordDragPageContentState extends State<_WordDragPageContent> {
  final DraggableWordCardController _cardController = DraggableWordCardController();

  @override
  void initState() {
    super.initState();
    // 设置导航回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = context.read<WordDragNotifier>();
      notifier.setNavigateCallback(_navigateToDetail);
    });
  }

  void _navigateToDetail() {
    final notifier = context.read<WordDragNotifier>();
    final word = notifier.state.currentWord;
    if (word == null) return;

    // 进入详情页时切换到下一个单词
    final nextIndex = (notifier.state.currentIndex + 1) % notifier.state.words.length;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WordDetailPage(
          word: word,
          onComplete: () {
            notifier.onDetailPageComplete();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WordDragNotifier>();
    final state = notifier.state;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Stack(
          children: [
            // 顶部进度
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: _buildProgressIndicator(state),
            ),

            // 中心卡片
            Center(
              child: state.hasNextWord
                  ? _buildCardStack(notifier, state)
                  : _buildEmptyState(notifier),
            ),

            // 右上角标新区
            if (state.hasNextWord)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.15,
                child: Opacity(
                  opacity: state.markZoneOpacity.clamp(0.0, 1.0),
                  child: _ActionZone(
                    icon: Icons.bookmark_add_outlined,
                    label: '标新',
                    isActive: state.isInMarkZone,
                    onTap: state.isInMarkZone ? notifier.onZoneConfirmed : null,
                  ),
                ),
              ),

            // 右下角删除区
            if (state.hasNextWord)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.60,
                child: Opacity(
                  opacity: state.deleteZoneOpacity.clamp(0.0, 1.0),
                  child: _ActionZone(
                    icon: Icons.delete_outline,
                    label: '删除',
                    isActive: state.isInDeleteZone,
                    isDelete: true,
                    onTap: state.isInDeleteZone ? notifier.onZoneConfirmed : null,
                  ),
                ),
              ),

            // 底部提示
            if (state.hasNextWord && state.markZoneOpacity < 0.1 && state.deleteZoneOpacity < 0.1)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: 0.5,
                    child: Text(
                      '上: 详情 | 左: 稍后 | 右: 操作',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ),
                ),
              ),

            // 区域确认提示
            if (state.isInMarkZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: _ConfirmHint(label: '松开标记新词', color: Colors.blue)),
              ),

            if (state.isInDeleteZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: _ConfirmHint(label: '松开删除', color: Colors.red)),
              ),

            // 成功提示
            if (state.showMarkSuccessHint)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: _SuccessHint(label: '已标记稍后复习', icon: Icons.check_circle)),
              ),

            if (state.showMarkNewSuccessHint)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: Center(child: _SuccessHint(label: '已标记为新词', icon: Icons.bookmark_add)),
              ),

            if (state.showDeleteSuccessHint)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: Center(child: _SuccessHint(label: '已删除单词', icon: Icons.delete)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStack(WordDragNotifier notifier, WordDragState state) {
    return DraggableWordCard(
      controller: _cardController,
      child: WordCardContent(
        word: state.currentWord!,
        isDragging: state.isDragging,
      ),
    );
  }

  Widget _buildProgressIndicator(WordDragState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${state.words.length} 个单词',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              Text(
                '已复习 ${Word.sampleWords.length - state.words.length}',
                style: TextStyle(color: Colors.green.shade400, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.words.isEmpty
                ? 1.0
                : (Word.sampleWords.length - state.words.length) / Word.sampleWords.length,
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation(Colors.green.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WordDragNotifier notifier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, size: 80, color: Colors.green.shade400),
        const SizedBox(height: 24),
        const Text(
          '太棒了！',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          '已完成全部 ${Word.sampleWords.length} 个单词',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: notifier.resetWords,
          child: const Text('再学一遍'),
        ),
      ],
    );
  }
}

/// 操作区域组件
class _ActionZone extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDelete;
  final VoidCallback? onTap;

  const _ActionZone({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isDelete = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDelete ? Colors.red : Colors.blue;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 80,
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [color.shade500, color.shade700]
                : [Colors.grey.shade800, Colors.grey.shade900],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color.shade300.withValues(alpha: 0.8) : Colors.grey.shade700,
            width: 2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isActive ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(icon, color: isActive ? Colors.white : Colors.grey, size: 36),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 确认提示组件
class _ConfirmHint extends StatelessWidget {
  final String label;
  final Color color;

  const _ConfirmHint({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '松开$label',
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 成功提示组件
class _SuccessHint extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SuccessHint({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证编译**

Run: `flutter build web --release 2>&1 | tail -5`
Expected: √ Built build\web

- [ ] **Step 3: Commit**

```bash
git add lib/core/word_drag/pages/word_drag_page.dart
git commit -m "refactor(word_drag): 重构为 ConsumerWidget + ChangeNotifier"
```

---

## Task 6: 更新导出文件

**Files:**
- Modify: `lib/core/word_drag/word_drag.dart`

- [ ] **Step 1: 更新导出**

```dart
// lib/core/word_drag/word_drag.dart

// Core word_drag module - 弹性拖动背单词

export 'models/word.dart';
export 'providers/word_drag_state.dart';
export 'providers/word_drag_notifier.dart';
export 'providers/draggable_word_card_controller.dart';
export 'widgets/draggable_word_card.dart';
export 'widgets/word_card_content.dart';
export 'pages/word_drag_page.dart';
export 'pages/word_detail_page.dart';
```

- [ ] **Step 2: 验证编译**

Run: `flutter build web --release 2>&1 | tail -5`
Expected: √ Built build\web

- [ ] **Step 3: Commit**

```bash
git add lib/core/word_drag/word_drag.dart
git commit -m "chore(word_drag): 更新导出文件"
```

---

## Task 7: 清理旧文件

**Files:**
- Delete: `lib/core/word_drag/widgets/delete_zone.dart` (功能已合并到 WordDragPage)

- [ ] **Step 1: 删除旧文件**

```bash
rm lib/core/word_drag/widgets/delete_zone.dart
git add -A
git commit -m "chore(word_drag): 删除已合并的 delete_zone.dart"
```

---

## 验证清单

- [ ] 所有手势都能正确触发
- [ ] 标新区进入/离开正确
- [ ] 删除区进入/离开正确
- [ ] 左滑标记"稍后复习"正确
- [ ] 上滑跳转到详情页
- [ ] 右滑未进区域跳转到详情页
- [ ] 区域提示正确显示/隐藏
- [ ] 成功提示正确显示/隐藏
- [ ] 空状态正确显示
- [ ] "再学一遍"按钮正常工作

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-07-worddrag-state-management.md`**

**Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
