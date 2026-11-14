import 'package:flutter/foundation.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../api/mnws/mnws.dart';
import '../../../../api/nxkv/nxkv_client.dart';
import '../mnws_app_views.dart';

/// nx-kv 界面的**唯一数据入口**。
///
/// 界面里没有一处手写 HTTP：所有请求都是生成客户端（`package:nx_kv_client`）的方法，
/// 端点、应用标识、设备令牌由 [MnWsEndpoint] 负责带上 —— 这就是「fr 只维护 UI」的
/// 字面意思。nx-kv 加一条 action，这里 `flutter pub upgrade nx_kv_client` 之后
/// 就能调用，界面代码不用改协议。
///
/// 为什么是 ChangeNotifier 而不是几个 Riverpod provider：
/// 这页的状态是**一处活的会话**（连的是哪台机器、当前选的是哪个主题、契约对不对得上），
/// 三个视图共享同一份，用 provider 拆开反而要维护「谁先刷新」的顺序。
class NxKvController extends ChangeNotifier {
  NxKvController({required this.target, required this.endpoint})
      : _client = NxKvApi(pc: target.bridgeId).bind(endpoint);

  /// 点的是哪台 PC 上的 nx-kv。
  final MnWsAppTarget target;

  final MnWsEndpoint endpoint;
  final kv.NxKvClientApi _client;

  /// 生成客户端的直接引用（视图只碰这个）。
  kv.NxKvClientApi get client => _client;

  // ── 主题清单 ──────────────────────────────────────────────

  List<kv.LocaltaskListTopic> topics = const [];
  kv.LocaltaskListSettings? settings;
  bool loading = true;
  String? error;

  /// 当前选中的主题键（三个视图共享：「队列」页选的、「主题」页点的，是同一个）。
  String? selectedKey;

  kv.LocaltaskListTopic? get selected {
    for (final t in topics) {
      if (t.key == selectedKey) return t;
    }
    return null;
  }

  /// 有活可领的主题优先（进页面时默认停在最该看的那个上）。
  String? get defaultKey {
    for (final t in topics) {
      if (t.pending > 0) return t.key;
    }
    for (final t in topics) {
      if (t.claimed > 0) return t.key;
    }
    return topics.isEmpty ? null : topics.first.key;
  }

  // ── 契约对账 ──────────────────────────────────────────────

  /// 端侧生成物里的指纹（编译期常量）。
  String get localHash => kv.contractHash;
  String get localVersion => kv.contractVersion;

  /// 服务端报的契约（打开页面时拉一次）。
  kv.ContractOutput? remoteContract;

  /// 不一致时的一句人话；null = 一致。
  String? drift;

  bool contractLoading = true;
  String? contractError;

  // ── 加载 ──────────────────────────────────────────────────

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final list = await _client.localtaskList();
      topics = list.topics;
      settings = list.settings;
      selectedKey ??= defaultKey;
      // 选中的主题可能被 prune 掉了：回落到默认
      if (selected?.key == null) selectedKey = defaultKey;
    } catch (e) {
      error = humanize(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> checkContract() async {
    contractLoading = true;
    contractError = null;
    notifyListeners();
    try {
      final c = await _client.systemContract();
      remoteContract = c;
      drift = c.hash == localHash
          ? null
          : '端侧跑在旧契约上：本地 $localHash（$localVersion）· 服务端 ${c.hash}（${c.version}）'
              '—— 跑 `flutter pub upgrade nx_kv_client` 拧到服务端那条';
    } catch (e) {
      contractError = humanize(e);
    } finally {
      contractLoading = false;
      notifyListeners();
    }
  }

  /// 一次性把首页需要的两件事都拉回来（主题清单 + 契约）。
  Future<void> bootstrap() async {
    await Future.wait([refresh(), checkContract()]);
  }

  void select(String? key) {
    if (selectedKey == key) return;
    selectedKey = key;
    notifyListeners();
  }

  // ── 动作（全部走生成客户端）────────────────────────────────

  Future<kv.LocaltaskTasksOutput> tasksOf(String key, {String? status}) =>
      _client.localtaskTasks(key, null, status);

  Future<kv.LocaltaskGetOutput> task(int id, String? key) =>
      _client.localtaskGet(id, null, key);

  /// 领一条（HTTP 侧恒为「没活就立刻回」，不会挂住请求）。
  Future<kv.LocaltaskClaimOutput> claim(kv.LocaltaskListTopic topic) =>
      _client.localtaskClaim(topic.cwd, null, true, null);

  Future<kv.LocaltaskDoneOutput> done(int id, String? key, String summary) =>
      _client.localtaskDone(id, null, key, summary);

  Future<kv.LocaltaskReopenOutput> feedback(
    int id,
    String? key, {
    required String kind,
    required String md,
    String? quote,
    String? heading,
  }) =>
      _client.localtaskReopen(id, null, key, null, kind, quote, md, heading, null);

  Future<kv.LocaltaskAddOutput> add(String text, String cwd) =>
      _client.localtaskAdd(text, cwd, null, null, null, null, null, null, null, null, null, null);

  // ── 错误人话 ──────────────────────────────────────────────

  /// 三层错误都要能读：桥的（MnWsException）、契约客户端的（NxKvApiException）、
  /// 其它（网络/JSON）。原文都留着，因为 `--json` 的报错信息往往就是答案。
  static String humanize(Object e) {
    if (e is MnWsException) return e.message;
    if (e is kv.NxKvApiException) return e.message;
    return e.toString();
  }
}
