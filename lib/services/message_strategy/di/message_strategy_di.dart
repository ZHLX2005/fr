import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../strategies/strategies.dart';
import '../factory/factory.dart';

final GetIt getIt = GetIt.instance;

/// Register all message strategies and factory
void registerMessageStrategies() {
  final List<MessageWidgetStrategy<IMessageData>> strategyInstances = [
    TextMessageWidgetStrategy(),
    MarkdownMessageWidgetStrategy(),
    HtmlMessageWidgetStrategy(),
    WaterCapsuleMessageWidgetStrategy(),
    CalendarMessageWidgetStrategy(),
    AskMessageWidgetStrategy(),
    SelectionMessageWidgetStrategy(),
  ];

  final strategies = <String, MessageWidgetStrategy<IMessageData>>{};
  final mockData = <String, IMessageData>{};
  for (final s in strategyInstances) {
    final mock = s.createMockData();
    strategies[mock.type] = s;
    mockData[mock.type] = mock;
  }

  getIt.registerSingleton<MessageWidgetFactory>(
    MessageWidgetFactory(strategies, mockData),
  );
}
