import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../media_test_page.dart';
import '../lab/lab_page.dart';
import '../banner_crop_page.dart';
import '../theme/theme_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _bannerPath;
  static const String _bannerKey = 'home_banner_path';

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bannerPath = prefs.getString(_bannerKey);
    });
  }

  Future<void> _saveBanner(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bannerKey, path);
  }

  Future<void> _openCropPage() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BannerCropPage()),
    );
    if (result != null) {
      setState(() {
        _bannerPath = result;
      });
      await _saveBanner(result);
    }
  }

  Future<void> _removeBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bannerKey);
    setState(() {
      _bannerPath = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Banner已移除')),
      );
    }
  }

  void _showBannerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('选择并裁剪图片'),
              onTap: () {
                Navigator.pop(context);
                _openCropPage();
              },
            ),
            if (_bannerPath != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('移除Banner', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeBanner();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false, // 让SliverAppBar处理顶部安全区域
        child: CustomScrollView(
          slivers: [
            // Banner 区域
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              // 标题不浮动，正常显示在AppBar区域
              floating: false,
              snap: false,
              flexibleSpace: FlexibleSpaceBar(
                // 标题只在收起状态显示
                title: _bannerPath == null
                    ? const Text('小豆子')
                    : null,
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                background: GestureDetector(
                  onTap: _showBannerOptions,
                  child: _bannerPath != null
                      ? Image.file(
                          File(_bannerPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _buildDefaultBanner(context),
                        )
                      : _buildDefaultBanner(context),
                ),
              ),
            ),
            // 功能列表
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // 媒体功能测试
                    _buildMenuCard(
                      context,
                      icon: Icons.camera_alt,
                      title: '媒体功能测试',
                      subtitle: '测试相机、相册、音视频播放等功能',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const MediaTestPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // 主题设置
                    _buildMenuCard(
                      context,
                      icon: Icons.palette,
                      title: '主题设置',
                      subtitle: '切换应用主题，支持夜间模式和粉红主题',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ThemePage()),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // 开发者实验室
                    _buildMenuCard(
                      context,
                      icon: Icons.science,
                      title: '开发者实验室',
                      subtitle: '各种Demo示例和实验性功能',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LabPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 48),
                    // 底部说明
                    Text(
                      '小豆子 - 为了满足好奇心而生',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultBanner(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: 48,
              color: Colors.white.withOpacity(0.7),
            ),
            const SizedBox(height: 8),
            Text(
              '点击设置Banner',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
