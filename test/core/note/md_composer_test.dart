import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/note/convert/convert.dart';
import 'package:xiaodouzi_fr/core/note/core/core.dart';
import 'package:xiaodouzi_fr/core/note/composer/md_composer.dart';

void main() {
  group('MdListContinuation：回车自动续列表', () {
    TextEditingValue edit(String text, int caret) {
      const f = MdListContinuation();
      return f.formatEditUpdate(
        TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret)),
        TextEditingValue(
          text: '${text.substring(0, caret)}\n${text.substring(caret)}',
          selection: TextSelection.collapsed(offset: caret + 1),
        ),
      );
    }

    test('无序列表：回车带出 `- `', () {
      final v = edit('- 买牛奶', 5);
      expect(v.text, '- 买牛奶\n- ');
      expect(v.selection.baseOffset, v.text.length);
    });

    test('待办清单：回车带出 `- [ ] `', () {
      final v = edit('- [ ] 写验收', 9);
      expect(v.text, '- [ ] 写验收\n- [ ] ');
    });

    test('引用：回车带出 `> `', () {
      final v = edit('> 一句话', 5);
      expect(v.text, '> 一句话\n> ');
    });

    test('有序列表：回车续号（3. 的下一行是 4.）', () {
      final v = edit('3. 第三步', 6);
      expect(v.text, '3. 第三步\n4. ');
    });

    test('缩进保留：子项的回车还在同一层', () {
      final v = edit('  - 子项', 6);
      expect(v.text, '  - 子项\n  - ');
    });

    test('空列表项上回车 = 退出列表（删掉空项）', () {
      final v = edit('- 一条\n- ', 7);
      expect(v.text, '- 一条');
      expect(v.selection.baseOffset, 4, reason: '光标落回上一行末尾');
    });

    test('普通段落：回车不加前缀', () {
      final v = edit('随便写的一行', 6);
      expect(v.text, '随便写的一行\n');
    });

    test('不是「插一个换行」的编辑不动（粘贴/删除/替换都放行）', () {
      const f = MdListContinuation();
      final oldValue = TextEditingValue(text: '- 一条', selection: TextSelection.collapsed(offset: 4));
      // 删两个字符：长度差不是 +1，formatter 不掺和
      final newValue = TextEditingValue(text: '- ', selection: TextSelection.collapsed(offset: 2));
      expect(f.formatEditUpdate(oldValue, newValue).text, '- ');
    });
  });

  group('MdToBlock：图片行', () {
    List<Block> parse(String md) => MdToBlock().parse(md);

    test('整行一张图 → ImageType（附件 id 目标）', () {
      final blocks = parse('![截图](abcdef0123456789abcdef0123456789.png)');
      expect(blocks, hasLength(1));
      final t = blocks.single.type as ImageType;
      expect(t.src, 'abcdef0123456789abcdef0123456789.png');
      expect(t.caption, '截图');
    });

    test('http 图片也解析（通用 markdown，不只认附件 id）', () {
      final blocks = parse('![logo](https://example.com/a.png)');
      expect(blocks.single.type, isA<ImageType>());
      expect((blocks.single.type as ImageType).src, 'https://example.com/a.png');
      expect((blocks.single.type as ImageType).caption, 'logo');
    });

    test('行内混排的图片保持段落文本（不假装支持内联图）', () {
      final blocks = parse('看这张 ![图](abcdef0123456789) 就明白了');
      expect(blocks.single.type, isA<ParagraphType>());
    });

    test('链接（无叹号）不是图片', () {
      final blocks = parse('[说明](abcdef0123456789)');
      expect(blocks.single.type, isA<ParagraphType>());
    });
  });

  group('looksLikeAttachmentFileId', () {
    test('≥16 位 hex 认，带短扩展名也认', () {
      expect(looksLikeAttachmentFileId('abcdef0123456789abcdef0123456789'), isTrue);
      expect(looksLikeAttachmentFileId('abcdef0123456789.png'), isTrue);
    });

    test('URL 与路径不认（判定窄是刻意的）', () {
      expect(looksLikeAttachmentFileId('https://example.com/a.png'), isFalse);
      expect(looksLikeAttachmentFileId('/api/file/content/x'), isFalse);
      expect(looksLikeAttachmentFileId('./local.png'), isFalse);
      expect(looksLikeAttachmentFileId(''), isFalse);
    });
  });

  group('MdRemoteImage：预览里的桥取图片', () {
    testWidgets('字节到位画出图，失败给占位（可点按重试）', (tester) async {
      // 成功路径（key 区分两棵树：State 复用会把 late 字段的 future 带过来）
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MdRemoteImage(
            key: const Key('ok'),
            resolver: (_) async => Uint8List.fromList([1, 2, 3]),
            fileId: 'f',
            alt: '截图',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);

      // 失败路径：占位文案 + 点按重试（resolver 换成永远失败）
      var calls = 0;
      Object? err;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MdRemoteImage(
            key: const Key('fail'),
            resolver: (_) async {
              calls++;
              throw StateError('boom');
            },
            fileId: 'f',
            alt: '截图',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      err = tester.takeException();
      expect(err, isNull, reason: '失败自己降级，不连累整页');

      await tester.tap(find.textContaining('画不出来'));
      await tester.pumpAndSettle();
      expect(calls, 2, reason: '点按重试又取了一次');
    });

    testWidgets('resolver 同步抛错也只落占位', (tester) async {
      // 重试那一拍 Future 生成在 setState 里、下一帧才有人订阅；若错误逃到
      // 源头之外，Dart 会按「未处理异常」上报 —— 线上就是满屏红字。
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MdRemoteImage(
            resolver: (_) {
              throw StateError('校验不过');
            },
            fileId: 'f',
            alt: '',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('画不出来'), findsOneWidget);

      await tester.tap(find.textContaining('画不出来'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '点按重试同样不能炸');
      expect(find.textContaining('画不出来'), findsOneWidget);
    });
  });
}
