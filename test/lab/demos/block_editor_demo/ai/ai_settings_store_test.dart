import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/ai_settings_store.dart';

void main() {
  AiSettingsStore storeWith(String prefix) => AiSettingsStore(prefsKey: 'test_$prefix');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns empty defaults when nothing saved', () async {
    final store = storeWith('empty');
    final s = await store.load();
    expect(s.apiKey, '');
    expect(s.model, '');
    expect(s.baseUrl, '');
    expect(s.isConfigured, isFalse);
  });

  test('save then load roundtrips all fields', () async {
    final store = storeWith('roundtrip');
    await store.save(const AiSettings(
      apiKey: 'sk-xxx',
      model: 'glm-4.7',
      baseUrl: 'https://example.com',
    ));
    final loaded = await store.load();
    expect(loaded.apiKey, 'sk-xxx');
    expect(loaded.model, 'glm-4.7');
    expect(loaded.baseUrl, 'https://example.com');
    expect(loaded.isConfigured, isTrue);
  });
}
