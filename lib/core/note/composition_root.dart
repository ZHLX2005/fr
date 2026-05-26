import 'core/core.dart' show BlockCodec;
import 'core/identity/identity.dart' show BlockIdentityFactory;
import 'core/text/text.dart' show InlineFormatRegistrar, InlineFormatRegistry, RichTextCodec;
import 'core/type/type_registry.dart';
import 'persistence/persistence.dart' show NoteRepository;
import 'widget/widget.dart' show BlockWidgetBuilder, BlockWidgetFactory, BlockRenderer;

/// 单一组装点——所有 note core 依赖在此构造并暴露。
///
/// 整个应用中只有此处知道如何接线，消费者只取现成实例。
/// 实例应在 [main] 中通过 [NoteCompositionRoot.create] 创建，
/// 并通过 [NoteRootScope] InheritedWidget 向下传递。
class NoteCompositionRoot {
  final BlockIdentityFactory idFactory;
  final NoteRepository noteRepository;
  final BlockWidgetFactory widgetFactory;
  final BlockRenderer blockRenderer;

  const NoteCompositionRoot._({
    required this.idFactory,
    required this.noteRepository,
    required this.widgetFactory,
    required this.blockRenderer,
  });

  static NoteCompositionRoot create() {
    final idFactory = BlockIdentityFactory();
    final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
    final formatRegistry = InlineFormatRegistry(InlineFormatRegistrar().createFactories());
    final richTextCodec = RichTextCodec(formatRegistry);
    final blockCodec = BlockCodec(
      typeRegistry,
      richTextCodec,
      idFactory: idFactory,
    );
    final widgetFactory = BlockWidgetBuilder().build();
    return NoteCompositionRoot._(
      idFactory: idFactory,
      noteRepository: NoteRepository(blockCodec, idFactory),
      widgetFactory: widgetFactory,
      blockRenderer: BlockRenderer(widgetFactory),
    );
  }
}
