import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xiaodouzi_fr/core/note/core/core.dart';
import 'package:xiaodouzi_fr/core/note/persistence/note_repository.dart';
import 'package:xiaodouzi_fr/core/note/persistence/toml_codec.dart';

void main() {
  late Directory tempDir;
  late BlockCodec codec;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('note_repo_test_');
    codec = _buildCodec();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  NoteRepository newRepo() => NoteRepository(
        codec,
        tomlCodec: TomlCodec(),
        notesDirProvider: () async => tempDir,
      );

  test('save then read roundtrips a block tree as .toml', () async {
    final repo = newRepo();
    final block = Block(
      id: 'r1',
      type: const ParagraphType(),
      content: RichText.text('hello toml'),
    );

    await repo.saveNote(block);

    final tomlFile = File(p.join(tempDir.path, 'r1.toml'));
    expect(await tomlFile.exists(), isTrue);
    final jsonFile = File(p.join(tempDir.path, 'r1.json'));
    expect(await jsonFile.exists(), isFalse);

    final loaded = await repo.readNote('r1');
    expect(loaded, isNotNull);
    expect(loaded!.content.toPlainText(), 'hello toml');
    expect(loaded.type, isA<ParagraphType>());
  });

  test('listAllNotes sees .toml files and returns NoteInfo', () async {
    final repo = newRepo();
    await repo.saveNote(Block(
      id: 'r2',
      type: const ParagraphType(),
      content: RichText.text('first'),
    ));
    await repo.saveNote(Block(
      id: 'r3',
      type: const ParagraphType(),
      content: RichText.text('second'),
    ));

    final notes = await repo.listAllNotes();
    expect(notes.length, 2);
    expect(notes.map((n) => n.id).toSet(), {'r2', 'r3'});
  });

  test('deleteNote removes the .toml file', () async {
    final repo = newRepo();
    await repo.saveNote(Block(
      id: 'r4',
      type: const ParagraphType(),
      content: RichText.text('gone'),
    ));
    await repo.deleteNote('r4');
    expect(await File(p.join(tempDir.path, 'r4.toml')).exists(), isFalse);
  });

  test('migrates legacy .json into .toml on first directory access', () async {
    // Place a legacy .json directly (simulating a pre-migration note)
    const jsonStr = '{"id":"legacy-1","type":"paragraph",'
        '"content":{"spans":[{"text":"legacy content"}]},'
        '"children":[],"data":{},"properties":{},'
        '"created_at":1,"updated_at":2}';
    await File(p.join(tempDir.path, 'legacy-1.json')).writeAsString(jsonStr);

    final repo = newRepo();
    final notes = await repo.listAllNotes();

    expect(notes.any((n) => n.id == 'legacy-1'), isTrue);
    expect(await File(p.join(tempDir.path, 'legacy-1.json')).exists(), isFalse);
    final loaded = await repo.readNote('legacy-1');
    expect(loaded!.content.toPlainText(), 'legacy content');
  });

  test('encodeToml then decodeToml roundtrips a block tree', () async {
    final repo = NoteRepository(
      codec,
      tomlCodec: TomlCodec(),
      notesDirProvider: () async => tempDir,
    );
    final block = Block(
      id: 'toml-rt',
      type: const HeadingType(),
      content: RichText.text('标题'),
    );

    final toml = repo.encodeToml(block);
    expect(toml, contains('id = '));
    expect(toml, contains("type = 'heading'"));

    final restored = repo.decodeToml(toml);
    expect(restored, isNotNull);
    expect(restored!.id, 'toml-rt');
    expect(restored.content.toPlainText(), '标题');
  });

  test('decodeToml returns null on invalid TOML', () {
    final repo = NoteRepository(codec, tomlCodec: TomlCodec());
    expect(repo.decodeToml('this is not = valid = toml {{{'), isNull);
  });
}

BlockCodec _buildCodec() {
  final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
  final formatRegistry =
      InlineFormatRegistry(InlineFormatRegistrar().createFactories());
  final richTextCodec = RichTextCodec(formatRegistry);
  return BlockCodec(typeRegistry, richTextCodec);
}
