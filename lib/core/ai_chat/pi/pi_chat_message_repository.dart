import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';

import '../../storage/box_descriptor.dart';
import '../../storage/hive/hive_repository.dart';
import '../../storage/hive/hive_store.dart';
import '../../storage/hive_type_ids.dart';
import '../../storage/storage_registry.dart';
import 'pi_chat_message.dart';

/// pi 聊天消息的本地仓库（Hive typed box）。
///
/// 按 flutter-hive-workflow：init 四件套（guard + adapter + 泛型 open +
/// StorageRegistry 注册）；typed box 只用 `Box<PiChatMessage>` 泛型访问。
/// key 结构 `sessionId#seq`：同一会话内按序、跨会话互不冲突。
class PiChatMessageRepository implements HiveRepository {
  static const String _boxName = 'pi_chat_messages';

  late Box<PiChatMessage> _box;
  bool _initialized = false;

  /// 每会话的本地消息序号（key 稳定递增用）。
  final Map<String, int> _seq = {};

  @override
  String get boxName => _boxName;

  Future<void> init() async {
    if (_initialized) return;
    _box = await HiveStore.instance.openTyped<PiChatMessage>(
      _boxName,
      adapter: PiChatMessageAdapter(),
      typeId: HiveTypeIds.piChatMessage,
    );
    StorageRegistry.register(BoxDescriptor<PiChatMessage>(
      name: _boxName,
      displayName: 'pi 聊天记录',
      typeId: HiveTypeIds.piChatMessage,
      openTyped: () => HiveStore.instance.openTyped<PiChatMessage>(
        _boxName,
        adapter: PiChatMessageAdapter(),
        typeId: HiveTypeIds.piChatMessage,
      ),
      formatValue: (v) {
        final m = v as PiChatMessage;
        final role = m.role == 'user' ? '用户' : '助手';
        final preview =
            m.text.length > 40 ? '${m.text.substring(0, 40)}…' : m.text;
        return [
          '会话: ${m.sessionId.substring(0, 8)}…',
          '角色: $role${m.pending ? '（发送中）' : ''}',
          '内容: $preview',
          if (m.model != null) '模型: ${m.model}',
          if (m.error != null) '错误: ${m.error}',
          '时间: ${m.createdAt.toString().substring(0, 19)}',
        ].join('\n');
      },
    ));
    // 重建序号表：key 形如 sessionId#seq
    for (final key in _box.keys) {
      final k = key.toString();
      final idx = k.indexOf('#');
      if (idx <= 0 || idx == k.length - 1) continue;
      final sid = k.substring(0, idx);
      final seq = int.tryParse(k.substring(idx + 1));
      if (seq == null) continue;
      if (seq >= (_seq[sid] ?? 0)) _seq[sid] = seq + 1;
    }
    _initialized = true;
  }

  /// 某会话的全部消息（按 key 中的 seq 排序 = 按时间序）。
  List<PiChatMessage> messagesOf(String sessionId) {
    final prefix = '$sessionId#';
    final items = <(int, PiChatMessage)>[];
    for (final key in _box.keys) {
      final k = key.toString();
      if (!k.startsWith(prefix)) continue;
      final seq = int.tryParse(k.substring(prefix.length));
      final msg = _box.get(key);
      if (seq != null && msg != null) items.add((seq, msg));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    return items.map((e) => e.$2).toList();
  }

  /// 追加一条消息，返回稳定 key。
  Future<String> append(PiChatMessage message) async {
    final seq = _seq[message.sessionId] ?? 0;
    _seq[message.sessionId] = seq + 1;
    final key = message.keyFor(seq);
    await _box.put(key, message);
    return key;
  }

  /// 流式补全：把增量写回同一条消息（key 不变）。
  Future<void> updateText(String key, String text, {bool? done}) async {
    final msg = _box.get(key);
    if (msg == null) return;
    msg
      ..text = text
      ..pending = false
      ..done = done ?? msg.done;
    await _box.put(key, msg);
  }

  /// 标记用户消息**已送达**（只清 pending，不改正文）。
  ///
  /// 区别于 updateText：后者需要调用方提供 text，跟随路径曾误传 '' 把
  /// 用户原话清成空串（第 11 次复评探针 F2）。
  Future<void> markUserDelivered(String key) async {
    final msg = _box.get(key);
    if (msg == null) return;
    msg.pending = false;
    await _box.put(key, msg);
  }

  /// 标记错误（prompt 被拒 / 网络失败）。
  Future<void> markError(String key, String error) async {
    final msg = _box.get(key);
    if (msg == null) return;
    msg
      ..error = error
      ..pending = false
      ..done = true;
    await _box.put(key, msg);
  }

  /// 删除某会话最后一条带 error 的 assistant 消息（失败重发前清理用）。
  Future<void> removeLastErrorOf(String sessionId) async {
    final prefix = '$sessionId#';
    String? targetKey;
    var targetSeq = -1;
    for (final key in _box.keys) {
      final k = key.toString();
      if (!k.startsWith(prefix)) continue;
      final msg = _box.get(key);
      if (msg == null || msg.error == null || msg.role != 'assistant') continue;
      final seq = int.tryParse(k.substring(prefix.length)) ?? -1;
      if (seq > targetSeq) {
        targetSeq = seq;
        targetKey = k;
      }
    }
    if (targetKey != null) await _box.delete(targetKey);
  }

  /// 仅测试用：重置 init 状态与序号表（仓库是单例，跨用例会串状态）。
  /// 不关 box（Hive.close 由用例自己控制），只让下一次 init() 重新走 openTyped。
  @visibleForTesting
  void resetForTest() {
    _initialized = false;
    _seq.clear();
  }

  /// 按 key 取一条（控制器持有 key 做流式更新时用）。
  PiChatMessage? getByKey(String key) => _box.get(key);

  /// 清空某会话的本地消息（不删服务端会话）。
  Future<void> clearSession(String sessionId) async {
    final prefix = '$sessionId#';
    final keys = _box.keys.where((k) => k.toString().startsWith(prefix)).toList();
    await _box.deleteAll(keys);
    _seq.remove(sessionId);
  }

  /// 有本地记录的会话 id 集合。
  Set<String> sessionIds() => _seq.keys.toSet();

  Future<void> clearAll() async {
    await _box.clear();
    _seq.clear();
  }
}

final piChatMessageRepository = PiChatMessageRepository();
