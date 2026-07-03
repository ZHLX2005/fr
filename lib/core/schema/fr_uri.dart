/// fr:// URI 解析器
///
/// 格式: fr://{authority}?{query?}
/// 语义:
///   - `authority` = fr:// 和 ? 之间的整段；可以是 'lab'、'lab/demo/clock'、
///     'notion/image-host'。Router 用整段做 prefix 匹配（'lab/demo' 路由
///     'lab/demo/clock'）。Host 单段 vs 多段都靠 authority 表达。
///   - `path` = authority 内第一个 '/' 之后的部分（保留给 handler 拆分）。
///     'lab/demo/clock' → path='demo/clock'；'lab' → path=''。
///   - `query` = ? 后的 key=value 字典。
///
/// 示例:
///   fr://lab                       → authority=lab, path="", query={}
///   fr://lab/demo/clock            → authority=lab/demo/clock, path="demo/clock", query={}
///   fr://notion/image-host?a=true  → authority=notion/image-host, path="image-host",
///                                    query={a: "true"}
class FrUri {
  final String scheme;
  final String authority;
  final String path;
  final Map<String, String> query;

  const FrUri({
    required this.scheme,
    required this.authority,
    required this.path,
    required this.query,
  });

  /// 解析失败返回 null（scheme 错误、字符串空、authority 缺失任一情况）。
  /// 静默返回，不抛 — 调用方负责处理 null。
  static FrUri? tryParse(String raw) {
    if (raw.isEmpty) return null;

    // scheme
    const schemePrefix = 'fr://';
    if (!raw.startsWith(schemePrefix)) return null;
    final afterScheme = raw.substring(schemePrefix.length);
    if (afterScheme.isEmpty) return null;

    // query split
    final querySplitIdx = afterScheme.indexOf('?');
    final authorityRaw = querySplitIdx == -1
        ? afterScheme
        : afterScheme.substring(0, querySplitIdx);
    final queryStr = querySplitIdx == -1 ? '' : afterScheme.substring(querySplitIdx + 1);

    // authority 必须非空（区分 "fr://" 和 "fr://lab"）
    if (authorityRaw.isEmpty) return null;

    // authority 安全 decode。
    //
    // Uri.decodeComponent 对**原始中文字符串**（非 percent-encoded）会抛
    // `Illegal percent encoding`，导致 fr://lab/demo/时钟 崩溃。
    // 仅当含 '%' 时才 decode，且 try/catch 兜底 — decode 失败用原字符串。
    // 这样 fr://lab/demo/时钟 和 fr://lab/demo/%E6%97%B6%E9%92%9F 等价。
    final authority = _safeDecode(authorityRaw);

    // path = authority 内第一个 '/' 之后的部分（保留给 handler 拆分）
    final slashIdx = authority.indexOf('/');
    final path = slashIdx == -1
        ? ''
        : authority.substring(slashIdx + 1);

    // query 解析
    final query = <String, String>{};
    if (queryStr.isNotEmpty) {
      for (final pair in queryStr.split('&')) {
        final eq = pair.indexOf('=');
        if (eq == -1) {
          query[_safeDecode(pair)] = '';
        } else {
          final k = _safeDecode(pair.substring(0, eq));
          final v = _safeDecode(pair.substring(eq + 1));
          query[k] = v;
        }
      }
    }

    return FrUri(
      scheme: 'fr',
      authority: authority,
      path: path,
      query: query,
    );
  }

  /// 安全 URL decode。
  ///
  /// - 输入不含 '%' → 原样返回（避开 decodeComponent 对原始中文抛异常）
  /// - 输入含 '%' → 尝试 decode；失败（非法 % 序列）也原样返回
  static String _safeDecode(String s) {
    if (!s.contains('%')) return s;
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
}
