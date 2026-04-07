import 'package:flutter/material.dart';
import '../models/word.dart';

/// 区域类型枚举
enum ZoneType {
  none,
  mark,
  delete,
}

/// WordDrag 状态数据类
class WordDragState {
  /// 单词列表
  final List<Word> words;

  /// 当前卡片索引
  final int currentIndex;

  /// 卡片偏移
  final Offset cardOffset;

  /// 是否正在拖动
  final bool isDragging;

  /// 当前激活的区域类型
  final ZoneType activeZone;

  /// 标新区透明度
  final double markZoneOpacity;

  /// 删除区透明度
  final double deleteZoneOpacity;

  /// 左滑标记"稍后复习"成功
  final bool showMarkSuccessHint;

  /// 标新成功
  final bool showMarkNewSuccessHint;

  /// 删除成功
  final bool showDeleteSuccessHint;

  /// 是否显示详情页
  final bool showDetails;

  /// 是否处于分类桶模式 (下滑 > 300px)
  final bool isFolderMode;

  /// 当前激活的分类桶 ID
  final String? activeCategoryBucketId;

  const WordDragState({
    required this.words,
    required this.currentIndex,
    required this.cardOffset,
    required this.isDragging,
    required this.activeZone,
    required this.markZoneOpacity,
    required this.deleteZoneOpacity,
    required this.showMarkSuccessHint,
    required this.showMarkNewSuccessHint,
    required this.showDeleteSuccessHint,
    required this.showDetails,
    required this.isFolderMode,
    required this.activeCategoryBucketId,
  });

  /// 当前单词
  Word? get currentWord {
    if (currentIndex >= 0 && currentIndex < words.length) {
      return words[currentIndex];
    }
    return null;
  }

  /// 是否在标新区
  bool get isInMarkZone => activeZone == ZoneType.mark;

  /// 是否在删除区
  bool get isInDeleteZone => activeZone == ZoneType.delete;

  /// 是否在任意区域
  bool get isInAnyZone => activeZone != ZoneType.none;

  /// 是否有下一个单词
  bool get hasNextWord => words.isNotEmpty && currentIndex < words.length;

  /// 初始状态工厂方法
  factory WordDragState.initial() {
    return WordDragState(
      words: List.from(Word.sampleWords),
      currentIndex: 0,
      cardOffset: Offset.zero,
      isDragging: false,
      activeZone: ZoneType.none,
      markZoneOpacity: 0.0,
      deleteZoneOpacity: 0.0,
      showMarkSuccessHint: false,
      showMarkNewSuccessHint: false,
      showDeleteSuccessHint: false,
      showDetails: false,
      isFolderMode: false,
      activeCategoryBucketId: null,
    );
  }

  /// 不可变数据类 copyWith 方法
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
    bool? isFolderMode,
    String? activeCategoryBucketId,
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
      isFolderMode: isFolderMode ?? this.isFolderMode,
      activeCategoryBucketId: activeCategoryBucketId,
    );
  }
}
