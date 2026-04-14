import 'dart:io';
import 'package:flutter/material.dart';
import '../lab_container.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知 Demo
class NotificationDemo extends DemoPage {
  @override
  String get title => '本地通知';

  @override
  String get description => '测试推送通知功能';

  @override
  Widget buildPage(BuildContext context) {
    return const _NotificationPage();
  }
}

class _NotificationPage extends StatefulWidget {
  const _NotificationPage();

  @override
  State<_NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<_NotificationPage> {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // 通知通道ID（Android）
  static const String _androidChannelId = 'fr_notification_channel';
  static const String _androidChannelName = 'FR Notifications';
  static const String _androidChannelDescription = 'FR App 本地通知通道';

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
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

  // 请求通知权限
  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    try {
      if (Platform.isAndroid) {
        final androidPlugin = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        // Android 13+ 使用 requestNotificationsPermission 会返回 null/pending
        // 需要引导用户去设置页面手动开启
        final granted = await androidPlugin?.requestNotificationsPermission();
        if (granted == true) {
          return true;
        }

        // 如果权限被拒绝或需要手动设置，引导用户去系统设置
        if (!mounted) return false;
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要通知权限'),
            content: const Text(
              '通知权限未开启。\n\n'
              '请点击"去设置"按钮，然后在权限设置中开启通知权限。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去设置'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          // 尝试打开应用通知设置页面
          await androidPlugin?.requestNotificationsPermission();
          return false; // 打开设置后用户自行开启，返回false
        }
        return false;
      } else if (Platform.isIOS) {
        final iosPlugin = _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('请求权限失败: $e');
    }
    return false;
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

    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F3F8),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Container(
                padding: const EdgeInsets.all(20),
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isInitialized
                              ? null
                              : _requestPermissions,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('请求通知权限'),
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

void registerNotificationDemo() {
  demoRegistry.register(NotificationDemo());
}
