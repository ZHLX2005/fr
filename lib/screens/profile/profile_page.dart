import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_controller/native_controller_page.dart';
import 'lab/lab_page.dart';
import '../../lab/lab_container.dart';
import '../banner_crop_page.dart';
import 'theme/theme_page.dart';
import '../../widgets/springy_banner.dart';
import '../../widgets/bounded_bouncing_scroll_physics.dart';
import 'character_profile_page.dart';

// 首页
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _bannerPath;
  static const String _bannerKey = 'home_banner_path';

  // ---------- 底部小字连点彩蛋 ----------
  int _tapCount = 0;
  DateTime? _lastTapTime;

  void _onBottomTextTap() {
    final now = DateTime.now();
    // 超过 2 秒没连点就重置
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!).inMilliseconds > 2000) {
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    _lastTapTime = now;

    if (_tapCount >= 5) {
      _tapCount = 0;
      _showEasterEggDialog();
    }
  }
  // ---------- /底部小字连点彩蛋 ----------

  void _showEasterEggDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.auto_awesome, size: 40),
        title: const Text('🎉 发现彩蛋！'),
        content: const Text('人物小谱已经解锁，要不要进去看看？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('下次再说'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                this.context,
                MaterialPageRoute(
                  builder: (context) => const CharacterProfilePage(),
                ),
              );
            },
            child: const Text('去看看'),
          ),
        ],
      ),
    );
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Banner已移除')));
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
                title: const Text(
                  '移除Banner',
                  style: TextStyle(color: Colors.red),
                ),
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
        top: false, // 让 SliverAppBar 处理顶部安全区域
        // iOS 风格下拉橡皮筋：
        //   - BouncingScrollPhysics 让 position.pixels 允许短暂为负（overscroll）
        //   - SliverAppBar(stretch: true) 自身消化顶部 overscroll，把 background
        //     拉伸（整个 banner 区域跟着手指下拉）
        //   - 列表下方也跟着 iOS 标准行为轻微下移（这是正确的 overscroll 行为）
        // 整段体验：banner 整体下拉 → 松手弹簧回弹，与 iOS Safari 顶部栏一致。
        child: CustomScrollView(
          // BoundedBouncingScrollPhysics：在 iOS 风格橡皮筋基础上限幅，
          // 最大下拉 overscroll = 80 px（默认 BouncingScrollPhysics 几乎无限）。
          physics: const BoundedBouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
            maxOverscroll: 80,
          ),
          slivers: [
            // Banner 区域
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              // 标题不浮动，正常显示在 AppBar 区域
              floating: false,
              snap: false,
              // stretch: true 让顶部 overscroll 把整个 banner 区域拉高（iOS 风格）。
              // banner 整体区域跟着手指下拉，松手有弹性回弹。
              stretch: true,
              flexibleSpace: FlexibleSpaceBar(
                // 标题只在收起状态显示
                title: _bannerPath == null ? const Text('小豆子') : null,
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                background: SpringyBanner(
                  imagePath: _bannerPath,
                  fallback: _buildDefaultBanner(context),
                  onTap: _showBannerOptions,
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
                            builder: (context) => const LabPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                    // 游戏中心
                    _buildMenuCard(
                      context,
                      icon: Icons.sports_esports,
                      title: '游戏中心',
                      subtitle:
                          '已收录 ${demoRegistry.getAll().filterByType(DemoType.game).length} 款休闲游戏',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GameCenterPage(),
                          ),
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
                            builder: (context) => const ThemePage(),
                          ),
                        );
                      },
                    ),
                   const SizedBox(height: 16),
                    // 原生功能测试
                    _buildMenuCard(
                      context,
                      icon: Icons.phone_android,
                      title: '原生功能测试',
                      subtitle: '测试通知、相机、麦克风等原生功能',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NativeControllerPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 48),
                    // 底部说明
                    GestureDetector(
                      onTap: _onBottomTextTap,
                      child: Text(
                        '小豆子 - 为了满足好奇心而生',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),    // CustomScrollView
        ),        // SafeArea
      );          // Scaffold
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
            ],
          ),    // CustomScrollView
        ),
      ),
    );
  }
}
