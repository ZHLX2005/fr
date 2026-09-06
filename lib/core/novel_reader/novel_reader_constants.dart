class NovelReaderConstants {
  const NovelReaderConstants._();

  static const String title = 'Novel Reader';
  static const String description =
      'Single-book TXT reader with local cache, pagination and page curl.';
  static const String bookTitle = 'Seven Day';
  static const String builtInBookId = 'builtin_seven_day';

  /// Fallback download URL when public catalog is empty / unreachable.
  static const String remoteUrl =
      'https://kklrbynhqpwwhtfanqwt.supabase.co/storage/v1/object/public/music/assets/books/sevenDay.txt';
  static const String localDirectory = 'novel_reader';
  static const String builtInFileName = 'sevenDay.txt';

  // ── Local SharedPreferences ───────────────────────────────────────
  static const String libraryKey = 'lab.novel_reader.library';
  static const String selectedBookKey = 'lab.novel_reader.selected_book_id';
  static const String progressKeyPrefix = 'lab.novel_reader.last_page_index';
  static const String progressOffsetKeyPrefix = 'lab.novel_reader.last_page_offset';
  static const String fontSizeKey = 'lab.novel_reader.font_size';
  static const String lineHeightKey = 'lab.novel_reader.line_height';
  static const String themeKey = 'lab.novel_reader.theme';
  static const String volumeKeyTurnKey = 'lab.novel_reader.volume_key_turn';
  static const String cloudSyncEnabledKey = 'lab.novel_reader.cloud_sync_enabled';
  static const String personalMigratedKey = 'lab.novel_reader.kv_migrated_v1';

  // ── Public catalog (group 190, admin-managed) ─────────────────────
  static const String catalogKvKey = 'novel_reader_catalog:index';
  static const String catalogTag = 'novel-reader-catalog';
  static const int catalogGroupId = 190;
  static const String defaultBaseUrl = 'http://47.110.80.47:8988';

  // ── Personal sync keys (per-user group) ───────────────────────────
  static const String personalKeyPrefix = 'fr_novel_reader:';
  static const String personalLibraryKey = '${personalKeyPrefix}library';
  static const String personalSelectedKey = '${personalKeyPrefix}selected_book_id';
  static const String personalFontSizeKey = '${personalKeyPrefix}font_size';
  static const String personalLineHeightKey = '${personalKeyPrefix}line_height';
  static const String personalThemeKey = '${personalKeyPrefix}theme';
  static const String personalVolumeKey = '${personalKeyPrefix}volume_key_turn';
  static const String personalTag = 'novel-reader';

  static String progressKey(String bookId) => '$progressKeyPrefix.$bookId';

  static String progressOffsetKey(String bookId) =>
      '$progressOffsetKeyPrefix.$bookId';

  static String personalProgressKey(String bookId) =>
      '${personalKeyPrefix}progress:$bookId';

  static String personalProgressOffsetKey(String bookId) =>
      '${personalKeyPrefix}progress_offset:$bookId';
}
