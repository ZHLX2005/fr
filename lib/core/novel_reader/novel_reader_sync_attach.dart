import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/goframe/group/group_endpoint.dart';
import '../../api/goframe/kv/kv_endpoint.dart';
import '../../api/token/token_manager.dart';
import '../../api/token/token_storage.dart';
import 'novel_reader_storage.dart';
import 'novel_reader_sync.dart';

/// Attach personal KV sync to [storage]. Caller owns [dispose].
NovelReaderSync attachNovelReaderSync(NovelReaderStorage storage) {
  final tokens = TokenManager(storage: SharedPrefsTokenStorage());
  final client = ApiClient(
    config: ApiConfig.production(),
    tokenManager: tokens,
  );
  final sync = NovelReaderSync(
    kv: KvEndpoint(client),
    groups: GroupEndpoint(client),
    tokens: tokens,
    storage: storage,
  );
  storage.sync = sync;
  return sync;
}
