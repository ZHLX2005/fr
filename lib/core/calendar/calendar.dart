/// 日历模块对外入口。
///
/// UI 只从这里拿领域模型与页面；任务读写统一走
/// `core/storage/sqlite` 的 `sqliteCalendarRepositoryProvider`。
library;

export 'domain/calendar_date_utils.dart';
export 'domain/calendar_task.dart';
export 'presentation/calendar_page.dart';
