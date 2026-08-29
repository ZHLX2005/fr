// test/core/chess/widgets/chess_piece_widget_test.dart
//
// ChessPiece 单图渲染 —— 用 MemoryImage 避免依赖具体资源（不需要任何网络 / 资产）。
// 使用已知最小合法 1x1 透明 PNG。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_piece.dart';

/// 1x1 透明 PNG（已通过 ImageDescriptor 验证合法）。
final Uint8List _kPngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG sig
  0x00, 0x00, 0x00, 0x0D, // IHDR length
  0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, // width=1
  0x00, 0x00, 0x00, 0x01, // height=1
  0x08, 0x06, 0x00, 0x00, 0x00, // bit depth=8, color type=6 (RGBA)
  0x1F, 0x15, 0xC4, 0x89, // CRC
  0x00, 0x00, 0x00, 0x0D, // IDAT length
  0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, // IEND length=0
  0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('ChessPiece 渲染一个 size x size 的 Image', (tester) async {
    const size = 48.0;
    final image = MemoryImage(_kPngBytes);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ChessPiece(
            image: image,
            size: size,
          ),
        ),
      ),
    );
    // 等图片加载（消除 codec 异步等待）
    await tester.pumpAndSettle();

    final imgFinder = find.byType(Image);
    expect(imgFinder, findsOneWidget);
    final img = tester.widget<Image>(imgFinder);
    expect(img.image, image);
    expect(img.width, size);
    expect(img.height, size);
    expect(img.fit, BoxFit.contain);
  });
}