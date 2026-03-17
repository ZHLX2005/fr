import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../lab_container.dart';

/// 浏览器预览Demo - 在应用内打开URL
class WebPreviewDemo extends DemoPage {
  @override
  String get title => '浏览器预览';

  @override
  String get description => '内嵌浏览器打开网页';

  @override
  Widget buildPage(BuildContext context) {
    return const _WebPreviewPage();
  }
}

class _WebPreviewPage extends StatefulWidget {
  const _WebPreviewPage();

  @override
  State<_WebPreviewPage> createState() => _WebPreviewPageState();
}

class _WebPreviewPageState extends State<_WebPreviewPage> {
  final _urlController = TextEditingController();
  String _currentUrl = '';
  bool _isLoading = false;
  String? _errorMessage;

  final List<_QuickLink> _quickLinks = [
    _QuickLink(name: 'Google', url: 'https://www.google.com', icon: Icons.search),
    _QuickLink(name: 'GitHub', url: 'https://github.com', icon: Icons.code),
    _QuickLink(name: 'Flutter', url: 'https://flutter.dev', icon: Icons.flutter_dash),
    _QuickLink(name: 'B站', url: 'https://www.bilibili.com', icon: Icons.play_circle_filled),
    _QuickLink(name: 'YouTube', url: 'https://www.youtube.com', icon: Icons.video_library),
    _QuickLink(name: '百度', url: 'https://www.baidu.com', icon: Icons.language),
    _QuickLink(name: '知乎', url: 'https://www.zhihu.com', icon: Icons.question_answer),
    _QuickLink(name: '掘金', url: 'https://juejin.cn', icon: Icons.edit),
    _QuickLink(name: 'CSDN', url: 'https://blog.csdn.net', icon: Icons.computer),
    _QuickLink(name: 'Gitee', url: 'https://gitee.com', icon: Icons.source),
    _QuickLink(name: 'Stack Overflow', url: 'https://stackoverflow.com', icon: Icons.help),
    _QuickLink(name: 'MDN', url: 'https://developer.mozilla.org', icon: Icons.book),
  ];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = '无法打开该链接';
        });
      }
    }
  }

  Future<void> _loadUrl() async {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;

    // 自动添加 https:// 前缀
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentUrl = url;
    });

    await _openUrl(url);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('浏览器预览'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 搜索栏
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText: '输入网址...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                        prefixIcon: Icon(Icons.link, color: Colors.grey[400], size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 15),
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _loadUrl(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _isLoading ? null : _loadUrl,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_forward, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // 错误提示
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red[50],
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[400], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red[400], fontSize: 13),
                  ),
                ],
              ),
            ),

          // 当前URL显示
          if (_currentUrl.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white,
              child: Row(
                children: [
                  Icon(Icons.public, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentUrl,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _openUrl(_currentUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        '在浏览器打开',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // 快速链接网格
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '快速访问',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _quickLinks.length,
                    itemBuilder: (context, index) {
                      final link = _quickLinks[index];
                      return _QuickLinkCard(
                        link: link,
                        onTap: () {
                          _urlController.text = link.url;
                          _openUrl(link.url);
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // 常用网站
                  const Text(
                    '常用网站',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSection([
                    _QuickLink(name: '淘宝', url: 'https://www.taobao.com', icon: Icons.shopping_bag),
                    _QuickLink(name: '京东', url: 'https://www.jd.com', icon: Icons.local_mall),
                    _QuickLink(name: '拼多多', url: 'https://www.pinduoduo.com', icon: Icons.thumb_up),
                    _QuickLink(name: '美团', url: 'https://www.meituan.com', icon: Icons.fastfood),
                  ]),

                  const SizedBox(height: 16),
                  _buildSection([
                    _QuickLink(name: '抖音', url: 'https://www.douyin.com', icon: Icons.music_video),
                    _QuickLink(name: '微博', url: 'https://weibo.com', icon: Icons.alternate_email),
                    _QuickLink(name: '微信', url: 'https://web.wechat.com', icon: Icons.chat),
                    _QuickLink(name: 'QQ邮箱', url: 'https://mail.qq.com', icon: Icons.email),
                  ]),

                  const SizedBox(height: 16),
                  _buildSection([
                    _QuickLink(name: '腾讯视频', url: 'https://v.qq.com', icon: Icons.tv),
                    _QuickLink(name: '爱奇艺', url: 'https://www.iq.com', icon: Icons.play_circle_outline),
                    _QuickLink(name: '网易云音乐', url: 'https://music.163.com', icon: Icons.music_note),
                    _QuickLink(name: '虾米音乐', url: 'https://www.xiami.com', icon: Icons.headphones),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(List<_QuickLink> links) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: links.asMap().entries.map((entry) {
          final index = entry.key;
          final link = entry.value;
          return Column(
            children: [
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(link.icon, color: const Color(0xFF007AFF), size: 20),
                ),
                title: Text(link.name, style: const TextStyle(fontSize: 15)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                onTap: () {
                  _urlController.text = link.url;
                  _openUrl(link.url);
                },
              ),
              if (index < links.length - 1)
                Divider(height: 1, indent: 56, color: Colors.grey[200]),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// 快速链接数据
class _QuickLink {
  final String name;
  final String url;
  final IconData icon;

  const _QuickLink({required this.name, required this.url, required this.icon});
}

/// 快速链接卡片
class _QuickLinkCard extends StatelessWidget {
  final _QuickLink link;
  final VoidCallback onTap;

  const _QuickLinkCard({required this.link, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(link.icon, color: const Color(0xFF007AFF), size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              link.name,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

void registerWebPreviewDemo() {
  demoRegistry.register(WebPreviewDemo());
}
