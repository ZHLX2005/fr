import '../../../api/goframe/kv/kv_endpoint.dart';
import '../export/storage_exporter.dart';

class BackupResult {
  final bool ok;
  final int? bytes;
  final String? error;
  const BackupResult({required this.ok, this.bytes, this.error});
}

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

  /// 备份：本地全量 → dump 文本 → kv.set(prefix+name, text)
  Future<BackupResult> backup(String name) async {
    final er = await StorageExporter().buildDumpText();
    if (er.text.isEmpty) {
      return const BackupResult(ok: false, error: '导出内容为空');
    }
    final r = await _kv.set(key: _realKey(name), value: er.text);
    if (r.code != 0) {
      return BackupResult(
        ok: false,
        error: r.message.isEmpty ? 'kv set 失败' : r.message,
      );
    }
    return BackupResult(ok: true, bytes: er.text.length);
  }

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
