import 'dart:io';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// 原生通知功能测试页面
class NativeNotificationsPage extends StatefulWidget {
  const NativeNotificationsPage({super.key});

  @override
  State<NativeNotificationsPage> createState() =>
      _NativeNotificationsPageState();
}

class _NativeNotificationsPageState extends State<NativeNotificationsPage> {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  // 当前通知权限状态字符串 (用于 UI 展示)
  String _permissionStatusText = '未查询';
  // 当前是否已授权 (用于按钮 disabled 状态)
  bool _permissionGranted = false;

  // 通知通道ID（Android）
  static const String _androidChannelId = 'fr_notification_channel';
  static const String _androidChannelName = 'FR Notifications';
  static const String _androidChannelDescription = 'FR App 本地通知通道';

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    // 页面打开时自动查询一次通知权限状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionStatus();
    });
  }

  Future<void> _initializeNotifications() async {
    // 仅在 Android/iOS 平台初始化
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('通知初始化失败: $e');
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('通知被点击: ${response.payload}');
  }

  // 查询当前通知权限状态
  // 用 permission_handler 而非 flutter_local_notifications,
  // 后者在国产 ROM 上 areNotificationsEnabled 经常误报 false,
  // 且无法区分 "未询问过" 和 "永久拒绝"。
  Future<void> _checkPermissionStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(() {
        _permissionStatusText = '当前平台不支持';
        _permissionGranted = false;
      });
      return;
    }
    try {
      final status = await Permission.notification.status;
      if (!mounted) return;
      setState(() {
        _permissionStatusText = _statusText(status);
        _permissionGranted = status.isGranted || status.isLimited;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通知权限状态: ${_statusText(status)}')),
        );
      }
    } catch (e) {
      debugPrint('查询通知权限失败: $e');
      if (mounted) {
        setState(() {
          _permissionStatusText = '查询失败: $e';
          _permissionGranted = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('查询失败: $e')),
        );
      }
    }
  }

  String _statusText(PermissionStatus s) {
    switch (s) {
      case PermissionStatus.granted:
        return '已授权';
      case PermissionStatus.denied:
        return '已拒绝 (可再次询问)';
      case PermissionStatus.permanentlyDenied:
        return '永久拒绝 (需去系统设置)';
      case PermissionStatus.restricted:
        return '受限';
      case PermissionStatus.limited:
        return '受限授权';
      case PermissionStatus.provisional:
        return '临时授权';
    }
  }

  // 请求通知权限
  //
  // 用 permission_handler 的 Permission.notification 替代
  // flutter_local_notifications 的 requestNotificationsPermission:
  // - 后者内部用 ActivityCompat.requestPermissions, 但当 permissionRequestProgress
  //   不为 None 时会 result.error, Dart 端 invokeMethod 会抛 PlatformException
  //   被外层 catch 静默吞掉, 这就是"点了按钮没任何反馈"的根因
  // - permission_handler 不会抛 PlatformException, 状态明确
  // - permission_handler 同时支持 Android 13+ POST_NOTIFICATIONS 和 iOS
  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台不支持通知权限')),
        );
      }
      return false;
    }

    try {
      // 先查一下当前状态, 避免无谓弹窗
      final current = await Permission.notification.status;
      debugPrint('[通知权限] 当前状态: $current');

      if (current.isPermanentlyDenied) {
        // 永久拒绝 → 直接引导去系统设置
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('权限已被永久拒绝, 请到系统设置开启')),
          );
          await _openSystemNotificationSettings();
        }
        return false;
      }

      // 弹系统授权框
      final result = await Permission.notification.request();
      debugPrint('[通知权限] 请求结果: $result');

      if (!mounted) return result.isGranted || result.isLimited;
      setState(() {
        _permissionStatusText = _statusText(result);
        _permissionGranted = result.isGranted || result.isLimited;
      });

      if (result.isGranted || result.isLimited) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知权限已开启')),
        );
        return true;
      }

      if (result.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已拒绝, 请到系统设置开启')),
        );
        await _openSystemNotificationSettings();
        return false;
      }

      // 用户点"不允许" 但还能再次询问
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通知权限未开启 (${_statusText(result)})')),
      );
      return false;
    } catch (e, st) {
      debugPrint('[通知权限] 请求异常: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请求权限异常: $e')),
        );
      }
      return false;
    }
  }

  // 真正打开系统的"应用通知设置"页
  Future<void> _openSystemNotificationSettings() async {
    try {
      // Android 8+ 支持直接跳到本 App 的通知设置页
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      // 某些 ROM / iOS 可能不支持 notification 类型, 退回通用设置
      try {
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
      } catch (e) {
        debugPrint('打开系统设置失败: $e');
      }
    }
  }

  // 显示即时通知
  Future<void> _showInstantNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      _showError('通知未初始化');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('通知已发送')));
      }
    } catch (e) {
      _showError('发送失败: $e');
    }
  }

  // 取消所有通知
  Future<void> _cancelAllNotifications() async {
    await _notifications.cancelAll();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已取消所有通知')));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F8),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题 - 延伸到状态栏后
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      size: 48,
                      color: theme.colorScheme.onPrimary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '本地通知测试',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '发送测试推送通知',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onPrimary.withAlpha(204),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 初始化状态
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isInitialized
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: _isInitialized ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '通知状态: ${_isInitialized ? "已就绪" : "未初始化"}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      if (!_isInitialized) ...[
                        const SizedBox(height: 8),
                        Text(
                          Platform.isAndroid || Platform.isIOS
                              ? '点击按钮请求通知权限'
                              : 'Web 平台不支持本地通知，请使用真机测试',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _requestPermissions,
                              icon: const Icon(Icons.lock_open),
                              label: const Text('请求通知权限'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _checkPermissionStatus,
                              icon: const Icon(Icons.search),
                              label: const Text('查询当前状态'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _permissionGranted
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _permissionGranted
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              size: 18,
                              color: _permissionGranted
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '权限状态: $_permissionStatusText',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 即时通知
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.flash_on, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            '即时通知',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '点击后立即显示通知',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildNotifyButton(
                            '简单通知',
                            () => _showInstantNotification(
                              title: '测试通知',
                              body: '这是一条测试通知',
                            ),
                          ),
                          _buildNotifyButton(
                            '任务提醒',
                            () => _showInstantNotification(
                              title: '任务提醒',
                              body: '您有一个新任务待完成',
                            ),
                          ),
                          _buildNotifyButton(
                            '社交动态',
                            () => _showInstantNotification(
                              title: '新消息',
                              body: '您收到了5条新消息',
                            ),
                          ),
                          _buildNotifyButton(
                            '系统警告',
                            () => _showInstantNotification(
                              title: '⚠️ 系统警告',
                              body: '检测到异常活动',
                            ),
                          ),
                          _buildNotifyButton(
                            '倒计时完成',
                            () => _showInstantNotification(
                              title: '⏰ 倒计时完成',
                              body: '您的3秒倒计时已结束！',
                              payload: 'countdown',
                            ),
                          ),
                          _buildNotifyButton(
                            '喝水提醒',
                            () => _showInstantNotification(
                              title: '💧 喝水提醒',
                              body: '该喝水了，今天已喝3杯水',
                              payload: 'water',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 管理操作
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.settings, color: Colors.grey),
                          SizedBox(width: 8),
                          Text(
                            '通知管理',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isInitialized
                              ? _cancelAllNotifications
                              : null,
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('取消所有通知'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 使用说明
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '使用说明',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 即时通知：点击后立即显示在通知栏\n'
                      '• 通知权限首次使用需要授权\n'
                      '• Web 平台不支持本地通知\n'
                      '• 需要真机测试完整功能',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotifyButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _isInitialized ? onPressed : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label),
    );
  }
}
