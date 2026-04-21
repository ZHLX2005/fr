import 'dart:ui' as ui;

import 'novel_paginator.dart';

class NovelRenderPage {
  const NovelRenderPage({
    required this.page,
    this.picture,
    this.image,
  });

  final NovelPage page;
  final ui.Picture? picture;
  final ui.Image? image;

  int get start => page.start;
  int get end => page.end;
  String get text => page.text;

  NovelRenderPage copyWith({
    NovelPage? page,
    ui.Picture? picture,
    ui.Image? image,
    bool clearPicture = false,
    bool clearImage = false,
  }) {
    return NovelRenderPage(
      page: page ?? this.page,
      picture: clearPicture ? null : (picture ?? this.picture),
      image: clearImage ? null : (image ?? this.image),
    );
  }
}
