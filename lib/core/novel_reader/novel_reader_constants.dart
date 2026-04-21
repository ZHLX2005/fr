class NovelReaderConstants {
  const NovelReaderConstants._();

  static const String title = 'Novel Reader';
  static const String description =
      'Single-book TXT reader with local cache, pagination and page curl.';
  static const String bookTitle = 'Seven Day';
  static const String builtInBookId = 'builtin_seven_day';
  static const String remoteUrl =
      'https://kklrbynhqpwwhtfanqwt.supabase.co/storage/v1/object/public/music/assets/books/sevenDay.txt';
  static const String localDirectory = 'novel_reader';
  static const String builtInFileName = 'sevenDay.txt';
  static const String libraryKey = 'lab.novel_reader.library';
  static const String selectedBookKey = 'lab.novel_reader.selected_book_id';
  static const String progressKeyPrefix = 'lab.novel_reader.last_page_index';
  static const String progressOffsetKeyPrefix = 'lab.novel_reader.last_page_offset';
  static const String fontSizeKey = 'lab.novel_reader.font_size';
  static const String lineHeightKey = 'lab.novel_reader.line_height';
  static const String themeKey = 'lab.novel_reader.theme';

  static String progressKey(String bookId) => '$progressKeyPrefix.$bookId';

  static String progressOffsetKey(String bookId) =>
      '$progressOffsetKeyPrefix.$bookId';
}
