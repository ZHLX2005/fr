import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/api/authhub/idp_session_store.dart';
import 'package:xiaodouzi_fr/api/token/token_storage.dart';

/// 登录态与业务 token 的**存储隔离**。
///
/// 背景：认证中心的全局会话是 30 天 + 24h 看门狗续期（服务端实测 TTL 一律 30 天），
/// 所以「登录态突然没了」不可能是服务端过期，只能是客户端把它弄丢了。
///
/// 本组测试盯的是一个具体的撞键事故：
///   IdpSessionStore   曾用 SharedPreferences['idp_session'] 存统一登录平台的会话
///   SharedPrefsTokenStorage 的「遗留键清理」列表里也列了 'idp_session'
/// 而 TokenManager.setAccessToken() → TokenStorage.save() 会执行那次清理。
/// 于是：**每铸一次业务 token，就顺手把统一登录平台的登录态从磁盘上删掉**。
///
/// 症状正是用户报告的：「登录之后过一会儿就要重新登录」——
/// 内存里的 _cached 还活着（同一进程内看不出问题），一重启 App 登录态就没了。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存业务 token 不得删除统一登录平台的登录态', () async {
    final sessionStore = IdpSessionStore();
    final tokenStore = SharedPrefsTokenStorage();

    // ① 先登录：登录态落盘
    await sessionStore.save('sid-abc-123');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('authhub_idp_session'), 'sid-abc-123',
        reason: '前置：登录态应当已经在磁盘上');

    // ② 再铸一枚业务 token（这是登录后必然发生的一步）
    await tokenStore.save(accessToken: 'business-jwt');

    // ③ 登录态必须还在
    expect(prefs.getString('authhub_idp_session'), 'sid-abc-123',
        reason: '保存业务 token 不得清掉统一登录平台的登录态：'
            '两者是两枚独立凭据，生命周期与吊销路径都不同');

    // ④ 且重开 App 后仍能读回（跨进程存活）
    final reopened = IdpSessionStore();
    expect(await reopened.read(), 'sid-abc-123',
        reason: 'App 重启后应仍持有登录态，否则用户会被迫重新登录');
  });

  test('清理业务 token 同样不得删除统一登录平台的登录态', () async {
    final sessionStore = IdpSessionStore();
    final tokenStore = SharedPrefsTokenStorage();

    await sessionStore.save('sid-xyz');
    await tokenStore.save(accessToken: 'business-jwt');
    await tokenStore.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('authhub_idp_session'), 'sid-xyz',
        reason: '「退出业务登录」与「退出统一登录平台」是两件事：'
            '登出业务 token 不该把统一登录平台的会话一起清掉');
  });

  test('业务 token 确实落盘、确实被清掉（防止测试本身空转）', () async {
    final tokenStore = SharedPrefsTokenStorage();

    await tokenStore.save(accessToken: 'business-jwt');
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_access_token'), 'business-jwt');

    await tokenStore.clear();
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_access_token'), isNull);
  });

  test('撞键事故期间写入的旧登录态会被迁移，不需要用户重新登录', () async {
    // 老版本把登录态写在 'idp_session'（与 Cookie 同名）。
    // 升级后必须认它一次：服务端那枚会话还有效，
    // 丢掉就等于让老用户白白重新登录一次。
    SharedPreferences.setMockInitialValues({'idp_session': 'sid-legacy'});

    final store = IdpSessionStore();
    expect(await store.read(), 'sid-legacy',
        reason: '旧键里的登录态应当被认领');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('authhub_idp_session'), 'sid-legacy',
        reason: '应当迁移到新键');
    expect(prefs.getString('idp_session'), isNull,
        reason: '迁移后不该留两份：留两份会让下一次读分不清哪份是真的');
  });

  test('登出登录态时旧键也一并清掉', () async {
    SharedPreferences.setMockInitialValues({'idp_session': 'sid-legacy'});
    final store = IdpSessionStore();
    await store.read(); // 触发迁移

    await store.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('authhub_idp_session'), isNull);
    expect(prefs.getString('idp_session'), isNull,
        reason: '旧键是同一次登录的遗留副本，留着就等于登录态没退干净');
  });
}
