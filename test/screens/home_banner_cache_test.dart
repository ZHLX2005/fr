import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/screens/profile/profile_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeBannerCache.resetForTest();
  });

  test('warmUp 读 home_banner_path 填 path 并置 ready', () async {
    SharedPreferences.setMockInitialValues({'home_banner_path': '/x/banner.jpg'});
    await HomeBannerCache.warmUp();
    expect(HomeBannerCache.path, '/x/banner.jpg');
    expect(HomeBannerCache.ready, isTrue);
  });

  test('warmUp 无值时 path=null 但 ready=true', () async {
    await HomeBannerCache.warmUp();
    expect(HomeBannerCache.path, isNull);
    expect(HomeBannerCache.ready, isTrue);
  });

  test('warmUp 幂等，二次不重读', () async {
    SharedPreferences.setMockInitialValues({'home_banner_path': '/a'});
    await HomeBannerCache.warmUp();
    // 第二次前改 mock 值，幂等应保留首次结果
    SharedPreferences.setMockInitialValues({'home_banner_path': '/b'});
    await HomeBannerCache.warmUp();
    expect(HomeBannerCache.path, '/a');
  });
}
