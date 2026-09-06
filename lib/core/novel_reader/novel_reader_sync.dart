// lib/core/novel_reader/novel_reader_sync.dart
//
// Route A: personal-group KV mirror for library / progress / prefs.
// Book bodies stay local (or download from catalog remoteUrl).
// Offline-first: local SharedPreferences is source of truth; KV is best-effort.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../api/goframe/group/group_endpoint.dart';
import '../../api/goframe/kv/kv_endpoint.dart';
import '../../api/token/token_manager.dart';
import 'novel_reader_constants.dart';
import 'novel_reader_storage.dart';
import 'novel_reader_sync_hook.dart';

export 'novel_reader_sync_hook.dart';

class NovelReaderSync implements NovelReaderSyncHook {
  NovelReaderSync({
    required KvEndpoint kv,
    required GroupEndpoint groups,
    required TokenManager tokens,
    NovelReaderStorage? storage,
    Duration progressDebounce = const Duration(milliseconds: 800),
  })  : _kv = kv,
        _groups = groups,
        _tokens = tokens,
        _storage = storage ?? NovelReaderStorage(),
        _progressDebounce = progressDebounce;

  final KvEndpoint _kv;
  final GroupEndpoint _groups;
  final TokenManager _tokens;
  final NovelReaderStorage _storage;
  final Duration _progressDebounce;

  int? _cachedGroupId;
  Timer? _progressTimer;
  String? _pendingProgressBookId;
  bool _pulling = false;

  /// When false, never touch KV (local-only).
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(NovelReaderConstants.cloudSyncEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NovelReaderConstants.cloudSyncEnabledKey, value);
  }

  Future<bool> get _hasToken async {
    final t = await _tokens.accessToken;
    return t != null && t.isNotEmpty;
  }

  /// Resolve personal workspace: prefer name==personal owner, else first owned.
  Future<int?> resolvePersonalGroupId({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedGroupId != null) return _cachedGroupId;
    if (!await _hasToken) return null;
    final res = await _groups.list();
    if (res.code != 0 || res.data == null) return null;
    final groups = res.data!;
    KvGroup? personal;
    for (final g in groups) {
      if (g.myRole == 'owner' &&
          g.name.trim().toLowerCase() == 'personal') {
        personal = g;
        break;
      }
    }
    if (personal == null) {
      for (final g in groups) {
        if (g.myRole == 'owner') {
          personal = g;
          break;
        }
      }
    }
    _cachedGroupId = personal?.id;
    return _cachedGroupId;
  }

  Future<bool> get canSync async =>
      await isEnabled() && await _hasToken && await resolvePersonalGroupId() != null;

  /// Pull cloud → merge into local prefs (last-write-wins on progress).
  Future<void> pullAll() async {
    if (_pulling) return;
    if (!await canSync) return;
    final gid = await resolvePersonalGroupId();
    if (gid == null) return;
    _pulling = true;
    try {
      await _migrateOnceIfNeeded(gid);
      await _pullLibrary(gid);
      await _pullSelected(gid);
      await _pullPrefs(gid);
      final books = await _storage.getLibrary(mergeCatalog: false);
      for (final book in books) {
        await _pullProgress(gid, book.id);
      }
    } finally {
      _pulling = false;
    }
  }

  /// Notify after a local write. Progress is debounced.
  @override
  void onLocalChanged(NovelSyncTopic topic, {String? bookId}) {
    unawaited(_handleLocalChanged(topic, bookId: bookId));
  }

  Future<void> _handleLocalChanged(
    NovelSyncTopic topic, {
    String? bookId,
  }) async {
    if (!await canSync) return;
    final gid = await resolvePersonalGroupId();
    if (gid == null) return;

    switch (topic) {
      case NovelSyncTopic.library:
        await _pushLibrary(gid);
      case NovelSyncTopic.selected:
        await _pushSelected(gid);
      case NovelSyncTopic.prefs:
        await _pushPrefs(gid);
      case NovelSyncTopic.progress:
        if (bookId == null || bookId.isEmpty) return;
        _pendingProgressBookId = bookId;
        _progressTimer?.cancel();
        _progressTimer = Timer(_progressDebounce, () {
          final id = _pendingProgressBookId;
          if (id == null) return;
          unawaited(_pushProgress(gid, id));
        });
    }
  }

  Future<void> _migrateOnceIfNeeded(int gid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(NovelReaderConstants.personalMigratedKey) == true) {
      return;
    }
    // Only push if cloud library is empty / missing.
    final cloud = await _kv.get(
      NovelReaderConstants.personalLibraryKey,
      groupId: gid,
    );
    final cloudEmpty = cloud.code != 0 ||
        cloud.data == null ||
        cloud.data!.value.trim().isEmpty ||
        cloud.data!.value == '[]';
    if (cloudEmpty) {
      await _pushLibrary(gid);
      await _pushSelected(gid);
      await _pushPrefs(gid);
      final books = await _storage.getLibrary(mergeCatalog: false);
      for (final book in books) {
        await _pushProgress(gid, book.id);
      }
    }
    await prefs.setBool(NovelReaderConstants.personalMigratedKey, true);
  }

  Future<void> _pushLibrary(int gid) async {
    final books = await _storage.getLibrary(mergeCatalog: false);
    final payload = jsonEncode(
      books.map((b) => b.toJson()).toList(growable: false),
    );
    await _kv.set(
      key: NovelReaderConstants.personalLibraryKey,
      value: payload,
      groupId: gid,
      tags: const [NovelReaderConstants.personalTag],
      ttl: 0,
    );
  }

  Future<void> _pullLibrary(int gid) async {
    final res = await _kv.get(
      NovelReaderConstants.personalLibraryKey,
      groupId: gid,
    );
    if (res.code != 0 || res.data == null) return;
    final remote = NovelBookEntry.decodeLibraryJson(res.data!.value);
    if (remote.isEmpty) return;
    // Keep catalog built-ins from local merge path; merge imported from cloud.
    final local = await _storage.getLibrary(mergeCatalog: false);
    final byId = <String, NovelBookEntry>{
      for (final b in local) b.id: b,
    };
    for (final b in remote) {
      if (b.source == NovelBookSource.imported) {
        byId[b.id] = b;
      } else {
        // Prefer local catalog fields; keep remote only if missing locally.
        byId.putIfAbsent(b.id, () => b);
      }
    }
    await _storage.replaceLibrary(byId.values.toList(growable: false));
  }

  Future<void> _pushSelected(int gid) async {
    final id = await _storage.getSelectedBookId();
    if (id == null) return;
    await _kv.set(
      key: NovelReaderConstants.personalSelectedKey,
      value: id,
      groupId: gid,
      tags: const [NovelReaderConstants.personalTag],
      ttl: 0,
    );
  }

  Future<void> _pullSelected(int gid) async {
    final res = await _kv.get(
      NovelReaderConstants.personalSelectedKey,
      groupId: gid,
    );
    if (res.code != 0 || res.data == null) return;
    final id = res.data!.value.trim();
    if (id.isEmpty) return;
    await _storage.setSelectedBookId(id, sync: false);
  }

  Future<void> _pushPrefs(int gid) async {
    final font = await _storage.getFontSize();
    final line = await _storage.getLineHeight();
    final theme = await _storage.getTheme();
    final volume = await _storage.getVolumeKeyTurnEnabled();
    Future<void> put(String key, String value) => _kv.set(
          key: key,
          value: value,
          groupId: gid,
          tags: const [NovelReaderConstants.personalTag],
          ttl: 0,
        );
    if (font != null) {
      await put(NovelReaderConstants.personalFontSizeKey, '$font');
    }
    if (line != null) {
      await put(NovelReaderConstants.personalLineHeightKey, '$line');
    }
    if (theme != null && theme.isNotEmpty) {
      await put(NovelReaderConstants.personalThemeKey, theme);
    }
    if (volume != null) {
      await put(NovelReaderConstants.personalVolumeKey, volume ? 'true' : 'false');
    }
  }

  Future<void> _pullPrefs(int gid) async {
    Future<String?> read(String key) async {
      final res = await _kv.get(key, groupId: gid);
      if (res.code != 0 || res.data == null) return null;
      final v = res.data!.value.trim();
      return v.isEmpty ? null : v;
    }

    final font = await read(NovelReaderConstants.personalFontSizeKey);
    if (font != null) {
      final n = int.tryParse(font);
      if (n != null) await _storage.setFontSize(n, sync: false);
    }
    final line = await read(NovelReaderConstants.personalLineHeightKey);
    if (line != null) {
      final n = int.tryParse(line);
      if (n != null) await _storage.setLineHeight(n, sync: false);
    }
    final theme = await read(NovelReaderConstants.personalThemeKey);
    if (theme != null) await _storage.setTheme(theme, sync: false);
    final volume = await read(NovelReaderConstants.personalVolumeKey);
    if (volume != null) {
      await _storage.setVolumeKeyTurnEnabled(
        volume == 'true',
        sync: false,
      );
    }
  }

  Future<void> _pushProgress(int gid, String bookId) async {
    final page = await _storage.getLastPageIndex(bookId);
    final offset = await _storage.getLastPageOffset(bookId);
    final ts = DateTime.now().millisecondsSinceEpoch;
    await _kv.set(
      key: NovelReaderConstants.personalProgressKey(bookId),
      value: '$page|$ts',
      groupId: gid,
      tags: const [NovelReaderConstants.personalTag],
      ttl: 0,
    );
    if (offset != null) {
      await _kv.set(
        key: NovelReaderConstants.personalProgressOffsetKey(bookId),
        value: '$offset|$ts',
        groupId: gid,
        tags: const [NovelReaderConstants.personalTag],
        ttl: 0,
      );
    }
  }

  Future<void> _pullProgress(int gid, String bookId) async {
    final pageRes = await _kv.get(
      NovelReaderConstants.personalProgressKey(bookId),
      groupId: gid,
    );
    if (pageRes.code == 0 && pageRes.data != null) {
      final parsed = _parseTsValue(pageRes.data!.value);
      if (parsed != null) {
        final local = await _storage.getLastPageIndex(bookId);
        final localTs = await _storage.getProgressTimestamp(bookId);
        if (localTs == null || parsed.ts >= localTs) {
          await _storage.setLastPageIndex(
            bookId,
            parsed.value,
            sync: false,
            timestampMs: parsed.ts,
          );
        } else if (local > parsed.value) {
          // local newer — leave as-is
        }
      }
    }

    final offsetRes = await _kv.get(
      NovelReaderConstants.personalProgressOffsetKey(bookId),
      groupId: gid,
    );
    if (offsetRes.code == 0 && offsetRes.data != null) {
      final parsed = _parseTsValue(offsetRes.data!.value);
      if (parsed != null) {
        await _storage.setLastPageOffset(
          bookId,
          parsed.value,
          sync: false,
        );
      }
    }
  }

  ({int value, int ts})? _parseTsValue(String raw) {
    final parts = raw.split('|');
    if (parts.isEmpty) return null;
    final value = int.tryParse(parts[0].trim());
    if (value == null) return null;
    final ts = parts.length > 1
        ? int.tryParse(parts[1].trim()) ?? 0
        : 0;
    return (value: value, ts: ts);
  }

  void dispose() {
    _progressTimer?.cancel();
  }
}
