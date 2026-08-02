import '../../../api/goframe/kv/kv_endpoint.dart';

/// 云端存储同步 —— 把本地 Hive+prefs+notes 整份快照存到一个 KV key。
///
/// 真实 key = `fr_storage_backup:<用户输入的友好名>`，前缀只在内部加/剥，
/// UI 永远看到的是友好名。
///
/// 依赖 [KvOps]（不是具体 KvEndpoint）以便单测注入。
class CloudStorageSync {
  CloudStorageSync(this._kv);

  final KvOps _kv;

  static const String prefix = 'fr_storage_backup:';

  String _realKey(String name) => '$prefix$name';

  /// 列已有备份的友好名（剥前缀；过滤非本前缀的 key）。
  Future<List<String>> listBackups() async {
    final r = await _kv.list();
    if (r.code != 0 || r.data == null) return const [];
    return r.data!.items
        .map((e) => e.key)
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList()
      ..sort();
  }

  /// 删除一个备份。
  Future<bool> deleteBackup(String name) async {
    final r = await _kv.delete(_realKey(name));
    return r.code == 0;
  }
}
