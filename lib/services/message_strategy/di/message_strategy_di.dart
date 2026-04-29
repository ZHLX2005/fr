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
  ];

  final strategies = <String, MessageWidgetStrategy<IMessageData>>{
    for (final s in strategyInstances) s.type: s,
  };

  // 遍历 strategies 通过 createMockData() 构建 mockData
  final mockData = <String, IMessageData>{
    for (final s in strategyInstances) s.type: s.createMockData(),
  };

  getIt.registerSingleton<MessageWidgetFactory>(
    MessageWidgetFactory(strategies, mockData),
  );
}
