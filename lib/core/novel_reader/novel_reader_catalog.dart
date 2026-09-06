// lib/core/novel_reader/novel_reader_catalog.dart
//
// Public catalog of built-in novels (group 190).
// Admin (ve game-skin-admin → 小说 tab) publishes `novel_reader_catalog:index`.
// Client reads anonymously via PublicKvReader; falls back to hard-coded Seven Day.

import '../game_kit/skin/public_kv_reader.dart';
import 'novel_reader_constants.dart';
import 'novel_reader_models.dart';

/// Default backend host (same as skins / line songs).
PublicKvReader novelCatalogKvReader({
  String baseUrl = NovelReaderConstants.defaultBaseUrl,
  int groupId = NovelReaderConstants.catalogGroupId,
}) =>
    PublicKvReader(baseUrl: baseUrl, groupId: groupId);

/// Hard-coded fallback when catalog is missing.
NovelBookEntry novelFallbackBuiltIn() => const NovelBookEntry(
      id: NovelReaderConstants.builtInBookId,
      title: NovelReaderConstants.bookTitle,
      fileName: NovelReaderConstants.builtInFileName,
      source: NovelBookSource.builtIn,
      remoteUrl: NovelReaderConstants.remoteUrl,
    );

/// Parse catalog JSON array into built-in [NovelBookEntry]s.
List<NovelBookEntry> parseNovelCatalog(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = NovelBookEntry.decodeLibraryJson(raw);
    return decoded
        .where((e) => e.id.isNotEmpty && e.title.isNotEmpty)
        .map(
          (e) => NovelBookEntry(
            id: e.id,
            title: e.title,
            fileName: e.fileName.isEmpty ? '${e.id}.txt' : e.fileName,
            source: NovelBookSource.builtIn,
            remoteUrl: e.remoteUrl,
            importedAt: e.importedAt,
            fileId: e.fileId,
            updatedAt: e.updatedAt,
          ),
        )
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// Best-effort fetch of public catalog. Never throws.
Future<List<NovelBookEntry>> fetchNovelCatalog({
  PublicKvReader? reader,
}) async {
  final kv = reader ?? novelCatalogKvReader();
  try {
    final raw = await kv.readString(NovelReaderConstants.catalogKvKey);
    final books = parseNovelCatalog(raw);
    if (books.isNotEmpty) return books;
  } catch (_) {
    // fall through
  }
  return const [];
}
