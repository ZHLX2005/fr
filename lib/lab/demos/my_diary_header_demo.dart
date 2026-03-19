import 'package:flutter/material.dart';
import '../lab_container.dart';

/// MyDiary风格头部 Demo
class MyDiaryHeaderDemo extends DemoPage {
  @override
  String get title => '日记头部';

  @override
  String get description => '下滑透明圆角头部与卡片列表';

  @override
  Widget buildPage(BuildContext context) {
    return const _MyDiaryHeaderPage();
  }
}

class _MyDiaryHeaderPage extends StatefulWidget {
  const _MyDiaryHeaderPage();

  @override
  State<_MyDiaryHeaderPage> createState() => _MyDiaryHeaderPageState();
}

class _MyDiaryHeaderPageState extends State<_MyDiaryHeaderPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _topBarAnimation;

  final ScrollController _scrollController = ScrollController();
  double _topBarOpacity = 0.0;

  // 青春活力配色
  static const Color _primaryColor = Color(0xFF6C63FF);
  static const Color _secondaryColor = Color(0xFFFF6B6B);
  static const Color _tertiaryColor = Color(0xFF4ECDC4);
  static const Color _accentColor = Color(0xFFFFE66D);
  static const Color _backgroundColor = Color(0xFFF2F3F8);
  static const Color _cardColor = Color(0xFFFFFFFF);

  final List<_DiaryCard> _cards = [
    _DiaryCard(
      title: '今天的计划',
      content: '完成项目报告，阅读一本书籍',
      time: '08:30',
      color: _primaryColor,
      icon: Icons.assignment,
    ),
    _DiaryCard(
      title: '健身记录',
      content: '跑步5公里，瑜伽30分钟',
      time: '09:15',
      color: _secondaryColor,
      icon: Icons.fitness_center,
    ),
    _DiaryCard(
      title: '学习笔记',
      content: 'Flutter高级组件与动画技巧',
      time: '14:20',
      color: _tertiaryColor,
      icon: Icons.school,
    ),
    _DiaryCard(
      title: '晚餐计划',
      content: '沙拉、鸡胸肉、水果',
      time: '18:00',
      color: _accentColor,
      icon: Icons.restaurant,
    ),
    _DiaryCard(
      title: '阅读时光',
      content: '《Flutter实战》Chapter 5',
      time: '21:00',
      color: _primaryColor,
      icon: Icons.menu_book,
    ),
    _DiaryCard(
      title: '每日反思',
      content: '今天完成了很多事情，很充实！',
      time: '22:30',
      color: _secondaryColor,
      icon: Icons.nightlight_round,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _topBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0, 0.5, curve: Curves.fastOutSlowIn),
      ),
    );

    _animationController.forward();

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.offset >= 24) {
      if (_topBarOpacity != 1.0) {
        setState(() {
          _topBarOpacity = 1.0;
        });
      }
    } else if (_scrollController.offset <= 24 && _scrollController.offset >= 0) {
      if (_topBarOpacity != _scrollController.offset / 24) {
        setState(() {
          _topBarOpacity = _scrollController.offset / 24;
        });
      }
    } else if (_scrollController.offset <= 0) {
      if (_topBarOpacity != 0.0) {
        setState(() {
          _topBarOpacity = 0.0;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _backgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            _buildListView(),
            _buildHeader(),
            SizedBox(
              height: MediaQuery.of(context).padding.bottom,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top +
            kToolbarHeight +
            24,
        bottom: 62 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: _cards.length,
      itemBuilder: (context, index) {
        _animationController.forward();
        return _buildAnimatedCard(index);
      },
    );
  }

  Widget _buildAnimatedCard(int index) {
    final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          (1 / _cards.length) * index,
          1.0,
          curve: Curves.fastOutSlowIn,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return FadeTransition(
          opacity: animation,
          child: Transform(
            transform: Matrix4.translationValues(
              0.0,
              30 * (1.0 - animation.value),
              0.0,
            ),
            child: child,
          ),
        );
      },
      child: _DiaryCardWidget(card: _cards[index]),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _topBarAnimation,
              child: Transform(
                transform: Matrix4.translationValues(
                  0.0,
                  30 * (1.0 - _topBarAnimation.value),
                  0.0,
                ),
                child: child,
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_topBarOpacity),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.4 * _topBarOpacity),
                  offset: const Offset(1.1, 1.1),
                  blurRadius: 10.0,
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).padding.top,
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16 - 8.0 * _topBarOpacity,
                    bottom: 12 - 8.0 * _topBarOpacity,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'My Diary',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 22 + 6 - 6 * _topBarOpacity,
                              letterSpacing: 1.2,
                              color: const Color(0xFF17262A),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 38,
                        width: 38,
                        child: InkWell(
                          highlightColor: Colors.transparent,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(32.0),
                          ),
                          onTap: () {},
                          child: const Center(
                            child: Icon(
                              Icons.keyboard_arrow_left,
                              color: Color(0xFF3A5160),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 8, right: 8),
                        child: Row(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.calendar_today,
                                color: Color(0xFF3A5160),
                                size: 18,
                              ),
                            ),
                            Text(
                              '19 Mar',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 18,
                                letterSpacing: -0.2,
                                color: Color(0xFF17262A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 38,
                        width: 38,
                        child: InkWell(
                          highlightColor: Colors.transparent,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(32.0),
                          ),
                          onTap: () {},
                          child: const Center(
                            child: Icon(
                              Icons.keyboard_arrow_right,
                              color: Color(0xFF3A5160),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DiaryCard {
  final String title;
  final String content;
  final String time;
  final Color color;
  final IconData icon;

  _DiaryCard({
    required this.title,
    required this.content,
    required this.time,
    required this.color,
    required this.icon,
  });
}

class _DiaryCardWidget extends StatelessWidget {
  final _DiaryCard card;

  const _DiaryCardWidget({required this.card});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: card.color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: card.color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 左侧图标
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: card.color,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  card.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // 中间内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: card.color.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 右侧时间
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: card.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  card.time,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: card.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void registerMyDiaryHeaderDemo() {
  demoRegistry.register(MyDiaryHeaderDemo());
}
