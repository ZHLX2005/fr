import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../strategies/strategies.dart';
import '../factory/factory.dart';
import '../panel/panel.dart';

final GetIt getIt = GetIt.instance;

/// Register all message strategies and factory
void registerMessageStrategies() {
  final List<MessageWidgetStrategy<IMessageData>> strategyInstances = [
    TextMessageWidgetStrategy(),
    TextLinkMessageWidgetStrategy(),
    MarkdownMessageWidgetStrategy(),
    HtmlMessageWidgetStrategy(),
    WaterCapsuleMessageWidgetStrategy(),
    CalendarMessageWidgetStrategy(),
    AskMessageWidgetStrategy(),
    SelectionMessageWidgetStrategy(),
    SmartAccountingMessageWidgetStrategy(),
    BillOverviewMessageWidgetStrategy(),
    CardManagerMessageWidgetStrategy(),
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

  // 全局面板控制器 —— 任意位置可通过 GetIt 取到，操作整个消息面板。
  // isRegistered 保护，防止热重载重复注册。
  if (!getIt.isRegistered<MessagePanelController>()) {
    getIt.registerSingleton<MessagePanelController>(MessagePanelController());
  }
}
