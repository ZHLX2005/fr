// 联调冒烟：拿本机（或经桥的）nx-kv，验证「契约生成物 + fr 适配层」整条路。
//
// 这是个命令行脚本，输出就是它的产出物 —— print 在这里不是调试残留。
// ignore_for_file: avoid_print
//
// 用法：
//   dart run tool/nxkv_smoke.dart                       # 直连本机 nx-kv 面板（:7877）
//   dart run tool/nxkv_smoke.dart http://<bridge>/nx-kv # 经 mn-ws 桥（需真凭据，见下）
//
// 直连时不需要登录：nx-kv 自己的服务端不校验 `X-Mn-Ws-Token`（门禁在桥那层），
// 所以下面塞一个占位凭据只是为了让 [MnWsEndpoint] 肯发请求。
//
// 这个脚本故意**不碰 flutter** —— 它证明的是「契约包能在纯 Dart 环境里跑」，
// 顺带也证明 fr 的适配层没有偷偷依赖 UI 层。
import 'package:xiaodouzi_fr/api/mnws/mnws_endpoint.dart';
import 'package:xiaodouzi_fr/api/mnws/mnws_models.dart';
import 'package:xiaodouzi_fr/api/nxkv/nxkv_client.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : 'http://127.0.0.1:7877';
  final endpoint = MnWsEndpoint(
    baseUrl: base,
    grantReader: () async => const MnWsGrant(
      token: 'smoke-placeholder',
      userId: '0',
      email: '',
      nickname: 'smoke',
      clientId: 'nxkv-smoke',
      deviceName: 'nxkv-smoke',
      tokenExpiresAt: null,
    ),
  );

  final api = NxKvApi();
  print('基址      $base');
  print('端侧契约  ${api.contractHash}（nx-kv ${api.contractVersion}）');

  final drift = await api.contractDrift(endpoint);
  print('契约对账  ${drift ?? '一致'}');

  final kv = api.bind(endpoint);
  final tasks = await kv.localtaskList();
  final boot = await kv.systemBootstrap();

  print('主题      ${tasks.topics.length} 个 · 等待中 ${tasks.waiting}');
  print('命令表    ${boot.commands.length} 条 · nx-kv ${boot.version} · 端口 ${boot.defaultPort}');
  for (final t in tasks.topics.take(5)) {
    print('  · ${t.key}  pending=${t.pending} claimed=${t.claimed} done=${t.done}');
  }
  if (tasks.topics.length > 5) print('  …还有 ${tasks.topics.length - 5} 个');
}
