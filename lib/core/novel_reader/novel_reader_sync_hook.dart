/// Narrow hook so [NovelReaderStorage] can notify sync without importing it.
enum NovelSyncTopic { library, selected, progress, prefs }

abstract interface class NovelReaderSyncHook {
  void onLocalChanged(NovelSyncTopic topic, {String? bookId});
}
