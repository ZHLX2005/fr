import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/note/convert/convert.dart';
import 'package:xiaodouzi_fr/core/note/core/core.dart';

void main() {
  group('MdToBlock 图片行', () {
    test('整行 ![说明](目标) 落成 ImageType', () {
      final blocks = MdToBlock().parse('![贴图](https://a.test/x.png)');
      expect(blocks, hasLength(1));
      final type = blocks.single.type;
      expect(type, isA<ImageType>());
      expect((type as ImageType).src, 'https://a.test/x.png');
      expect(type.caption, '贴图');
    });

    test('附件 id 原样保留，判定留给渲染端', () {
      // 服务端返回的片段就是这种形式：不透明 id 不带扩展名
      final blocks = MdToBlock().parse('![截图](3f2a9c1d4b5e6f708192a3b4c5d6e7f8)');
      final type = blocks.single.type as ImageType;
      expect(type.src, '3f2a9c1d4b5e6f708192a3b4c5d6e7f8');
      expect(type.caption, '截图');
    });

    test('空说明不给 caption（渲染端自己决定怎么标注）', () {
      final blocks = MdToBlock().parse('![](./a.png)');
      expect((blocks.single.type as ImageType).caption, isNull);
    });

    test('行内混排图片不假装支持，仍是段落', () {
      final blocks = MdToBlock().parse('看图 ![贴图](a.png) 再说');
      expect(blocks.single.type, isNot(isA<ImageType>()));
    });

    test('图片与前后段落各自成块', () {
      final blocks = MdToBlock().parse('上文\n\n![贴图](a.png)\n\n下文');
      expect(blocks, hasLength(3));
      expect(blocks[1].type, isA<ImageType>());
    });
  });
}
