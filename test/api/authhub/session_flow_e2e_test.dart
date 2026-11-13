// ignore_for_file: avoid_print
// 本文件是诊断 / e2e 链路脚本，控制台输出即测试结果本身，
// 不属于 avoid_print 所指的「生产代码」。
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_pkce.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_models.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_qr_endpoint.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_session_client.dart';
import 'package:xiaodouzi_fr/api/authhub/idp_session_store.dart';
import 'package:xiaodouzi_fr/api/token/token_storage.dart';

/// 验证新架构的核心断言：**只用一份登录态**，既能换授权码、又能批准扫码。
///
/// 打真实认证中心。这些步骤的错误全部是"与服务端实际约定不符"类型的
/// （Cookie 名对不对、authorize 跟不跟随重定向、consent 返回的是不是裸对象、
/// state 比不比得上），MockClient 一条都测不出来。
///
/// 服务不可达时整组跳过，与仓库其它依赖外部服务的测试同一口径。
const idpBase = String.fromEnvironment('GOAH_IDP', defaultValue: 'http://127.0.0.1:18080');
const rpClient = String.fromEnvironment('GOAH_RP_CLIENT', defaultValue: 'local-sso-check');
const rpRedirect =
    String.fromEnvironment('GOAH_RP_REDIRECT', defaultValue: 'http://127.0.0.1:19999/callback');
const seedUser = String.fromEnvironment('GOAH_USER', defaultValue: 'test');
const seedPass = String.fromEnvironment('GOAH_PASS', defaultValue: 'test123456');

/// 内存版登录态存储：测试不碰 SharedPreferences。
class _MemSessionStore extends IdpSessionStore {
  String? v;
  @override
  Future<String?> read() async => v;
  @override
  Future<void> save(String cookieValue) async => v = cookieValue;
  @override
  Future<void> clear() async => v = null;
  @override
  Future<bool> get exists async => (v ?? '').isNotEmpty;
}

Future<bool> _reachable() async {
  try {
    final r = await http
        .get(Uri.parse('$idpBase/.well-known/openid-configuration'))
        .timeout(const Duration(seconds: 3));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// main 必须是 async：可达性要在**注册用例之前**问出来。
///
/// 原来写成 `setUpAll(() => up = await _reachable())` + 每条用例开头
/// `if (!up) return;`，后果是认证中心不可达时三条断言一条都没执行，
/// 而 runner 报的是 **All tests passed**——把"没测"交付成"测过了"。
/// 本项目已经因为 `skip 当成 pass` 踩过一次，这次是同一种错的另一个写法。
///
/// 现在不可达会显式显示为 SKIPPED 并带上怎么让它可达。
Future<void> main() async {
  final up = await _reachable();
  final skipReason = up
      ? false
      : '认证中心 $idpBase 不可达，整组未执行。'
          '指向一个可登录的实例：flutter test --dart-define=GOAH_IDP=http://host:port';

  test('口令 → 登录态 → 静默换授权码', () async {
    if (!up) fail('不该被执行到：可达性预检查说服务不可达');
    final store = _MemSessionStore();
    final client = AuthHubSessionClient(store: store, issuer: idpBase);

    final who = await client.signInWithPassword(
        username: seedUser, password: seedPass);
    expect(who.username, isNotEmpty);
    expect(await store.exists, isTrue, reason: '登录态必须被存下来');
    print('登录态已获取：账号=${who.username} 昵称=${who.displayName}');

    // 关键一步：App 手里只有登录态，没有 access_token、没有 refresh_token，
    // 却要为一个依赖方拿到授权码。这一步成立，"静默换业务 token"才成立。
    final pkce = AuthPkce.generate();
    final issued = await client.mintCodeForClient(
      client: rpClient,
      redirectUri: rpRedirect,
      scopes: const ['openid', 'profile', 'email'],
      state: pkce.state,
      nonce: pkce.nonce,
      codeChallenge: pkce.codeChallenge,
    );
    expect(issued.code, isNotEmpty);
    expect(issued.state, pkce.state,
        reason: 'state 必须原样回到调用方，否则无从判断这次回调是不是给自己的');
    print('授权码已换到：${issued.code.substring(0, 12)}…（App 全程未持有 token）');

    client.close();
  }, skip: skipReason);

  test('没有登录态时，换码与扫码批准都要明确拒绝而不是发无凭据请求', () async {
    if (!up) fail('不该被执行到：可达性预检查说服务不可达');
    final store = _MemSessionStore();
    final client = AuthHubSessionClient(store: store, issuer: idpBase);
    final qr = AuthHubQrEndpoint(issuer: idpBase, sessionStore: store);

    final pkce = AuthPkce.generate();
    expect(
      () => client.mintCodeForClient(
        client: rpClient,
        redirectUri: rpRedirect,
        scopes: const ['openid'],
        state: pkce.state,
        nonce: pkce.nonce,
        codeChallenge: pkce.codeChallenge,
      ),
      throwsA(isA<Object>()),
    );
    // 端点自己取登录态；没有就当场抛，而不是发一个必然 401 的请求
    await expectLater(qr.preview('qrt_whatever'), throwsA(isA<Object>()));

    client.close();
    qr.close();
  }, skip: skipReason);

  test('同一份登录态可直接用于批准扫码（不需要另外的 token）', () async {
    if (!up) fail('不该被执行到：可达性预检查说服务不可达');
    final store = _MemSessionStore();
    final client = AuthHubSessionClient(store: store, issuer: idpBase);
    final qr = AuthHubQrEndpoint(issuer: idpBase, sessionStore: store);

    await client.signInWithPassword(username: seedUser, password: seedPass);
    // 领取响应里的 username 是**账号名**，不是登录名：
    // 登录名可能是邮箱，而 username 是账号名（两者在 go-ah 里是不同字段）。
    // 所以这里跟"刚刚登录成功的那个身份"比，而不是跟 seedUser 字面比。
    final signedIn = await client.me();
    expect(signedIn, isNotNull);

    // 建票用匿名 PC 侧路径（不带登录态），批准用手机侧路径（带登录态）。
    // 两者共用同一个 store 实例，正是"一份登录态两个用途"的正当形态：
    // 批准扫码和换业务 token 回答的是同一个问题——这台设备是否已登录。
    final anonStore = _MemSessionStore();
    final pcQr = AuthHubQrEndpoint(issuer: idpBase, sessionStore: anonStore);
    final session = await pcQr.create();

    final pv = await qr.preview(session.ticket);
    expect(pv.hasMeaningfulDeviceInfo, isTrue,
        reason: '画像为空说明 preview 又打错端点了');
    print('设备画像：ua=${pv.pcUa} ip=${pv.pcIp} geo=${pv.pcGeo}');

    await qr.scan(session.ticket);
    expect(await pcQr.poll(session.ticket), QrStatus.scanned);

    await qr.confirm(session.ticket);
    expect(await pcQr.poll(session.ticket), QrStatus.confirmed);

    final claimed = await pcQr.claim(session.ticket);
    expect(claimed['username'], signedIn!.username);

    // 一次性
    await expectLater(pcQr.claim(session.ticket), throwsA(anything));

    client.close();
    qr.close();
    pcQr.close();
  }, skip: skipReason);

  test('登录态落到磁盘后跨进程存活（撞键事故的回归防线）', () async {
    if (!up) fail('不该被执行到：可达性预检查说服务不可达');
    // 这条用**真实的 SharedPreferences**（不用内存版 store）：
    // 事故的根因在"落盘"这一层，内存版 store 天然测不出来。
    SharedPreferences.setMockInitialValues({});

    final store = IdpSessionStore();
    final client = AuthHubSessionClient(store: store, issuer: idpBase);

    await client.signInWithPassword(username: seedUser, password: seedPass);
    expect(await store.exists, isTrue, reason: '登录态必须被存下来');

    // 模拟"铸一枚业务 token"：这正是历史上把登录态从磁盘删掉的那一步。
    await SharedPrefsTokenStorage().save(accessToken: 'business-jwt');

    // 换一个 store 实例 = 模拟 App 重启（内存缓存清空，只剩磁盘）
    final afterRestart = IdpSessionStore();
    expect(await afterRestart.exists, isTrue,
        reason: 'App 重启后登录态必须还在：服务端那边是 30 天有效期 + 看门狗续期，'
            '客户端不该主动把它弄丢');

    // 且重铸授权码仍然成功 —— 这才是"业务令牌失效时用登录态静默重铸"的闭环。
    final pkce = AuthPkce.generate();
    final issued = await client.mintCodeForClient(
      client: rpClient,
      redirectUri: rpRedirect,
      scopes: const ['openid', 'profile', 'email'],
      state: pkce.state,
      nonce: pkce.nonce,
      codeChallenge: pkce.codeChallenge,
    );
    expect(issued.code, isNotEmpty,
        reason: '重启后仍应能用登录态静默换到授权码');

    client.close();
  }, skip: skipReason);
}
