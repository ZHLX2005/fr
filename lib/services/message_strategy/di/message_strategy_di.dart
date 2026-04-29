import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../strategies/strategies.dart';
import '../factory/factory.dart';

final GetIt getIt = GetIt.instance;

/// Register all message strategies and factory
void registerMessageStrategies() {
  final strategies = <String, MessageWidgetStrategy<IMessageData>>{
    TextMessageWidgetStrategy().type: TextMessageWidgetStrategy(),
    MarkdownMessageWidgetStrategy().type: MarkdownMessageWidgetStrategy(),
    HtmlMessageWidgetStrategy().type: HtmlMessageWidgetStrategy(),
  };

  getIt.registerSingleton<MessageWidgetFactory>(
    MessageWidgetFactory(strategies),
  );
}
