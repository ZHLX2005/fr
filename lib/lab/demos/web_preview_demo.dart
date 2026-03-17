import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../lab_container.dart';

/// 浏览器预览Demo - 内嵌浏览器
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
  late final WebViewController _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0;
  String _currentUrl = '';
  bool _showWebView = false;

  final List<_QuickLink> _quickLinks = [
    _QuickLink(name: 'Google', url: 'https://www.google.com', icon: Icons.search),
    _QuickLink(name: 'GitHub', url: 'https://github.com', icon: Icons.code),
    _QuickLink(name: 'Flutter', url: 'https://flutter.dev', icon: Icons.flutter_dash),
    _QuickLink(name: 'B站', url: 'https://www.bilibili.com', icon: Icons.play_circle_filled),
    _QuickLink(name: 'YouTube', url: 'https://www.youtube.com', icon: Icons.video_library),
    _QuickLink(name: '百度', url: 'https://www.baidu.com', icon: Icons.language),
    _QuickLink(name: '知乎', url: 'https://www.zhihu.com', icon: Icons.question_answer),
    _QuickLink(name: '掘金', url: 'https://juejin.cn', icon: Icons.edit),
  ];

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  void _initWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _loadProgress = 0;
              _currentUrl = url;
            });
          },
          onProgress: (int progress) {
            setState(() {
              _loadProgress = progress / 100;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
              _urlController.text = url;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // 允许所有导航
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadUrl(String url) async {
    var finalUrl = url.trim();
    if (finalUrl.isEmpty) return;

    // 自动添加 https:// 前缀
    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      finalUrl = 'https://$finalUrl';
    }

    setState(() {
      _showWebView = true;
      _currentUrl = finalUrl;
    });

    await _webViewController.loadRequest(Uri.parse(finalUrl));
  }

  void _goBack() async {
    if (await _webViewController.canGoBack()) {
      await _webViewController.goBack();
    }
  }

  void _goForward() async {
    if (await _webViewController.canGoForward()) {
      await _webViewController.goForward();
    }
  }

  void _reload() async {
    await _webViewController.reload();
  }

  void _closeWebView() {
    setState(() {
      _showWebView = false;
      _currentUrl = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(_showWebView ? '浏览器' : '浏览器预览'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: _showWebView
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _goBack();
                },
              )
            : null,
        actions: _showWebView
            ? [
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _goForward,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _reload,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _closeWebView,
                ),
              ]
            : null,
      ),
      body: _showWebView ? _buildWebView() : _buildHomePage(),
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        WebViewWidget(controller: _webViewController),
        // 加载进度条
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _loadProgress,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
              minHeight: 2,
            ),
          ),
        // URL地址栏（固定在底部）
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _showWebView = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.home, size: 16, color: Color(0xFF007AFF)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _currentUrl,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHomePage() {
    return Column(
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
                    onSubmitted: _loadUrl,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _loadUrl(_urlController.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_forward, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

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
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _quickLinks.length,
                  itemBuilder: (context, index) {
                    final link = _quickLinks[index];
                    return _QuickLinkCard(
                      link: link,
                      onTap: () => _loadUrl(link.url),
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
                  _QuickLink(name: '网易云', url: 'https://music.163.com', icon: Icons.music_note),
                  _QuickLink(name: 'Gitee', url: 'https://gitee.com', icon: Icons.source),
                ]),
              ],
            ),
          ),
        ),
      ],
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
                onTap: () => _loadUrl(link.url),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(link.icon, color: const Color(0xFF007AFF), size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              link.name,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
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
