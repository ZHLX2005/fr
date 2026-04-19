class NovelReaderConstants {
  const NovelReaderConstants._();

  static const String title = 'Novel Reader';
  static const String description =
      'Single-book TXT reader with local cache, pagination and page curl.';
  static const String bookTitle = 'Seven Day';
  static const String remoteUrl =
      'https://kklrbynhqpwwhtfanqwt.supabase.co/storage/v1/object/public/music/assets/books/sevenDay.txt';
  static const String localDirectory = 'novel_reader';
  static const String localFileName = 'sevenDay.txt';
  static const String progressKey = 'lab.novel_reader.last_page_index';
  static const String progressOffsetKey = 'lab.novel_reader.last_page_offset';
}
