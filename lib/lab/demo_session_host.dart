// lib/lab/demo_session_host.dart
//
// Demo 会话托管者——demo 运行时 scope 的基础设施层。
// 设计全文：docs/superpowers/specs/2026-10-12-demo-scope-design.md
//
// 背景：demo 页面经 MaterialPageRoute 打开，pop 即 State 销毁。把连接 / 房间 /
// 长计时这类「页面外仍应存续」的状态放在页面 State 里的 demo（如 remotetype），
// 离开页面 = 主动掐断。本文件提供第三种归属：
//
//   page（默认，不经本文件） < session（这里托管，可 reattach） < global
//
// host 只管生死（创建 / 复用 / 回收 / 前后台转发），不感知任何具体会话类型，
// 也不做跨 session 通信——业务归 session 对象自己。

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../app_lifecycle/app_foreground.dart';
import 'lab_container.dart' show DemoScope, demoRegistry;

/// detached 会话的空闲回收阈值：超过没人认领即销毁（安全阀，防 70 个
/// demo 各留一条僵尸连接）。改这里要同步 spec §3 生命周期表。
const Duration kSessionIdleReapTimeout = Duration(minutes: 15);

/// 空闲回收检查周期。
const Duration kSessionReapCheckInterval = Duration(minutes: 5);

/// 一个被托管的 demo 会话条目。[state] 对 host 完全不透明。
class HostedSession {
  HostedSession({
    required this.slug,
    required this.state,
    required Future<void> Function() onDispose,
    Future<void> Function()? onAppBackground,
    Future<void> Function()? onAppForeground,
  })  : onDispose = onDispose,
        onAppBackground = onAppBackground,
        onAppForeground = onAppForeground;

  /// 稳定身份 = demo slug：一个 demo 至多一条活动会话。同 demo 的多个入口
  /// （lab 网格 / 游戏中心 / 钉选底栏 / fr:// 深链 / 时间页）共享同一条——
  /// host 是唯一真相，入口决定不了生命周期。
  final String slug;

  /// demo 自己的会话对象（连接、房间、计时器…）。host 不感知其类型。
  final Object state;

  /// 唯一销毁入口：drop / 空闲回收时调用。应幂等（host 不重复调用，
  /// 但 session 实现自行兜底更稳）。
  Future<void> Function() onDispose;

  /// 可选钩子：app 退到后台（paused）。会话在此暂停周期性工作。
  Future<void> Function()? onAppBackground;

  /// 可选钩子：app 回到前台（resumed）。连接型会话在此做健康检查 + 自动重连
  /// （remotetype 的 `keepTypingUi` 重连就是这里该调的东西）。
  Future<void> Function()? onAppForeground;

  /// 非 null = 页面已退出、暂无人认领（attach 会清零）。空闲回收从此刻起算。
  DateTime? detachedAt;

  bool get detached => detachedAt != null;
}

/// Demo 会话托管者。
///
/// 用法（session scope 的 demo 页面）：
/// ```dart
/// // initState / 首次进入：
/// _session = demoSessionHost.attach(
///   widget.demo.slug,
///   () => RtSession(...),
///   onDispose: () => session.dispose(),
///   onAppForeground: () => _reconnectIfNeeded(),
/// );
/// // 页面 dispose：只 detach，绝不 session.dispose()。
/// demoSessionHost.detach(widget.demo.slug);
/// // 用户显式「断开」：
/// await demoSessionHost.drop(widget.demo.slug);
/// ```
class DemoSessionHost {
  final Map<String, HostedSession> _sessions = {};

  /// 空闲回收维护协程。首次 attach 拉起，会话清空后自停。
  Timer? _reapTimer;

  /// [maintenance] 仅供测试关掉：周期 timer 会拖住测试 isolate 的退出，
  /// 纯单测一律 `DemoSessionHost(maintenance: false)`，回收走显式
  /// [reapIdle] 或 fakeAsync 用例。
  ///
  /// [nowSource] 时钟缝隙：fakeAsync 只伪造 Timer/microtask、伪造不了
  /// `DateTime.now()`，fakeAsync 用例须注入虚拟时间源，否则 detach 与
  /// 回收判定用的是两个不相关的时间轴。
  DemoSessionHost({
    @visibleForTesting bool maintenance = true,
    @visibleForTesting DateTime Function()? nowSource,
  })  : _maintenance = maintenance,
        _nowSource = nowSource ?? DateTime.now;
  final bool _maintenance;
  final DateTime Function() _nowSource;

  /// 维护协程是否在跑（测试用）。
  @visibleForTesting
  bool get reapTimerActive => _reapTimer != null;

  void _ensureReapTimer() {
    if (!_maintenance || _reapTimer != null) return;
    _reapTimer = Timer.periodic(kSessionReapCheckInterval, (_) {
      unawaited(reapIdle(now: _nowSource()));
    });
  }

  void _maybeStopReapTimer() {
    if (_reapTimer != null && _sessions.isEmpty) {
      _reapTimer!.cancel();
      _reapTimer = null;
    }
  }

  // AppForeground → 前后台广播的联动。懒挂：首次 attach 时装上，幂等——
  // 不占 bootstrap 名额，没人托管会话时 host 完全静默。
  bool _foregroundLinked = false;

  /// 广播派发中标记：前台钩子里若再触发 attach（罕见）不会重入死循环，
  /// 主要防测试里同步翻转造成的重入。
  bool _dispatching = false;

  void _ensureForegroundLink() {
    if (_foregroundLinked) return;
    _foregroundLinked = true;
    AppForeground.isForeground.addListener(_onAppForegroundFlip);
  }

  void _onAppForegroundFlip() {
    if (_dispatching) return;
    _dispatching = true;
    final notify = AppForeground.value
        ? notifyAppForeground()
        : notifyAppBackground();
    notify.whenComplete(() => _dispatching = false);
  }

  /// 全部活动会话（含 detached）。只读视图，调试 / 审计用。
  Map<String, HostedSession> get active => Map.unmodifiable(_sessions);

  int get count => _sessions.length;

  /// 取回已托管会话对象；不存在返回 null。
  /// 类型不匹配是编程错误（assert 拦截；release 下 as 抛 TypeError）。
  T? get<T extends Object>(String slug) {
    final hs = _sessions[slug];
    if (hs == null) return null;
    assert(
      hs.state is T,
      'slug=$slug 托管的 state 是 ${hs.state.runtimeType}，与请求的 $T 不符',
    );
    return hs.state as T;
  }

  /// 页面进入时调用：无则创建托管；有则复用同一对象（**绝不重建**），
  /// 清除 detached 并用最新闭包刷新钩子——当前在场的页面才是权威 UI。
  ///
  /// 钩子闭包应指向会话对象或当前页面 State；旧页面的闭包随 reattach 被丢弃。
  T attach<T extends Object>(
    String slug,
    T Function() create, {
    required Future<void> Function() onDispose,
    Future<void> Function()? onAppBackground,
    Future<void> Function()? onAppForeground,
  }) {
    _ensureForegroundLink();
    _ensureReapTimer();
    // 契约防腐蚀：只有声明 session/global scope 的 demo 才能挂托管。
    // 「行为迁了、声明没跟」（或反过来）在这里炸出来，而不是留到
    // 审计文档对不上。demo 未注册（测试桩）时放行。
    assert(
      demoRegistry.getBySlug(slug)?.scope != DemoScope.page,
      'slug=$slug 的 demo 声明是 page scope，不能挂进 host 托管——'
      '先在 DemoPage 子类 override scope => DemoScope.session',
    );
    final existing = _sessions[slug];
    if (existing != null) {
      assert(
        existing.state is T,
        'slug=$slug 已托管 ${existing.state.runtimeType}，与请求的 $T 不符',
      );
      existing
        ..onDispose = onDispose
        ..onAppBackground = onAppBackground
        ..onAppForeground = onAppForeground
        ..detachedAt = null;
      return existing.state as T;
    }
    final state = create();
    _sessions[slug] = HostedSession(
      slug: slug,
      state: state,
      onDispose: onDispose,
      onAppBackground: onAppBackground,
      onAppForeground: onAppForeground,
    );
    return state;
  }

  /// 页面退出（dispose）时调用：只标记 detached，不销毁——会话继续存活，
  /// 等 reattach、空闲回收或显式 drop。对不存在的 slug 幂等。
  /// [now] 供测试钉时钟（与 [reapIdle] 的 now 同一缝隙）。
  void detach(String slug, {DateTime? now}) {
    _sessions[slug]?.detachedAt = now ?? _nowSource();
  }

  /// 用户显式「断开 / 停止」：真正销毁并移除。对不存在的 slug 幂等。
  Future<void> drop(String slug) async {
    final hs = _sessions.remove(slug);
    if (hs == null) return;
    await _disposeQuietly(hs);
    _maybeStopReapTimer();
  }

  /// 空闲回收：detached 超过 [timeout] 的会话逐个销毁（attached 的永不动）。
  ///
  /// 单个 onDispose 抛错不影响其余回收——回收路径上没有可恢复动作，
  /// 死连接销毁失败也无妨，故错误被吞。返回被回收的 slug 列表（日志/测试用）。
  /// 维护协程按 [kSessionReapCheckInterval] 周期调它；测试可传 now 钉时钟。
  Future<List<String>> reapIdle({
    Duration timeout = kSessionIdleReapTimeout,
    DateTime? now,
  }) async {
    final deadline = (now ?? DateTime.now()).subtract(timeout);
    final stale = [
      for (final hs in _sessions.values)
        if (hs.detachedAt != null && hs.detachedAt!.isBefore(deadline)) hs,
    ];
    for (final hs in stale) {
      _sessions.remove(hs.slug);
      await _disposeQuietly(hs);
    }
    _maybeStopReapTimer();
    return stale.map((hs) => hs.slug).toList();
  }

  /// app 退到后台：向全部会话转发钩子。
  ///
  /// P0 仅供测试直调；P1 接入后由 host 订阅 `AppForeground.isForeground`
  /// 统一转发（口径沿用 app_foreground.dart：只认 paused/resumed）。
  Future<void> notifyAppBackground() async {
    for (final hs in _sessions.values) {
      await hs.onAppBackground?.call();
    }
  }

  /// app 回到前台：向全部会话转发钩子（连接型在此自动重连）。
  Future<void> notifyAppForeground() async {
    for (final hs in _sessions.values) {
      await hs.onAppForeground?.call();
    }
  }

  Future<void> _disposeQuietly(HostedSession hs) async {
    try {
      await hs.onDispose();
    } catch (_) {
      // 销毁失败不阻断 host：回收路径没有可恢复动作。
    }
  }
}

/// 全局托管者单例——与 [demoRegistry] 同款的全局 final 惯例。
final demoSessionHost = DemoSessionHost();
