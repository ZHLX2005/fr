import 'dart:async';
import 'package:flutter/material.dart';
import '../models/word.dart';
import 'word_drag_state.dart';

/// WordDrag 状态管理通知器
class WordDragNotifier extends ChangeNotifier {
  WordDragState _state = WordDragState.initial();
  WordDragState get state => _state;

  VoidCallback? _onNavigateToDetail;

  // ==================== 拖动事件方法 ====================

  /// 拖动开始
  void onDragStart() {
    _state = _state.copyWith(isDragging: true);
    notifyListeners();
  }

  /// 拖动更新
  void onDragUpdate(Offset offset, Size screenSize) {
    _state = _state.copyWith(cardOffset: offset);
    _updateZoneState(screenSize);
    notifyListeners();
  }

  // ==================== 滑动完成回调 ====================

  /// 上滑完成 (跳过)
  void onSwipeUp() {
    _skipWord();
  }

  /// 左滑完成 (稍后复习)
  void onSwipeLeft() {
    _markAsReviewed();
  }

  /// 右滑完成 (标记为已掌握)
  void onSwipeRight() {
    _markAsMastered();
  }

  /// 回弹
  void onSpringBack() {
    _springBack();
  }

  /// 进入分类桶模式 (下滑 > 300px)
  void enterFolderMode() {
    _state = _state.copyWith(isFolderMode: true);
    notifyListeners();
  }

  /// 退出分类桶模式
  void exitFolderMode() {
    _state = _state.copyWith(
      isFolderMode: false,
      activeCategoryBucketId: null,
    );
    _resetZoneAndHints();
    notifyListeners();
  }

  /// 更新激活的分类桶
  void updateActiveBucket(String? bucketId) {
    _state = _state.copyWith(activeCategoryBucketId: bucketId);
    notifyListeners();
  }

  /// 选择分类桶
  void selectBucket(String bucketId) {
    // 可以在这里添加将单词添加到对应分类的逻辑
    _state = _state.copyWith(
      isFolderMode: false,
      activeCategoryBucketId: null,
    );
    _moveToNextWord();
  }

  // ==================== 区域检测方法 ====================

  /// 更新区域状态
  void _updateZoneState(Size screenSize) {
    final cardCenter = _getCardCenter(screenSize);
    final markZoneOpacity = _calculateZoneOpacity(cardCenter, screenSize);
    final deleteZoneOpacity = _calculateZoneOpacity(
      cardCenter,
      screenSize,
      isDeleteZone: true,
    );

    ZoneType activeZone = ZoneType.none;
    if (markZoneOpacity > 0) {
      activeZone = ZoneType.mark;
    } else if (deleteZoneOpacity > 0) {
      activeZone = ZoneType.delete;
    }

    _state = _state.copyWith(
      activeZone: activeZone,
      markZoneOpacity: markZoneOpacity,
      deleteZoneOpacity: deleteZoneOpacity,
    );
  }

  /// 计算区域透明度
  double _calculateZoneOpacity(Offset offset, Size screenSize, {bool isDeleteZone = false}) {
    final zone = isDeleteZone ? _getDeleteZone(screenSize) : _getMarkZone(screenSize);

    // 计算距离
    final distance = (offset - zone.center).distance;
    final maxDistance = screenSize.width * 0.4;

    // 基于距离计算透明度
    double opacity = 1.0 - (distance / maxDistance).clamp(0.0, 1.0);

    // 只有在区域内或接近区域时才显示
    if (!zone.inflate(50).contains(offset)) {
      opacity = opacity * 0.3;
    }

    return opacity.clamp(0.0, 1.0);
  }

  /// 获取卡片中心位置
  Offset _getCardCenter(Size screenSize) {
    // 假设卡片在屏幕中心，偏移量应用于卡片中心
    final cardCenterX = screenSize.width / 2 + _state.cardOffset.dx;
    final cardCenterY = screenSize.height * 0.4 + _state.cardOffset.dy;
    return Offset(cardCenterX, cardCenterY);
  }

  // ==================== 区域操作方法 ====================

  /// 用户确认区域操作
  void onZoneConfirmed(ZoneType zone) {
    switch (zone) {
      case ZoneType.mark:
        _markAsNew();
        break;
      case ZoneType.delete:
        _deleteWord();
        break;
      case ZoneType.none:
        _springBack();
        break;
    }
  }

  /// 标记为新词
  void _markAsNew() {
    if (_state.currentWord != null) {
      final updatedWords = List<Word>.from(_state.words);
      final currentWord = updatedWords[_state.currentIndex];
      final index = updatedWords.indexOf(currentWord);
      if (index >= 0) {
        updatedWords[index] = Word(
          id: currentWord.id,
          text: currentWord.text,
          phonetic: currentWord.phonetic,
          definition: currentWord.definition,
          example: currentWord.example,
          mastered: false,
        );
      }
      _state = _state.copyWith(
        words: updatedWords,
        showMarkNewSuccessHint: true,
      );
      notifyListeners();
      _hideHintAfterDelay(() {
        _state = _state.copyWith(showMarkNewSuccessHint: false);
        notifyListeners();
      });
      _moveToNextWord();
    }
  }

  /// 删除单词
  void _deleteWord() {
    if (_state.words.length > 1) {
      final updatedWords = List<Word>.from(_state.words);
      updatedWords.removeAt(_state.currentIndex);
      _state = _state.copyWith(
        words: updatedWords,
        showDeleteSuccessHint: true,
      );
      notifyListeners();
      _hideHintAfterDelay(() {
        _state = _state.copyWith(showDeleteSuccessHint: false);
        notifyListeners();
      });
      _ensureValidIndex();
      _resetZoneAndHints();
    } else {
      _springBack();
    }
  }

  /// 标记稍后复习
  void _markAsReviewed() {
    _state = _state.copyWith(showMarkSuccessHint: true);
    notifyListeners();
    _hideHintAfterDelay(() {
      _state = _state.copyWith(showMarkSuccessHint: false);
      notifyListeners();
    });
    _moveToNextWord();
  }

  /// 标记为已掌握 (右滑)
  void _markAsMastered() {
    if (_state.currentWord != null) {
      final updatedWords = List<Word>.from(_state.words);
      final currentWord = updatedWords[_state.currentIndex];
      final index = updatedWords.indexOf(currentWord);
      if (index >= 0) {
        updatedWords[index] = Word(
          id: currentWord.id,
          text: currentWord.text,
          phonetic: currentWord.phonetic,
          definition: currentWord.definition,
          example: currentWord.example,
          mastered: true,
        );
      }
      _state = _state.copyWith(
        words: updatedWords,
        showMasteredSuccessHint: true,
      );
      notifyListeners();
      _hideHintAfterDelay(() {
        _state = _state.copyWith(showMasteredSuccessHint: false);
        notifyListeners();
      });
      _moveToNextWord();
    }
  }

  /// 跳过当前单词 (上滑)
  void _skipWord() {
    _moveToNextWord();
  }

  // ==================== 导航回调 ====================

  /// 设置导航到详情的回调
  void setNavigateCallback(VoidCallback callback) {
    _onNavigateToDetail = callback;
  }

  /// 导航到详情页
  void _navigateToDetail() {
    _state = _state.copyWith(showDetails: true);
    notifyListeners();
    _onNavigateToDetail?.call();
  }

  // ==================== 辅助方法 ====================

  /// 回弹
  void _springBack() {
    _state = _state.copyWith(
      cardOffset: Offset.zero,
      isDragging: false,
      isFolderMode: false,
      activeCategoryBucketId: null,
    );
    _resetZoneAndHints();
    notifyListeners();
  }

  /// 重置区域和提示
  void _resetZoneAndHints() {
    _state = _state.copyWith(
      activeZone: ZoneType.none,
      markZoneOpacity: 0.0,
      deleteZoneOpacity: 0.0,
      showMarkSuccessHint: false,
      showMarkNewSuccessHint: false,
      showMasteredSuccessHint: false,
      showDeleteSuccessHint: false,
    );
    notifyListeners();
  }

  /// 确保索引有效
  void _ensureValidIndex() {
    if (_state.currentIndex >= _state.words.length) {
      _state = _state.copyWith(
        currentIndex: _state.words.isNotEmpty ? _state.words.length - 1 : 0,
      );
      notifyListeners();
    }
  }

  /// 延迟隐藏提示
  void _hideHintAfterDelay(VoidCallback callback) {
    Future.delayed(const Duration(milliseconds: 800), () {
      callback();
    });
  }

  /// 移动到下一个单词
  void _moveToNextWord() {
    _state = _state.copyWith(
      cardOffset: Offset.zero,
      isDragging: false,
      currentIndex: _state.currentIndex + 1,
    );
    _resetZoneAndHints();
    _ensureValidIndex();
    notifyListeners();
  }

  /// 获取标新区域
  Rect _getMarkZone(Size screenSize) {
    return Rect.fromLTWH(
      screenSize.width - 100,
      screenSize.height * 0.15,
      80,
      screenSize.height * 0.25,
    ).inflate(30);
  }

  /// 获取删除区区域
  Rect _getDeleteZone(Size screenSize) {
    return Rect.fromLTWH(
      screenSize.width - 100,
      screenSize.height * 0.60,
      80,
      screenSize.height * 0.25,
    ).inflate(30);
  }

  // ==================== 外部调用方法 ====================

  /// 详情页完成
  void onDetailPageComplete() {
    _state = _state.copyWith(
      showDetails: false,
      cardOffset: Offset.zero,
      isDragging: false,
      isFolderMode: false,
      activeCategoryBucketId: null,
    );
    _resetZoneAndHints();
    notifyListeners();
  }

  /// 重置单词列表
  void resetWords() {
    _state = WordDragState.initial();
    notifyListeners();
  }
}