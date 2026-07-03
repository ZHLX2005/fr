/// fr:// URI 解析器
///
/// 格式: fr://{host}/{path?}?{query?}
/// 示例:
///   fr://lab                       → host=lab, path="", query={}
///   fr://lab/demo/clock            → host=lab, path="demo/clock", query={}
///   fr://notion/x?autocapture=true → host=notion, path="x", query={autocapture: true}
class FrUri {
  final String scheme;
  final String host;
  final String path;
  final Map<String, String> query;

  const FrUri({
    required this.scheme,
    required this.host,
    required this.path,
    required this.query,
  });

  /// 解析失败返回 null（scheme 错误、字符串空、host 缺失任一情况）。
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
    final pathAndHost = querySplitIdx == -1
        ? afterScheme
        : afterScheme.substring(0, querySplitIdx);
    final queryStr = querySplitIdx == -1 ? '' : afterScheme.substring(querySplitIdx + 1);

    // host / path split（第一个 '/' 是分隔符）
    final slashIdx = pathAndHost.indexOf('/');
    final host = slashIdx == -1 ? pathAndHost : pathAndHost.substring(0, slashIdx);
    if (host.isEmpty) return null;
    final path = slashIdx == -1
        ? ''
        : Uri.decodeComponent(pathAndHost.substring(slashIdx + 1));

    // query 解析
    final query = <String, String>{};
    if (queryStr.isNotEmpty) {
      for (final pair in queryStr.split('&')) {
        final eq = pair.indexOf('=');
        if (eq == -1) {
          query[Uri.decodeComponent(pair)] = '';
        } else {
          final k = Uri.decodeComponent(pair.substring(0, eq));
          final v = Uri.decodeComponent(pair.substring(eq + 1));
          query[k] = v;
        }
      }
    }

    return FrUri(
      scheme: 'fr',
      host: host,
      path: path,
      query: query,
    );
  }
}
