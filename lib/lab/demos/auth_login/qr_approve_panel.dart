import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/authhub/authhub_config.dart';
import '../../../api/authhub/authhub_exception.dart';
import '../../../api/authhub/authhub_models.dart';
import '../../../api/providers/api_providers.dart';
import 'const_auth_login.dart';

/// 扫码批准面板：拍下电脑上的二维码 → 服务端解码 → 展示对方设备画像 → 确认 / 拒绝。
///
/// ── 为什么是"拍照上传"而不是"相机实时预览" ──────────────────────────────
/// 实时预览要在客户端解二维码，那意味着背上 ML Kit 条码引擎
/// （libbarhopper_v3.so 4.2MB + 0.8MB .tflite 模型）—— 为了读一张
/// **电脑屏幕上的**登录码，APK 平白多 5MB。
/// 改成"拍一张照传上去、服务端解码"后，这 5MB 整块消失；
/// 代价只是从"对准即扫"变成"对准 + 按一下快门"（image_picker 已经
/// 在项目里，不额外增加原生体积）。
///
/// ── 为什么"确认"按钮可能压根不出现 ──────────────────────────────────────
///
/// 用户点下确认，效果等价于在另一台机器上输入自己的密码。他能核对这件事
/// 对不对，靠的只有服务端算出来的那份设备画像（浏览器·系统 / IP / 来源 / 时间）。
/// 所以画像取不到或全空时，这里**只报错、不给按钮** ——
/// 让人对着一片空白点"确认登录"，是把安全决策退化成了手滑。
class QrApprovePanel extends ConsumerStatefulWidget {
  const QrApprovePanel({super.key});

  @override
  ConsumerState<QrApprovePanel> createState() => _QrApprovePanelState();
}

class _QrApprovePanelState extends ConsumerState<QrApprovePanel> {
  final ImagePicker _picker = ImagePicker();

  String? _ticket;
  QrPreview? _preview;
  String? _error;
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    super.dispose();
  }

  /// 拍照 → 上传 → 服务端解码 → 解析 ticket。
  ///
  /// 解码失败与"拍到的不是登录码"是两种不同的错，给用户的提示必须分开：
  /// 前者让人重拍，后者让人去刷新电脑上的码 —— 混成一句"扫不出来"，
  /// 用户只能反复重拍。
  Future<void> _pickAndDecode() async {
    if (_busy) return;
    final XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        // 压到 1600px 宽：足够服务端识别，又不至于把 8MB 上限顶满。
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法打开相机：$e');
      return;
    }
    if (shot == null) return; // 用户取消

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uint8List bytes = await shot.readAsBytes();
      final raw =
          await ref.read(authHubQrEndpointProvider).decodeImage(bytes);
      final ticket = AuthHubConfig.parseTicketFromScan(raw);
      if (ticket == null) {
        throw const AuthHubException(
          error: 'not_login_qr',
          message: '这张图里不是登录二维码，请对准电脑上显示的那一张。',
        );
      }
      if (!mounted) return;
      await _load(ticket);
    } on AuthHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '识别失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _load(String ticket) async {
    setState(() {
      _busy = true;
      _error = null;
      _ticket = ticket;
      _preview = null;
    });
    try {
      // 凭据由端点自己从登录态存储里取；这里只判断「有没有登录态」，
      // 因为要给用户的是可行动的提示，而不是一个从深处冒出来的 401。
      if (!await ref.read(idpSessionStoreProvider).exists) {
        // 未登录不是"再等等"，而是一条必须明确说出来的前置条件：
        // 没有身份就没有批准权。静默重试只会让人以为相机坏了。
        throw const AuthHubException(
          error: 'unauthenticated',
          message: '还没有登录统一认证中心，请先在「统一登录」页完成登录后再扫码。',
        );
      }
      final preview = await ref.read(authHubQrEndpointProvider).preview(ticket);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
      });
      // 上报"已扫码"，让 PC 那边从"等待扫码"变成"已扫码，请在手机确认"。
      // 这一步失败不影响本机确认，所以只记不抛。
      if (preview.status == QrStatus.pending) {
        unawaited(_safeScan(ticket));
      }
    } on AuthHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.error == 'unauthenticated'
            ? e.message
            : '读取登录请求失败：${e.message}';
        _busy = false;
      });
    }
  }

  Future<void> _safeScan(String ticket) async {
    try {
      await ref.read(authHubQrEndpointProvider).scan(ticket);
    } catch (_) {
      // 并发下可能已被另一台设备扫过；pending|scanned → confirmed 两条路后端都认，
      // 所以这里静默即可，不该把一次无害竞态报成故障。
    }
  }

  Future<void> _decide({required bool approve}) async {
    final ticket = _ticket;
    if (ticket == null) return;
    setState(() => _busy = true);
    try {
      final qr = ref.read(authHubQrEndpointProvider);
      if (approve) {
        await qr.confirm(ticket);
      } else {
        await qr.refuse(ticket);
      }
      if (!mounted) return;
      setState(() {
        _done = true;
        _busy = false;
      });
    } on AuthHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${approve ? '确认' : '拒绝'}失败：${e.message}';
        _busy = false;
      });
      // 状态可能已经变了（票过期/已被领），重新取一次数比留着一块
      // 仍然摆着"确认登录"按钮的过期界面诚实。
      await _load(ticket);
    }
  }

  void _reset() {
    setState(() {
      _ticket = null;
      _preview = null;
      _error = null;
      _done = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_done) {
      return _ResultView(
        icon: Icons.check_circle_outline,
        title: '已处理',
        message: '这台电脑可以继续了，这页可以关掉。',
        actionLabel: '再扫一张',
        onAction: _reset,
      );
    }

    if (_ticket != null) return _confirmView(context, scheme);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    '拍下电脑上显示的登录二维码',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '照片只用于识别这张二维码，会立刻上传到认证中心解码，'
                    '不会保存在手机上。',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickAndDecode,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('拍照识别二维码'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _confirmView(BuildContext context, ColorScheme scheme) {
    final p = _preview;
    final canApprove = p != null && p.hasMeaningfulDeviceInfo && p.status.canApprove;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy && p == null) const Center(child: CircularProgressIndicator()),
          if (p == null && !_busy) ...[
            Icon(Icons.report_gmailerrorred_outlined, color: scheme.error, size: 36),
            const SizedBox(height: 10),
            Text(_error ?? '无法读取这次登录请求', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _reset, child: const Text('返回重新扫')),
          ],
          if (p != null) ...[
            Text('收到一个登录请求', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('要登录的设备',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(p.pcUa.isEmpty ? '未知设备' : p.pcUa,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('来源 ${p.pcGeo.isEmpty ? '未知' : p.pcGeo} · '
                        '${p.pcIp.isEmpty ? '未知 IP' : p.pcIp}',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text('发起于 ${_fmtTime(p.pcCreatedAt)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!p.status.canApprove)
              _Banner(
                color: scheme.tertiary,
                text: p.status == QrStatus.confirmed
                    ? '这次登录已经批准过了，请等待电脑那边完成。'
                    : p.status == QrStatus.consumed
                        ? '这次登录已经完成。'
                        : '这张二维码已经失效，请让对方刷新后重扫。',
              )
            else if (!p.hasMeaningfulDeviceInfo)
              _Banner(color: scheme.error, text: AuthLoginConst.errNoDeviceInfo)
            else
              _Banner(color: scheme.secondary, text: AuthLoginConst.warnApproveMeaning),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canApprove && !_busy ? () => _decide(approve: false) : null,
                    child: const Text(AuthLoginConst.btnRefuse),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: canApprove && !_busy ? () => _decide(approve: true) : null,
                    child: Text(_busy
                        ? '提交中…'
                        : AuthLoginConst.btnApprove),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: _reset, child: const Text('取消，重新扫码')),
          ],
        ],
      ),
    );
  }
}

/// 后端返回的是 RFC3339（带偏移），这里只取到分钟并按本地时区显示。
///
/// 刻意不在服务端格式化：认证中心读出来的时间是 UTC，
/// 在服务端格式化成无偏移串会让用户以为"发起时间比我操作早了 8 小时"。
String _fmtTime(String raw) {
  if (raw.isEmpty) return '未知';
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  final local = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _Banner extends StatelessWidget {
  final Color color;
  final String text;
  const _Banner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _ResultView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _ResultView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
