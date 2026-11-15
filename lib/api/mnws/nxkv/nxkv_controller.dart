import 'package:flutter/foundation.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../mnws.dart';
import 'nxkv_api.dart';
import 'nxkv_boards.dart';
import 'nxkv_tree.dart';

/// nx-kv 界面的**唯一数据入口**。
///
/// 界面里没有一处手写 HTTP：所有请求都是生成客户端（`package:nx_kv_client`）的方法，
/// 端点、应用标识、设备令牌由 [MnWsEndpoint] 负责带上 —— 这就是「fr 只维护 UI」的
/// 字面意思。nx-kv 加一条 action，这里 `flutter pub upgrade nx_kv_client` 之后
/// 就能调用，界面代码不用改协议。
///
/// ## 为什么它在 `api/` 而不在 `lab/`
///
/// 它没有一行 widget 代码，只把契约客户端编排成「界面能直接用的状态」——
/// 那不是界面。放在 `lab/demos/mnws/nxkv/` 时，它要用 `MnWsAppTarget`，
/// 而那个类型当时长在 UI 文件 `mnws_app_views.dart` 里，于是数据层反向依赖了
/// UI 层：命令行脚本想复用这份编排，就得把整个 material 拖进来。
/// 现在 `lab/demos/mnws/nxkv/` 只剩 widget，这个文件和 [NxKvApi] 一起留在
/// `api/mnws/nxkv/`。
///
/// 为什么是 ChangeNotifier 而不是几个 Riverpod provider：
/// 这页的状态是**一处活的会话**（连的是哪台机器、当前选的是哪个主题、契约对不对得上），
/// 三个视图共享同一份，用 provider 拆开反而要维护「谁先刷新」的顺序。
class NxKvController extends ChangeNotifier {
  NxKvController({required this.target, required this.endpoint})
      : _api = NxKvApi(pc: target.bridgeId),
        _client = NxKvApi(pc: target.bridgeId).bind(endpoint);

  /// 点的是哪台 PC 上的 nx-kv。
  final MnWsAppTarget target;

  final MnWsEndpoint endpoint;

  /// 契约之外的两次读（组清单 / 附件字节）走它。
  final NxKvApi _api;
  final kv.NxKvClientApi _client;

  /// 生成客户端的直接引用（视图只碰这个）。
  kv.NxKvClientApi get client => _client;

  // ── 主题清单 ──────────────────────────────────────────────

  List<kv.LocaltaskListTopic> topics = const [];
  kv.LocaltaskListSettings? settings;
  bool loading = true;
  String? error;

  /// 项目组（看板）清单 —— 侧边栏树的第一层。
  ///
  /// 它是**装饰**：拉不到就是空列表，界面把项目全挂到「未分组」下，
  /// 任务队列照样能用。所以这里没有 `boardsError`，也不参与 loading 判定。
  List<NxKvBoard> boards = const [];

  /// 侧边栏要画的那棵树（组 → 项目 → 主题）。搜索词非空时只留命中的分支。
  List<NxKvTreeNode> tree({String query = ''}) => buildTopicTree(
        topics: topics,
        boards: boards,
        query: query,
      );

  /// 当前选中的主题键（三个视图共享：「队列」页选的、「主题」页点的，是同一个）。
  String? selectedKey;

  kv.LocaltaskListTopic? get selected {
    for (final t in topics) {
      if (t.key == selectedKey) return t;
    }
    return null;
  }

  // ── 当前主题的任务清单 ────────────────────────────────────
  //
  // 清单放在 controller 而不是某个视图里：抽屉（切任务）与主页（看队列）
  // 看的是**同一份**数据。各自拉一份的话，抽屉里刚领的活主页还不知道 ——
  // 这类「两处状态」的病，最后都要靠到处 refresh 来缝。

  List<kv.LocaltaskTasksTask> tasks = const [];
  bool tasksLoading = false;
  String? tasksError;

  /// 状态过滤：null = 全部（与 `localtask.tasks --status` 同口径）。
  String? statusFilter;

  /// 拉当前主题的清单。`status` 省略时沿用 [statusFilter]。
  Future<void> loadTasks({String? status}) async {
    final key = selectedKey;
    if (key == null) {
      tasks = const [];
      notifyListeners();
      return;
    }
    tasksLoading = true;
    tasksError = null;
    notifyListeners();
    try {
      final out = await _client.localtaskTasks(key, null, status ?? statusFilter);
      // 期间切了主题：这份结果已经过时，别把别人的清单贴到当前主题上
      if (selectedKey != key) return;
      tasks = out.tasks;
    } catch (e) {
      if (selectedKey == key) tasksError = humanize(e);
    } finally {
      tasksLoading = false;
      notifyListeners();
    }
  }

  /// 换状态过滤并重拉（抽屉与队列页共用）。
  void filterTasks(String? status) {
    if (statusFilter == status) return;
    statusFilter = status;
    loadTasks();
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
    // 组清单与主题清单是两个来源：一个失败不该让另一个也空着，
    // 所以分两次 await（不是 Future.wait 里一起失败）。
    await loadBoards();
    // 主题清单变了，当前主题的活也可能变了（领走一条、被 prune 掉）—— 一起刷
    await loadTasks();
  }

  /// 拉项目组清单（失败即空，不报错）。
  Future<void> loadBoards() async {
    try {
      final out = await _api.boards(endpoint);
      // 组变了树就要重画：界面订阅的是本 controller
      boards = out;
    } catch (_) {
      boards = const [];
    }
    notifyListeners();
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
    tasks = const []; // 旧主题的清单立刻下线，别让抽屉先显示上一个主题的活
    notifyListeners();
    loadTasks();
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

  /// 派一条任务。
  ///
  /// 契约 0.55.x 起 `localtaskAdd` 多了第二个参数 `file`（正文可以走文件，
  /// 长文本/多行不必再靠引号硬拼，见 nx-kv `feat(localtask): 提交任务支持 --file`）。
  /// 这里正文一直是从编辑页读出来的字符串，`file` 传 null —— 但**位置不能漏**，
  /// 少了它后面每个参数都会左移一格（CI 上就是这么炸的：13 required, 12 given）。
  Future<kv.LocaltaskAddOutput> add(String text, String cwd) =>
      _client.localtaskAdd(text, null, cwd, null, null, null, null, null, null, null, null, null, null);

  // ── 附件本体（手机端要真的画出来）──────────────────────────
  //
  // 任务详情里的附件以前只显示「本机：D:\…\x.png」—— 那句话对手机毫无用处：
  // 路径在 PC 上，手机既打不开也看不到。第 4 轮反馈第 3 条要的就是这件事：
  // **附件要经网络传到手机端展示**。

  /// 已取回的附件字节：fileId → bytes。
  ///
  /// 同一张图会被重画很多次（滚动、切任务、旋转屏幕），每画一次走一遍公网
  /// 就是几百 KB 的白流量，所以按 id 缓存。
  final Map<String, Uint8List> _attachmentCache = {};

  /// 缓存预算按**字节**算而不是按条数：20 张 1MB 的截图和 20 张 20KB 的图标
  /// 是两回事，按条数限等于没限。
  static const int _attachmentCacheBudget = 16 * 1024 * 1024;
  int _attachmentCacheUsed = 0;

  /// 取一个附件的字节（命中缓存就不再发请求）。
  Future<Uint8List> attachmentBytes(String fileId) async {
    final hit = _attachmentCache[fileId];
    if (hit != null) return hit;
    final bytes = await _api.attachmentBytes(endpoint, fileId);
    _rememberAttachment(fileId, bytes);
    return bytes;
  }

  void _rememberAttachment(String id, Uint8List bytes) {
    if (bytes.isEmpty) return;
    // 单张就超预算的不缓存（几十 MB 的录屏/压缩包，本来也不该内联画）
    if (bytes.length > _attachmentCacheBudget) return;
    final old = _attachmentCache.remove(id);
    if (old != null) _attachmentCacheUsed -= old.length;
    _attachmentCache[id] = bytes;
    _attachmentCacheUsed += bytes.length;
    // 先进先出地丢：Map 保持插入序
    while (_attachmentCacheUsed > _attachmentCacheBudget && _attachmentCache.length > 1) {
      final first = _attachmentCache.keys.first;
      _attachmentCacheUsed -= _attachmentCache.remove(first)!.length;
    }
  }

  @override
  void dispose() {
    _attachmentCache.clear();
    _attachmentCacheUsed = 0;
    super.dispose();
  }

  // ── 错误人话 ──────────────────────────────────────────────

  /// 三层错误都要能读：桥的（MnWsException）、契约客户端的（NxKvApiException）、
  /// 其它（网络/JSON）。原文都留着，因为 `--json` 的报错信息往往就是答案。
  static String humanize(Object e) {
    if (e is MnWsException) return e.message;
    if (e is kv.NxKvApiException) return e.message;
    return e.toString();
  }
}
