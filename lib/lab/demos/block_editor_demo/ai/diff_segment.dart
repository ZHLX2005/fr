/// 单个 diff 段 — 表示 block content 在原版本和新版本之间的变化片段。
///
/// 用在编辑器 inline diff 高亮渲染（红删 / 绿增）。
/// 运行时状态，**不持久化**（存在 EditorState，不在 Block 模型里）。
class DiffSegment {
  /// 'kept' — 原样保留
  /// 'removed' — 原版本有，新版本删了（红色删除线）
  /// 'added' — 原版本无，新版本新增（绿色背景）
  final String type;
  final String text;

  const DiffSegment._(this.type, this.text);

  factory DiffSegment.kept(String text) => DiffSegment._('kept', text);
  factory DiffSegment.removed(String text) => DiffSegment._('removed', text);
  factory DiffSegment.added(String text) => DiffSegment._('added', text);

  bool get isKept => type == 'kept';
  bool get isRemoved => type == 'removed';
  bool get isAdded => type == 'added';

  @override
  String toString() => '$type:"$text"';
}

/// 字符级 diff — 用经典 LCS 算法算最长公共子序列，逐字符切分。
///
/// 时间复杂度 O(n*m)，适合短文本（block content 通常 < 500 字符）。
/// 短到极端的情况可后续换成 Myers diff，目前够用。
class CharDiff {
  /// 对比 [oldText] 和 [newText]，返回 DiffSegment 列表。
  ///
  /// 规则：
  /// - 公共字符段 → kept
  /// - 仅 old 里有 → removed
  /// - 仅 new 里有 → added
  static List<DiffSegment> compute(String oldText, String newText) {
    if (oldText == newText) {
      return oldText.isEmpty ? const [] : [DiffSegment.kept(oldText)];
    }
    if (oldText.isEmpty) {
      return [DiffSegment.added(newText)];
    }
    if (newText.isEmpty) {
      return [DiffSegment.removed(oldText)];
    }

    final lcs = _lcsTable(oldText, newText);
    return _backtrack(oldText, newText, lcs);
  }

  /// 构造 (oldLen+1) x (newLen+1) 的 LCS 长度表。
  static List<List<int>> _lcsTable(String a, String b) {
    final n = a.length;
    final m = b.length;
    final t = List.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        if (a[i - 1] == b[j - 1]) {
          t[i][j] = t[i - 1][j - 1] + 1;
        } else {
          t[i][j] = t[i - 1][j] > t[i][j - 1] ? t[i - 1][j] : t[i][j - 1];
        }
      }
    }
    return t;
  }

  /// 从 LCS 表回溯出 diff 段（从右下角走到左上角）。
  static List<DiffSegment> _backtrack(String a, String b, List<List<int>> t) {
    final result = <DiffSegment>[];
    var i = a.length;
    var j = b.length;

    // 临时缓冲，最后按反向遍历 → 输出反向数组 → 再 reverse
    final buf = <DiffSegment>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
        buf.add(DiffSegment.kept(a[i - 1]));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || t[i][j - 1] >= t[i - 1][j])) {
        buf.add(DiffSegment.added(b[j - 1]));
        j--;
      } else if (i > 0 && (j == 0 || t[i][j - 1] < t[i - 1][j])) {
        buf.add(DiffSegment.removed(a[i - 1]));
        i--;
      }
    }

    // 合并连续同类型段（避免 "kept:h" "kept:e" "kept:l" "kept:l" "kept:o"）
    for (final seg in buf.reversed) {
      if (result.isNotEmpty && result.last.type == seg.type) {
        final last = result.removeLast();
        result.add(DiffSegment._(last.type, last.text + seg.text));
      } else {
        result.add(seg);
      }
    }
    return result;
  }
}
