// lib/core/chess/skins/chess_skin_meta_sync.dart
//
// Thin compat wrapper — preserves `fetchAndMergeSkins()` signature.

import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/public_kv_reader.dart';
import 'chess_skin.dart';

Future<bool> fetchAndMergeSkins({
  PublicKvReader? reader,
  FileResolver? resolver,
}) async {
  return ChessSkinBundle.bundle.fetchAndMerge(
    reader: reader,
    resolver: resolver,
    defaultBaseUrl: kDefaultChessSkinBaseUrl,
  );
}
