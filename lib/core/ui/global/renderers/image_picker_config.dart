// 图片选择配置（自 image_picker_widget.dart 拆出，2026-10-28 N7）

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

/// 图片选择器配置
class ImagePickerConfig {
  /// 裁剪宽度与高度的比例
  final double aspectRatioX;
  final double aspectRatioY;

  /// 裁剪界面标题
  final String cropTitle;

  /// 是否锁定宽高比
  final bool lockAspectRatio;

  /// 初始宽高比预设
  final CropAspectRatioPreset aspectRatioPreset;

  /// 工具栏颜色
  final Color? toolbarColor;

  /// 是否显示裁剪功能
  final bool enableCrop;

  const ImagePickerConfig({
    this.aspectRatioX = 16,
    this.aspectRatioY = 9,
    this.cropTitle = '裁剪图片',
    this.lockAspectRatio = false,
    this.aspectRatioPreset = CropAspectRatioPreset.original,
    this.toolbarColor,
    this.enableCrop = true,
  });

  /// Banner 配置 (16:9)
  factory ImagePickerConfig.banner({Color? toolbarColor}) {
    return ImagePickerConfig(
      aspectRatioX: 16,
      aspectRatioY: 9,
      cropTitle: '裁剪Banner',
      toolbarColor: toolbarColor,
    );
  }

  /// 正方形配置 (1:1)
  factory ImagePickerConfig.square({Color? toolbarColor}) {
    return ImagePickerConfig(
      aspectRatioX: 1,
      aspectRatioY: 1,
      cropTitle: '裁剪图片',
      toolbarColor: toolbarColor,
    );
  }

  /// 自由裁剪配置
  factory ImagePickerConfig.free({Color? toolbarColor}) {
    return ImagePickerConfig(
      aspectRatioX: 1,
      aspectRatioY: 1,
      cropTitle: '裁剪图片',
      lockAspectRatio: false,
      toolbarColor: toolbarColor,
    );
  }

  /// 获取宽高比
  double get aspectRatio => aspectRatioX / aspectRatioY;

  /// 获取宽高比字符串
  String get aspectRatioString {
    final ratio = aspectRatio;
    if ((ratio - 16 / 9).abs() < 0.1) return '16:9';
    if ((ratio - 4 / 3).abs() < 0.1) return '4:3';
    if ((ratio - 21 / 9).abs() < 0.1) return '21:9';
    if ((ratio - 1).abs() < 0.1) return '1:1';
    return '${ratio.toStringAsFixed(1)}:1';
  }
}
