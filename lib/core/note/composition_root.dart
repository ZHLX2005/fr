import 'core/models/block_codec.dart';
import 'core/identity/identity_factory.dart';
import 'core/text/inline_format_registry.dart';
import 'core/text/rich_text_codec.dart';
import 'core/type/type_registry.dart';
import 'persistence/note_repository.dart';
import 'widget/block_widget_factory.dart';
import 'widget/di/block_widget_di.dart';

/// 单一组装点——所有 note core 依赖在此构造并暴露。
///
/// 整个应用中只有此处知道如何接线，消费者只取现成实例。
class NoteCompositionRoot {
  final BlockIdentityFactory idFactory;
  final NoteRepository noteRepository;
  final BlockWidgetFactory widgetFactory;

  const NoteCompositionRoot._({
    required this.idFactory,
    required this.noteRepository,
    required this.widgetFactory,
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
    return NoteCompositionRoot._(
      idFactory: idFactory,
      noteRepository: NoteRepository(blockCodec, idFactory),
      widgetFactory: BlockWidgetBuilder().build(),
    );
  }
}

/// 全局唯一组装实例。应用启动即完成。
final noteCompositionRoot = NoteCompositionRoot.create();
