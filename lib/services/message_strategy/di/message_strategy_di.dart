import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../strategies/strategies.dart';
import '../factory/factory.dart';
import '../panel/panel.dart';
import '../../../api/user/user_auth_service.dart';

final GetIt getIt = GetIt.instance;

/// Register all message strategies and factory
void registerMessageStrategies() {
  final List<MessageWidgetStrategy<IMessageData>> strategyInstances = [
    TextMessageWidgetStrategy(),
    AutoTextMessageWidgetStrategy(),
    TextLinkMessageWidgetStrategy(),
    MarkdownMessageWidgetStrategy(),
    HtmlMessageWidgetStrategy(),
    WaterCapsuleMessageWidgetStrategy(),
    CalendarMessageWidgetStrategy(),
    AskMessageWidgetStrategy(),
    SelectionMessageWidgetStrategy(),
    SmartAccountingMessageWidgetStrategy(),
    BillOverviewMessageWidgetStrategy(),
    ReceiptOcrMessageWidgetStrategy(),
    CardManagerMessageWidgetStrategy(),
    LoginMessageWidgetStrategy(),
    RegisterMessageWidgetStrategy(),
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

  // 卡片交互依赖的全局对象（isRegistered 保护，防热重载重复注册）
  if (!getIt.isRegistered<MessagePanelController>()) {
    getIt.registerSingleton<MessagePanelController>(MessagePanelController());
  }
  if (!getIt.isRegistered<UserAuthService>()) {
    getIt.registerSingleton<UserAuthService>(UserAuthService());
  }
  if (!getIt.isRegistered<RegisterFlowController>()) {
    getIt.registerSingleton<RegisterFlowController>(RegisterFlowController());
  }
}
