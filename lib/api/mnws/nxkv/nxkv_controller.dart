import 'package:flutter/foundation.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../mnws.dart';
import 'nxkv_api.dart';
import 'nxkv_boards.dart';
import 'nxkv_template.dart';
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

  /// 项目组（看板）清单 —— 侧边栏的组行。
  ///
  /// 它是**导航装饰**：拉不到就是空列表，项目照常平铺，任务队列照样能用。
  /// 所以这里没有 `boardsError`，也不参与 loading 判定。
  List<NxKvBoard> boards = const [];

  /// 各组的**组任务**（`localtask.boardtasks`，一次拿全）。
  ///
  /// 组任务物理上落在成员项目的队列里，归属只看正文 frontmatter 的 board ——
  /// 服务端已经按这个口径聚合好了，这里只按 topicKey / boardKey 用：
  ///   · 侧栏组行徽标 = 本组任务待领；
  ///   · 项目行徽标要**减掉**落在自己队列里的组任务（两种走向，见 nxkv_tree.dart）；
  ///   · 组页（选中一个组）列的就是这些任务，每条带归属项目。
  ///
  /// 拉不到不算错：`boardTasksKnown` 转 false，界面说「数暂时没有」，不报 0。
  List<kv.LocaltaskBoardTasksBoard> boardTasks = const [];
  bool boardTasksKnown = false;

  /// 侧边栏要画的行（组行在前、项目平铺在后）。搜索词非空时只留命中的行。
  ///
  /// 语义与 nx-kv 面板一致（见 `nxkv_tree.dart` 文件头）：**组是组、项目是项目**，
  /// 两者都是队列；组任务从项目侧剔除，组不跳到项目去。
  NxKvSideList sideList({String query = ''}) => buildSideList(
        topics: topics,
        boards: boards,
        boardTasks: boardTasks,
        boardTasksKnown: boardTasksKnown,
        query: query,
      );

  /// 当前选中的主题键（三个视图共享：「队列」页选的、「主题」页点的，是同一个）。
  String? selectedKey;

  /// 当前选中的**组**（看板键 `group/xxx`）。非空时主区看的是组队列，
  /// [selectedKey] 为空 —— 两者互斥，和面板的 `#/group/<id>` 与 `#/dir/<key>` 一样。
  String? selectedBoardKey;

  /// 当前选中组的那一行（徽标/名称/成员都从这里取）。
  NxKvSideRow? get selectedGroup =>
      selectedBoardKey == null ? null : sideList().groupByKey(selectedBoardKey);

  kv.LocaltaskListTopic? get selected {
    for (final t in topics) {
      if (t.key == selectedKey) return t;
    }
    return null;
  }

  /// 当前组的数据（`boardtasks` 里的那一条）；null = 没选组 / 服务端没这个组。
  kv.LocaltaskBoardTasksBoard? get selectedBoard {
    final key = selectedBoardKey;
    if (key == null) return null;
    for (final b in boardTasks) {
      if (b.key == key || b.id == key) return b;
    }
    return null;
  }

  // ── 当前主题的任务清单 ────────────────────────────────────
  //
  // 清单放在 controller 而不是某个视图里：抽屉（切任务）与主页（看队列）
  // 看的是**同一份**数据。各自拉一份的话，抽屉里刚领的活主页还不知道 ——
  // 这类「两处状态」的病，最后都要靠到处 refresh 来缝。

  /// 当前主题的**项目走向**任务清单（已剔除组任务）。
  ///
  /// 面板里项目侧与组侧是两种走向（`projectTasks` / `taskInBoard`）：组任务物理上
  /// 躺在项目队列里，但它的「归属」是组 —— 项目列表再列一遍就成了两份数据。
  /// 端侧同理：这里只留 `board` 为空的任务，组任务在组页里看。
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
      // 显示序 = 待领取 → 已领取 → 终态，桶内最新在前（`sortTasksForDisplay`）。
      // 服务端给的是队列追加序（seq），直接画会出现「刚发的活在最底下」。
      tasks = sortTasksForDisplay(
        out.tasks.where((t) => t.board.isEmpty).toList(),
        (t) => (
          bucket: nxKvTaskBucket(t.status),
          stamp: nxKvTaskStamp(
            createdAt: t.createdAt,
            consumedAt: t.consumedAt,
            completedAt: t.completedAt,
          ),
          id: t.id,
        ),
      );
    } catch (e) {
      if (selectedKey == key) tasksError = humanize(e);
    } finally {
      tasksLoading = false;
      notifyListeners();
    }
  }

  /// 当前组的任务清单（按 [statusFilter] 过滤，按显示序排）。
  ///
  /// 数据来自 [boardTasks]（一次拿全的组任务），**不再逐成员队列去问** ——
  /// 那在手机上就是 28 次请求，每次服务端还要重读一遍 store。
  ///
  /// 排序与项目队列同一份口径（[sortTasksForDisplay]）：服务端按「待领在前、
  /// 编号升序」给，那是队列序；组页要看的是「最新在最上面」。
  List<kv.LocaltaskBoardTasksBoardTask> get groupTasks {
    final sorted = sortTasksForDisplay(
      selectedBoard?.tasks ?? const <kv.LocaltaskBoardTasksBoardTask>[],
      (t) => (
        bucket: nxKvTaskBucket(t.status),
        stamp: nxKvTaskStamp(
          createdAt: t.createdAt,
          consumedAt: t.consumedAt,
          completedAt: t.completedAt,
        ),
        id: t.id,
      ),
    );
    final f = statusFilter;
    if (f == null) return sorted;
    return sorted.where((t) => t.status == f).toList();
  }

  /// 换状态过滤并重拉（抽屉与队列页共用）。组页只筛本地缓存，不发请求。
  void filterTasks(String? status) {
    if (statusFilter == status) return;
    statusFilter = status;
    if (selectedBoardKey != null) {
      notifyListeners();
      return;
    }
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
    // 组清单 / 组任务 / 主题清单是三个来源：一个失败不该让另一个也空着，
    // 所以分开 await（不是 Future.wait 里一起失败）。
    await loadBoards();
    await loadBoardTasks();
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

  /// 拉「各组的组任务」（`localtask.boardtasks`，一次请求拿全）。
  ///
  /// 失败不是空：`boardTasksKnown` 转 false，界面上组的徽标就不再假装 0，
  /// 而是说明「组任务数暂时拿不到」—— 让人知道这是没数，不是没活。
  Future<void> loadBoardTasks() async {
    try {
      final out = await _client.localtaskBoardtasks(null);
      boardTasks = out.boards;
      boardTasksKnown = true;
    } catch (_) {
      boardTasks = const [];
      boardTasksKnown = false;
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
    if (selectedKey == key && selectedBoardKey == null) return;
    selectedKey = key;
    selectedBoardKey = null; // 项目与组是互斥的两个落点（面板上也是两条路由）
    tasks = const []; // 旧主题的清单立刻下线，别让抽屉先显示上一个主题的活
    notifyListeners();
    loadTasks();
  }

  /// 选一个**组**：主区看组队列（本组任务，带归属项目 tag）。
  ///
  /// 组有自己的任务，不是「装着项目的文件夹」—— 选中组不碰任何项目队列。
  void selectBoard(String? key) {
    if (selectedBoardKey == key) return;
    selectedBoardKey = key;
    if (key != null) {
      selectedKey = null;
      tasks = const [];
    }
    notifyListeners();
  }

  // ── 动作（全部走生成客户端）────────────────────────────────

  Future<kv.LocaltaskTasksOutput> tasksOf(String key, {String? status}) =>
      _client.localtaskTasks(key, null, status);

  /// 看一条任务的详情（契约 0.65.x 起：详情走 `localtaskShow`，
  /// `localtaskGet` 改成「领一条」的语义）。
  Future<kv.LocaltaskShowOutput> task(int id, String? key) =>
      _client.localtaskShow(id, null, key);

  /// 领一条（契约 0.65.x 起：`localtaskGet` = 领一条 + 返回任务信封；
  /// 旧的 `localtaskClaim` 已并入它）。
  Future<kv.LocaltaskGetOutput> claim(kv.LocaltaskListTopic topic) =>
      _client.localtaskGet(topic.cwd, null, true, null);

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

  /// 改一条**已存在**任务的正文（服务端 `localtask.update --text`）。
  ///
  /// 「再编辑」不是「再派一条」：编号不变、队列位置不变、领取状态与轮次历史
  /// 都不动，换掉的只是文件内容。服务端按首个 `#` 行取标题，所以改标题也走这里。
  ///
  /// 十个位置参数是生成客户端的形制（`id, text, cwd, key, ...`），后面的时间目标
  /// 与 DAG 字段手机端不碰 —— 全传 null 就是「这几样别动」。
  Future<kv.LocaltaskUpdateOutput> editTask(int id, String? key, String text) =>
      _client.localtaskUpdate(id, text, null, key, null, null, null, null, null, null);

  /// 派一条任务。
  ///
  /// 契约 0.55.x 起 `localtaskAdd` 多了第二个参数 `file`（正文可以走文件，
  /// 长文本/多行不必再靠引号硬拼，见 nx-kv `feat(localtask): 提交任务支持 --file`）。
  /// 这里正文一直是从编辑页读出来的字符串，`file` 传 null —— 但**位置不能漏**，
  /// 少了它后面每个参数都会左移一格（CI 上就是这么炸的：13 required, 12 given）。
  Future<kv.LocaltaskAddOutput> add(String text, String cwd) =>
      _client.localtaskAdd(text, null, cwd, null, null, null, null, null, null, null, null, null, null);

  /// 在**组里**派一条：落点选一个成员仓库，归属写进正文 frontmatter。
  ///
  /// 这正是面板组页「＋ 新增任务 → 工具区选归属项目（限本组成员）」那条路：
  ///   · `board`   = 看板 id —— 任务出现在组页（`boardtasks` 按它认领）；
  ///   · `project` = 成员仓库 key —— 任务物理落进那个项目的队列（agent 按目录领活）；
  ///   · `cwd`     = 不给 —— 由 `project` 推导落点，免得队列目录与仓库路径不一致时报错。
  ///
  /// 服务端会校验「该项目是不是本组成员」，不是就直接拒绝（不在端侧重复这条规则）。
  Future<kv.LocaltaskAddOutput> addToBoard(
    String text, {
    required String boardId,
    required String projectKey,
  }) =>
      _client.localtaskAdd(text, null, null, null, null, boardId, projectKey, null, null, null, null, null, null);

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

  /// 新建任务的起始正文（fr #23）。
  ///
  /// 取服务端的默认模板并按 `{{槽位}}` 渲染；拉不到 / 没模板 / 模板被删 →
  /// 面板同款兜底骨架。**任何情况都返回可直接放进编辑器的正文**，不抛：
  /// 派活是主路径，模板取不回来只是「正文朴素一点」，不该变成派不出去。
  Future<String> newTaskBody() async {
    try {
      final set = await _api.templates(endpoint);
      return nxKvNewTaskBody(set);
    } catch (_) {
      return nxKvNewTaskBody(null);
    }
  }

  /// 上传一张图片到本机附件仓，返回可直接插进正文的嵌入片段。
  ///
  /// 这是 md 编辑器贴图的唯一网络动作：编辑器拿到片段插进正文，任务提交时
  /// 服务端自动解析嵌入并登记附件关系 —— 端侧不再调 attach（面板同一条链路）。
  Future<NxKvUpload> uploadImage({
    required String name,
    required Uint8List bytes,
    String contentType = '',
  }) =>
      _api.uploadFile(endpoint, name: name, bytes: bytes, contentType: contentType);

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
