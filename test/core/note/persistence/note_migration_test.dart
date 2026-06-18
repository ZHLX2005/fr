import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xiaodouzi_fr/core/note/core/core.dart';
import 'package:xiaodouzi_fr/core/note/persistence/note_migration.dart';
import 'package:xiaodouzi_fr/core/note/persistence/toml_codec.dart';

void main() {
  late Directory tempDir;
  late BlockCodec codec;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('note_migration_test_');
    codec = _buildCodec();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migrates a .json note to .toml and deletes the .json', () async {
    final block = Block(
      id: 'old-note-1',
      type: const ParagraphType(),
      content: RichText.text('老笔记内容'),
    );
    final jsonMap = codec.encode(block);
    final jsonFile = File(p.join(tempDir.path, 'old-note-1.json'));
    await jsonFile.writeAsString(jsonEncode(jsonMap));

    final migration = NoteMigration(TomlCodec());
    final count = await migration.migrateIfNeeded(tempDir);

    expect(count, 1);
    expect(await jsonFile.exists(), isFalse);
    final tomlFile = File(p.join(tempDir.path, 'old-note-1.toml'));
    expect(await tomlFile.exists(), isTrue);

    final tomlMap = TomlCodec().decode(await tomlFile.readAsString());
    final restored = codec.decode(tomlMap);
    expect(restored.content.toPlainText(), '老笔记内容');
    expect(restored.type, isA<ParagraphType>());
  });

  test('is idempotent: running twice does nothing the second time', () async {
    final block = Block(
      id: 'old-note-2',
      type: const ParagraphType(),
      content: RichText.text('内容'),
    );
    final jsonFile = File(p.join(tempDir.path, 'old-note-2.json'));
    await jsonFile.writeAsString(jsonEncode(codec.encode(block)));

    final migration = NoteMigration(TomlCodec());
    await migration.migrateIfNeeded(tempDir);
    final secondCount = await migration.migrateIfNeeded(tempDir);

    expect(secondCount, 0);
  });

  test('skips a corrupted .json without deleting it', () async {
    final badJson = File(p.join(tempDir.path, 'broken.json'));
    await badJson.writeAsString('{ this is not valid json');

    final migration = NoteMigration(TomlCodec());
    final count = await migration.migrateIfNeeded(tempDir);

    expect(count, 0);
    expect(await badJson.exists(), isTrue);
  });

  test('does nothing when directory has only .toml files', () async {
    final tomlFile = File(p.join(tempDir.path, 'new.toml'));
    await tomlFile.writeAsString('id = "new"\ntype = "paragraph"\n');

    final migration = NoteMigration(TomlCodec());
    final count = await migration.migrateIfNeeded(tempDir);

    expect(count, 0);
  });
}

BlockCodec _buildCodec() {
  final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
  final formatRegistry =
      InlineFormatRegistry(InlineFormatRegistrar().createFactories());
  final richTextCodec = RichTextCodec(formatRegistry);
  return BlockCodec(typeRegistry, richTextCodec);
}
