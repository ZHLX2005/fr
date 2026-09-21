import '../const_clock_max_mode.dart';
import '../models/lab_clock.dart';
import '../models/lab_clock_record.dart';

/// 一条 parent 血缘链 —— max 模式下「合并卡」的唯一数据源。
///
/// 全部字段在构造时算好，只读；不持有 provider、不写任何存储。
class ClockChain {
  /// 链根 clock：卡片标题与圆点颜色的来源（稳定，不随代表漂移）。
  final LabClock root;

  /// 链上全部 clock，顺序 = 输入 clocks 中的出现顺序。
  final List<LabClock> members;

  /// 播放/暂停/重置与长按编辑的作用对象。
  final LabClock representative;

  /// max(成员 durationSeconds ?? 0) —— 合并卡中央要显示的"最大的一个时间"。
  final int maxDurationSeconds;

  const ClockChain({
    required this.root,
    required this.members,
    required this.representative,
    required this.maxDurationSeconds,
  });

  /// 分组键（grid key / map key 用）。
  String get id => root.id;

  String get title => root.title;

  int get size => members.length;

  /// 正在运行的成员；null = 链上全空闲。
  /// pickRepresentative 保证「有运行成员时代表必是运行成员」，故可直接派生。
  LabClock? get running => representative.isRunning ? representative : null;

  bool get isRunning => representative.isRunning;

  /// 合并卡中央显示的数字：运行中显示实时倒计时，空闲显示链上最大目标时长。
  int get centerSeconds =>
      isRunning ? representative.remainingSeconds : maxDurationSeconds;

  /// true → 中央数字是"链上最大目标时长"（用 accent 色并挂角标）。
  bool get centerIsChainMax => !isRunning;
}

/// max 模式下记录区的一行：每条链折叠成一行，孤儿记录汇总成最后一行。
class ChainRecordRow {
  final String chainId;

  /// 链标题（根 clock 的 title），孤儿行 = [kClockChainOrphanTitle]。
  final String title;

  /// 该链"实际时长最大"的那条记录（孤儿行 = 孤儿记录中最大的那条）。
  final LabClockRecord record;

  /// 上面那条记录的实际时长（秒）。
  final int actualSeconds;

  /// 该链的记录条数（"N 条"角标）。
  final int count;

  /// 孤儿行（所属 clock 已被删除）→ UI 用 textMuted 弱化。
  final bool isOrphan;

  const ChainRecordRow({
    required this.chainId,
    required this.title,
    required this.record,
    required this.actualSeconds,
    required this.count,
    this.isOrphan = false,
  });
}

/// clock 血缘链的纯函数工具集。
///
/// 刻意不依赖 Flutter / Provider：`LabClockProvider` 构造函数会调
/// `MetronomeService.ensureReady()`（测试环境抛 UnsupportedError），无法在单测里
/// 实例化，所以链解析的全部决策都必须留在这里才能被测（照 `resolveToggle` /
/// `crossedZero` / `resolveColor` 的既有范式）。
class ClockChainUtil {
  ClockChainUtil._();

  /// 按 `parentId` 把 [clocks] 分组成链。
  ///
  /// 输出顺序 = 每条链的首个成员在 [clocks] 中的出现顺序 —— 这让 clock 网格与
  /// 记录折叠行天然对齐（旧版按 title 字典序排会让两者各排各的，用户对不上）。
  ///
  /// 用并查集而非"沿 parentId 上溯"：上溯法在环数据（A→B→A）下会因入口不同
  /// 得到两个不同的"根"，把同一个环拆成两条链；并查集只 union 边，天然安全，
  /// 且是迭代实现（超长直线链不会爆栈）。
  static List<ClockChain> buildChains(List<LabClock> clocks) {
    if (clocks.isEmpty) return const [];

    final byId = {for (final c in clocks) c.id: c};
    final rootIds = resolveRootIds(clocks);

    // 保序分组：key = 并查集根，插入顺序即"首次出现顺序"。
    final buckets = <String, List<LabClock>>{};
    for (final c in clocks) {
      buckets.putIfAbsent(rootIds[c.id]!, () => <LabClock>[]).add(c);
    }

    final chains = <ClockChain>[];
    for (final members in buckets.values) {
      var maxDuration = 0;
      for (final m in members) {
        final d = m.durationSeconds ?? 0;
        if (d > maxDuration) maxDuration = d;
      }
      chains.add(
        ClockChain(
          root: _displayRoot(members, byId),
          members: List.unmodifiable(members),
          representative: pickRepresentative(members),
          maxDurationSeconds: maxDuration,
        ),
      );
    }
    return chains;
  }

  /// 每个 clock id → 其所属链的并查集根 id。环 / 缺失父 / 自环都不会死循环。
  static Map<String, String> resolveRootIds(List<LabClock> clocks) {
    final byId = {for (final c in clocks) c.id: c};
    final up = <String, String>{for (final c in clocks) c.id: c.id};

    // 迭代 find + 路径压缩。
    String find(String x) {
      var r = x;
      while (up[r] != r) {
        r = up[r]!;
      }
      var cur = x;
      while (up[cur] != r) {
        final next = up[cur]!;
        up[cur] = r;
        cur = next;
      }
      return r;
    }

    // 只连"父确实存在"的边：缺失父 = 该节点即根（不连边）。
    for (final c in clocks) {
      final p = c.parentId;
      if (p == null || !byId.containsKey(p)) continue;
      final a = find(c.id);
      final b = find(p);
      if (a != b) up[a] = b;
    }

    return {for (final c in clocks) c.id: find(c.id)};
  }

  /// 链内代表选取：优先运行中的成员（多个取时长最大者），否则取时长最大者；
  /// 平手取 createdAt 最早，再平手取 id 字典序最小（保证确定性）。
  static LabClock pickRepresentative(List<LabClock> members) {
    assert(members.isNotEmpty, 'pickRepresentative 需要至少一个成员');
    final runnings = members.where((c) => c.isRunning).toList();
    final pool = runnings.isNotEmpty ? runnings : members;
    var best = pool.first;
    for (final c in pool.skip(1)) {
      if (_isPreferred(c, best)) best = c;
    }
    return best;
  }

  /// 记录的实际时长（秒）—— `LabClockProvider.getRecordLiveDuration` 的唯一实现，
  /// provider 侧已改为委托本方法，避免两份等价逻辑日后分叉。
  static int liveDuration(LabClockRecord record, LabClock? clock) {
    // 已完成：直接返回保存的值
    if (record.completed) return record.accumulatedSeconds ?? 0;
    // 时钟还在：当前已消耗 = 配置时长 - 剩余
    if (clock != null) return record.durationSeconds - clock.remainingSeconds;
    // 时钟不在且未完成：用已累计秒数兜底
    return record.accumulatedSeconds ?? 0;
  }

  /// 记录按链折叠成"每条链一行"。
  ///
  /// - 分组键 = 记录所属 clock 的链；**孤儿记录**（clock 已删）汇总成最后一行，
  ///   否则这些历史记录会在 max 模式下静默消失。
  /// - 组内取**实际时长**最大者（不是配置时长 `durationSeconds`）；平手保留
  ///   先遇到的一条 —— [records] 已按 startTime 倒序，等价于"保留最近的一条"。
  /// - 行顺序 = 链顺序，孤儿行恒在最后。
  static List<ChainRecordRow> foldRecords({
    required List<LabClock> clocks,
    required List<LabClockRecord> records,
  }) {
    final chains = buildChains(clocks);
    final byId = {for (final c in clocks) c.id: c};

    final clockToChain = <String, String>{};
    for (final ch in chains) {
      for (final m in ch.members) {
        clockToChain[m.id] = ch.id;
      }
    }

    final best = <String, LabClockRecord>{};
    final counts = <String, int>{};
    LabClockRecord? orphanBest;
    var orphanCount = 0;

    for (final r in records) {
      final chainId = clockToChain[r.clockId];
      if (chainId == null) {
        // clock 已删：byId 查不到 → liveDuration 走 accumulated 兜底。
        orphanCount++;
        final v = liveDuration(r, null);
        if (orphanBest == null || v > liveDuration(orphanBest, null)) {
          orphanBest = r;
        }
        continue;
      }
      counts[chainId] = (counts[chainId] ?? 0) + 1;
      final prev = best[chainId];
      if (prev == null ||
          liveDuration(r, byId[r.clockId]) >
              liveDuration(prev, byId[prev.clockId])) {
        best[chainId] = r;
      }
    }

    final rows = <ChainRecordRow>[];
    for (final ch in chains) {
      final count = counts[ch.id] ?? 0;
      if (count == 0) continue; // 该链无任何记录 → 不产出行（但网格里仍有卡）
      final r = best[ch.id]!;
      rows.add(
        ChainRecordRow(
          chainId: ch.id,
          title: ch.title,
          record: r,
          actualSeconds: liveDuration(r, byId[r.clockId]),
          count: count,
        ),
      );
    }

    if (orphanCount > 0 && orphanBest != null) {
      rows.add(
        ChainRecordRow(
          chainId: kClockOrphanChainId,
          title: kClockChainOrphanTitle,
          record: orphanBest,
          actualSeconds: liveDuration(orphanBest, null),
          count: orphanCount,
          isOrphan: true,
        ),
      );
    }
    return rows;
  }

  /// 由编辑器结果解析要写入的 parentId —— sheet 的显示条件与调用方的采纳条件
  /// 共用这一行代码，杜绝"开关显示了但不生效"的漂移型 bug。
  static String? resolveParentId({
    required LabClock? mergeParent,
    required bool isNewRoot,
  }) {
    if (mergeParent == null || isNewRoot) return null;
    return mergeParent.id;
  }

  /// "新的根时钟"开关是否显示：存在可并入的父才显示。
  ///
  /// - 从记录新建（[mergeParent] 非空）→ 显示，默认关（并入来源链）
  /// - 长按编辑一个在链上的 clock（`parentId != null`）→ 显示，打开 = 脱离链
  /// - FAB 新建 / 编辑一个已经是根的 clock → 不显示（无父可并入）
  static bool shouldShowNewRootSwitch({
    LabClock? existing,
    LabClock? mergeParent,
  }) {
    if (mergeParent != null) return true;
    return existing?.parentId != null;
  }

  /// 组件的展示用链根：无父或父已不存在的成员中取唯一一个；
  /// 纯环（无候选）或多候选异常 → 取 createdAt 最早者（id 兜底）保证确定性。
  static LabClock _displayRoot(List<LabClock> members, Map<String, LabClock> byId) {
    final candidates = members
        .where((c) {
          final p = c.parentId;
          return p == null || !byId.containsKey(p);
        })
        .toList();
    if (candidates.length == 1) return candidates.first;
    return _earliest(candidates.isEmpty ? members : candidates);
  }

  static LabClock _earliest(List<LabClock> pool) {
    var best = pool.first;
    for (final c in pool.skip(1)) {
      if (c.createdAt.isBefore(best.createdAt) ||
          (c.createdAt == best.createdAt && c.id.compareTo(best.id) < 0)) {
        best = c;
      }
    }
    return best;
  }

  /// a 是否比 b 更该当选代表：时长更大 → createdAt 更早 → id 更小。
  static bool _isPreferred(LabClock a, LabClock b) {
    final da = a.durationSeconds ?? 0;
    final db = b.durationSeconds ?? 0;
    if (da != db) return da > db;
    if (a.createdAt != b.createdAt) return a.createdAt.isBefore(b.createdAt);
    return a.id.compareTo(b.id) < 0;
  }
}
