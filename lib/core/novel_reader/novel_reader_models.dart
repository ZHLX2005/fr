import 'dart:convert';

enum NovelBookSource { builtIn, imported }

class NovelBookEntry {
  const NovelBookEntry({
    required this.id,
    required this.title,
    required this.fileName,
    required this.source,
    this.remoteUrl,
    this.importedAt,
    this.fileId,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final NovelBookSource source;
  final String? remoteUrl;
  final int? importedAt;

  /// Optional File API id (route B reserved).
  final String? fileId;

  /// Optional LWW marker (ms).
  final int? updatedAt;

  bool get isBuiltIn => source == NovelBookSource.builtIn;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'fileName': fileName,
      'source': source.name,
      'remoteUrl': remoteUrl,
      'importedAt': importedAt,
      if (fileId != null) 'fileId': fileId,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  factory NovelBookEntry.fromJson(Map<String, dynamic> json) {
    final sourceName =
        json['source'] as String? ?? NovelBookSource.imported.name;
    final source = NovelBookSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => NovelBookSource.imported,
    );
    return NovelBookEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      source: source,
      remoteUrl: json['remoteUrl'] as String?,
      importedAt: (json['importedAt'] as num?)?.toInt(),
      fileId: json['fileId'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
    );
  }

  static List<NovelBookEntry> decodeLibraryJson(String raw) {
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final books = <NovelBookEntry>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        books.add(NovelBookEntry.fromJson(item));
      } else if (item is Map) {
        books.add(NovelBookEntry.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return books;
  }
}
