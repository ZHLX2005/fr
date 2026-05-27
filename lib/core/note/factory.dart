import 'package:flutter/material.dart' hide RichText;
import 'convert/convert.dart';
import 'core/core.dart';
import 'identity/identity.dart';
import 'persistence/persistence.dart';
import 'widget/widget.dart';

/// Note 模块的 domain facade。
///
/// 封装所有内部服务，对外只暴露领域操作。
/// 消费者通过 [NoteRootScope.of(context).noteRoot] 获取此实例。
class NoteFactory {
  final BlockIdentityFactory _idFactory;
  final NoteRepository _repository;
  final BlockRenderer _renderer;
  final MdToBlock _mdToBlock;

  NoteFactory._({
    required BlockIdentityFactory idFactory,
    required NoteRepository repository,
    required BlockRenderer renderer,
  })  : _idFactory = idFactory,
        _repository = repository,
        _renderer = renderer,
        _mdToBlock = MdToBlock();

  /// 创建并组装 NoteFactory 所需的所有内部服务。
  static NoteFactory create() {
    final idFactory = BlockIdentityFactory();
    final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
    final formatRegistry = InlineFormatRegistry(InlineFormatRegistrar().createFactories());
    final richTextCodec = RichTextCodec(formatRegistry);
    final blockCodec = BlockCodec(typeRegistry, richTextCodec);
    final widgetFactory = BlockWidgetBuilder().build();
    return NoteFactory._(
      idFactory: idFactory,
      repository: NoteRepository(blockCodec),
      renderer: BlockRenderer(widgetFactory),
    );
  }

  // === Identity ===

  String generateId() => _idFactory.generateId();

  // === 块构造 ===

  /// 创建 [Block] 实例，自动生成 ID（除非显式传入）。
  Block createBlock(BlockType type, {
    String? id,
    RichText? content,
    List<Block>? children,
    Map<String, dynamic>? properties,
  }) =>
      Block(
        id: id ?? _idFactory.generateId(),
        type: type,
        content: content,
        children: children,
        properties: properties,
      );

  // === 笔记 CRUD ===

  Future<List<NoteInfo>> listNotes() => _repository.listAllNotes();
  Future<NoteSummary> getNoteSummary() => _repository.getSummary();
  Future<Block?> loadNote(String id) => _repository.readNote(id);
  Future<void> saveNote(Block root) => _repository.saveNote(root);
  Future<void> deleteNote(String id) => _repository.deleteNote(id);
  Future<String> readRawNoteContent(String filePath) => _repository.readRawContent(filePath);

  // === 类型元信息 ===

  /// 所有策略提供的可创建类型列表，供工具栏等 UI 消费。
  List<BlockTypeInfo> get availableTypes => _renderer.typeInfoList;

  // === 渲染 ===

  Widget renderBlock(Block block, {VoidCallback? onToggleTodo, VoidCallback? onTapAddImage}) =>
      _renderer.renderBlockContent(block, onToggleTodo: onToggleTodo, onTapAddImage: onTapAddImage);

  Widget buildEditor(Block block, {required Widget textField, VoidCallback? onToggleTodo}) =>
      _renderer.buildEditor(block, textField: textField, onToggleTodo: onToggleTodo);

  TextStyle? textStyleFor(Block block) => _renderer.textStyleForType(block);

  // === 转换 ===

  List<Block> parseMarkdown(String source) => _mdToBlock.parse(source);
}
