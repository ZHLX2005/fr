import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../media_test_page.dart';
import '../lab/lab_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          final user = userProvider.currentUser;

          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // Avatar
                          GestureDetector(
                            onTap: () => _showAvatarOptions(context, user),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 50,
                                  backgroundImage: user.avatar != null
                                      ? CachedNetworkImageProvider(user.avatar!)
                                      : null,
                                  child: user.avatar == null
                                      ? Text(
                                          user.nickname.substring(0, 1),
                                          style: const TextStyle(
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Nickname
                          Text(
                            user.nickname,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          // User ID
                          Text(
                            'ID: ${user.id}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withOpacity(0.8),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // Status indicator
                    _buildStatusIndicator(context, user),
                    const SizedBox(height: 8),

                    // Signature
                    if (user.signature != null && user.signature!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          user.signature!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Stats
                    _buildStatsRow(context),
                    const SizedBox(height: 24),

                    // Menu items
                    _buildMenuItem(
                      context,
                      icon: Icons.edit,
                      title: '编辑资料',
                      onTap: () => _editProfile(context, user),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.qr_code,
                      title: '我的二维码',
                      onTap: () => _showQRCode(context, user),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.settings,
                      title: '设置',
                      onTap: () => _openSettings(context),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.help_outline,
                      title: '帮助与反馈',
                      onTap: () {},
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.science,
                      title: '媒体功能测试',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MediaTestPage(),
                          ),
                        );
                      },
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.science,
                      title: '开发者实验室',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LabPage(),
                          ),
                        );
                      },
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.info_outline,
                      title: '关于',
                      onTap: () => _showAbout(context),
                    ),
                    const SizedBox(height: 24),

                    // Logout button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _logout(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('退出登录'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context, User user) {
    String statusText;
    Color statusColor;

    switch (user.status) {
      case 'online':
        statusText = '在线';
        statusColor = Colors.green;
        break;
      case 'away':
        statusText = '离开';
        statusColor = Colors.orange;
        break;
      default:
        statusText = '离线';
        statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Consumer<FriendProvider>(
      builder: (context, friendProvider, child) {
        final friendCount = friendProvider.friends.length;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatItem(context, count: friendCount, label: '好友'),
            _buildStatItem(context, count: 0, label: '群组'),
            _buildStatItem(context, count: 0, label: '动态'),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(BuildContext context,
      {required int count, required String label}) {
    return Column(
      children: [
        Text(
          '$count',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  void _showAvatarOptions(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement image picker
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement camera
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editProfile(BuildContext context, User user) {
    final nicknameController = TextEditingController(text: user.nickname);
    final signatureController = TextEditingController(text: user.signature ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑资料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nicknameController,
              decoration: const InputDecoration(
                labelText: '昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: signatureController,
              decoration: const InputDecoration(
                labelText: '个性签名',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await context.read<UserProvider>().updateProfile(
                    nickname: nicknameController.text.trim(),
                    signature: signatureController.text.trim(),
                  );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('资料已更新')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showQRCode(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('我的二维码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'QR Code\n${user.id}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '扫一扫上面的二维码图案，加我为好友',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsPage(),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Flutter 聊天应用',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2024 Flutter Demo',
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement logout logic
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已退出登录')),
              );
            },
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _buildSettingSection(
            context,
            title: '通知设置',
            children: [
              SwitchListTile(
                title: const Text('消息通知'),
                subtitle: const Text('接收新消息时通知'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('声音'),
                subtitle: const Text('新消息提示音'),
                value: true,
                onChanged: (value) {},
              ),
            ],
          ),
          _buildSettingSection(
            context,
            title: '隐私设置',
            children: [
              SwitchListTile(
                title: const Text('在线状态'),
                subtitle: const Text('让好友看到我的在线状态'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('已读回执'),
                subtitle: const Text('发送已读消息回执'),
                value: true,
                onChanged: (value) {},
              ),
            ],
          ),
          _buildSettingSection(
            context,
            title: '通用',
            children: [
              ListTile(
                title: const Text('语言'),
                trailing: const Text('简体中文'),
                onTap: () {},
              ),
              ListTile(
                title: const Text('清除缓存'),
                onTap: () {
                  // TODO: Implement cache clearing
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          ),
        ),
        ...children,
        const Divider(height: 32),
      ],
    );
  }
}
