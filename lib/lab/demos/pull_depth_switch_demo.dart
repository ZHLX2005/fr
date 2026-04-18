import 'dart:async';

import 'package:flutter/material.dart';

import '../lab_container.dart';
import 'const_pull_depth_switch_demo.dart';

class PullDepthSwitchDemo extends DemoPage {
  @override
  String get title => '二段下拉';

  @override
  String get description => '轻下拉触发刷新，深下拉真实展开一个小程序页';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const _PullDepthSwitchDemoPage();
  }
}

class _PullDepthSwitchDemoPage extends StatefulWidget {
  const _PullDepthSwitchDemoPage();

  @override
  State<_PullDepthSwitchDemoPage> createState() =>
      _PullDepthSwitchDemoPageState();
}

class _PullDepthSwitchDemoPageState extends State<_PullDepthSwitchDemoPage> {
  final ScrollController _scrollController = ScrollController();

  double _pullExtent = 0;
  double _pullPeakExtent = 0;
  bool _isRefreshing = false;
  bool _isAnimatingSheet = false;
  bool _isMiniProgramOpen = false;
  int _refreshCount = 0;
  DateTime _lastRefreshAt = DateTime.now();

  final List<_MiniFeatureCardData> _cards = const [
    _MiniFeatureCardData(
      title: '日程提醒',
      subtitle: '快速记录今天的待办和提醒',
      icon: Icons.event_note_rounded,
      color: Color(0xFF2563EB),
    ),
    _MiniFeatureCardData(
      title: '喝水打卡',
      subtitle: '轻量记录和今日目标进度',
      icon: Icons.water_drop_rounded,
      color: Color(0xFF0EA5A4),
    ),
    _MiniFeatureCardData(
      title: '账单速记',
      subtitle: '像小程序一样做一件小事',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFFF97316),
    ),
    _MiniFeatureCardData(
      title: '出行卡片',
      subtitle: '通勤、打车、停车一屏完成',
      icon: Icons.directions_car_filled_rounded,
      color: Color(0xFF7C3AED),
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canTrackPull =>
      !_isRefreshing &&
      !_isAnimatingSheet &&
      !_isMiniProgramOpen &&
      _scrollController.hasClients &&
      _scrollController.position.pixels <=
          _scrollController.position.minScrollExtent + 0.5;

  double get _refreshProgress =>
      (_pullExtent / kPullRefreshThreshold).clamp(0.0, 1.0);

  double get _launchProgress =>
      ((_pullExtent - kPullRefreshThreshold) /
              (kPullLaunchThreshold - kPullRefreshThreshold))
          .clamp(0.0, 1.0);

  double _pageOffset(double viewportHeight) {
    if (_isMiniProgramOpen) {
      return viewportHeight;
    }
    if (_pullExtent <= kPullRefreshThreshold) {
      return 0;
    }
    final progress =
        ((_pullExtent - kPullRefreshThreshold) /
                (kPullLaunchThreshold - kPullRefreshThreshold))
            .clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(progress) * viewportHeight;
  }

  Future<void> _handleRelease() async {
    final double releaseExtent = _pullPeakExtent > 0
        ? _pullPeakExtent
        : _pullExtent;

    if (_isRefreshing ||
        _isAnimatingSheet ||
        _isMiniProgramOpen ||
        releaseExtent <= 0) {
      await _resetPullExtent();
      return;
    }

    if (releaseExtent >= kPullLaunchThreshold) {
      await _openMiniProgram();
      return;
    }

    if (releaseExtent >= kPullRefreshThreshold) {
      await _refreshContent();
      return;
    }

    await _resetPullExtent();
  }

  Future<void> _refreshContent() async {
    setState(() {
      _isRefreshing = true;
      _pullExtent = kPullRefreshThreshold;
      _pullPeakExtent = kPullRefreshThreshold;
    });

    await Future<void>.delayed(kPullActionDuration);
    if (!mounted) {
      return;
    }

    setState(() {
      _refreshCount += 1;
      _lastRefreshAt = DateTime.now();
      _isRefreshing = false;
    });

    await _resetPullExtent();
  }

  Future<void> _openMiniProgram() async {
    setState(() {
      _isAnimatingSheet = true;
      _isMiniProgramOpen = true;
      _pullExtent = 0;
      _pullPeakExtent = 0;
    });

    await Future<void>.delayed(kPullActionDuration);
    if (!mounted) {
      return;
    }

    setState(() {
      _isAnimatingSheet = false;
    });
  }

  Future<void> _closeMiniProgram() async {
    if (_isAnimatingSheet || !_isMiniProgramOpen) {
      return;
    }

    setState(() {
      _isAnimatingSheet = true;
      _isMiniProgramOpen = false;
      _pullExtent = 0;
      _pullPeakExtent = 0;
    });

    await Future<void>.delayed(kPullResetDuration);
    if (!mounted) {
      return;
    }

    setState(() {
      _isAnimatingSheet = false;
    });
  }

  Future<void> _resetPullExtent() async {
    if (!mounted || _pullExtent == 0) {
      return;
    }

    setState(() {
      _pullExtent = 0;
      _pullPeakExtent = 0;
    });

    await Future<void>.delayed(kPullResetDuration);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.metrics.extentBefore == 0 &&
        notification.metrics.pixels <= 0 &&
        !_isRefreshing &&
        !_isAnimatingSheet &&
        !_isMiniProgramOpen) {
      final nextExtent = (-notification.metrics.pixels * 0.92).clamp(
        0.0,
        kPullIndicatorMaxExtent,
      );
      if ((nextExtent - _pullExtent).abs() > 0.5) {
        setState(() {
          _pullExtent = nextExtent;
          _pullPeakExtent = _pullPeakExtent > nextExtent
              ? _pullPeakExtent
              : nextExtent;
        });
      }
    }

    if (notification is OverscrollNotification && _canTrackPull) {
      final delta = -notification.overscroll;
      if (delta != 0) {
        setState(() {
          _pullExtent = (_pullExtent + delta * 0.62).clamp(
            0.0,
            kPullIndicatorMaxExtent,
          );
          _pullPeakExtent = _pullPeakExtent > _pullExtent
              ? _pullPeakExtent
              : _pullExtent;
        });
      }
    }

    if (notification is ScrollEndNotification) {
      unawaited(_handleRelease());
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final viewportHeight = MediaQuery.of(context).size.height;
    final pageOffset = _pageOffset(viewportHeight);
    final animationDuration = _isRefreshing || _isAnimatingSheet
        ? kPullActionDuration
        : kPullResetDuration;

    return DecoratedBox(
      decoration: const BoxDecoration(color: kPullDemoBackground),
      child: Stack(
        children: [
          Positioned.fill(
            child: _MiniProgramSurface(
              topInset: topInset,
              revealExtent: pageOffset,
              pageHeight: viewportHeight,
              isOpen: _isMiniProgramOpen,
              onClose: _closeMiniProgram,
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: AnimatedContainer(
              duration: animationDuration,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, pageOffset, 0),
              decoration: const BoxDecoration(color: kPullDemoBackground),
              child: CustomScrollView(
                controller: _scrollController,
                physics: _isMiniProgramOpen
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: topInset + 12)),
                  SliverToBoxAdapter(
                    child: _HeroCard(
                      refreshCount: _refreshCount,
                      lastRefreshAt: _lastRefreshAt,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    sliver: SliverList.separated(
                      itemBuilder: (context, index) {
                        final item = _cards[index];
                        return _FeatureCard(item: item);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemCount: _cards.length,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                height: _pullExtent + topInset,
                padding: EdgeInsets.only(
                  top: topInset + 10,
                  left: 20,
                  right: 20,
                  bottom: 12,
                ),
                child: _PullStatusPanel(
                  pullExtent: _pullExtent,
                  isRefreshing: _isRefreshing,
                  isLaunching: _isAnimatingSheet || _isMiniProgramOpen,
                  refreshProgress: _refreshProgress,
                  launchProgress: _launchProgress,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PullStatusPanel extends StatelessWidget {
  const _PullStatusPanel({
    required this.pullExtent,
    required this.isRefreshing,
    required this.isLaunching,
    required this.refreshProgress,
    required this.launchProgress,
  });

  final double pullExtent;
  final bool isRefreshing;
  final bool isLaunching;
  final double refreshProgress;
  final double launchProgress;

  @override
  Widget build(BuildContext context) {
    final bool reachedRefresh = pullExtent >= kPullRefreshThreshold;
    final bool reachedLaunch = pullExtent >= kPullLaunchThreshold;

    final String title;
    final String subtitle;
    final IconData icon;
    final Color color;

    if (isLaunching) {
      title = '小程序页已展开';
      subtitle = '当前是底层页面被真实拉出';
      icon = Icons.open_in_full_rounded;
      color = kPullDemoAccent;
    } else if (isRefreshing) {
      title = '正在刷新';
      subtitle = '轻下拉动作已生效';
      icon = Icons.sync_rounded;
      color = kPullDemoSecondary;
    } else if (reachedLaunch) {
      title = '松手展开小程序页';
      subtitle = '主页面会被整体下推，露出底层页面';
      icon = Icons.rocket_launch_rounded;
      color = kPullDemoAccent;
    } else if (reachedRefresh) {
      title = '松手立即刷新';
      subtitle = '继续下拉可以展开底层小程序页';
      icon = Icons.refresh_rounded;
      color = kPullDemoSecondary;
    } else {
      title = '轻下拉刷新，深下拉展开';
      subtitle = '同一个手势，按深度命中不同结果';
      icon = Icons.south_rounded;
      color = kPullDemoPrimary;
    }

    final indicatorOpacity = (pullExtent / 18).clamp(0.0, 1.0);

    return Opacity(
      opacity: indicatorOpacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kPullDemoSurface.withOpacity(0.96),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: kPullDemoText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: kPullDemoSubtleText,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ProgressRail(
                label: '刷新阈值',
                color: kPullDemoSecondary,
                value: refreshProgress,
              ),
              const SizedBox(height: 10),
              _ProgressRail(
                label: '展开阈值',
                color: kPullDemoAccent,
                value: launchProgress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRail extends StatelessWidget {
  const _ProgressRail({
    required this.label,
    required this.color,
    required this.value,
  });

  final String label;
  final Color color;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: kPullDemoSubtleText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: value,
            backgroundColor: color.withOpacity(0.14),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.refreshCount, required this.lastRefreshAt});

  final int refreshCount;
  final DateTime lastRefreshAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.unfold_more_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '二段式下拉交互',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '同一个手势，根据下拉深度进入不同结果',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricChip(label: '刷新次数', value: '$refreshCount 次'),
                _MetricChip(label: '最近刷新', value: _formatTime(lastRefreshAt)),
                const _MetricChip(label: '当前能力', value: '轻拉刷新 / 深拉揭页'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    final String second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.item});

  final _MiniFeatureCardData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPullDemoSurface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(item.icon, color: item.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: kPullDemoText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: kPullDemoSubtleText,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

class _MiniProgramSurface extends StatelessWidget {
  const _MiniProgramSurface({
    required this.topInset,
    required this.revealExtent,
    required this.pageHeight,
    required this.isOpen,
    required this.onClose,
  });

  final double topInset;
  final double revealExtent;
  final double pageHeight;
  final bool isOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final double revealFactor = revealExtent <= 0
        ? 0
        : (revealExtent / pageHeight).clamp(0.0, 1.0);

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: revealFactor,
        child: Container(
          height: pageHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFEAF2FF), Color(0xFFF9FBFF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            physics: isOpen
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, topInset + 20, 20, 24),
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEDD5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.widgets_rounded,
                      color: kPullDemoAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下拉展开的小程序页',
                          style: TextStyle(
                            color: kPullDemoText,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '深拉后直接把底层页面揭出来，不再是 release 后跳转。',
                          style: TextStyle(
                            color: kPullDemoSubtleText,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: isOpen ? onClose : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    tooltip: '收起',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFFB7185)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '深拉已命中',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '这里可以替换成任何小程序式的轻量页面，比如快捷支付、打卡、表单或临时任务。',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const _MiniProgramEntry(
                title: '快捷收款',
                subtitle: '一屏输入金额并生成付款码',
                icon: Icons.qr_code_2_rounded,
              ),
              const SizedBox(height: 12),
              const _MiniProgramEntry(
                title: '临时登记',
                subtitle: '像小程序一样用完即走',
                icon: Icons.edit_note_rounded,
              ),
              const SizedBox(height: 12),
              const _MiniProgramEntry(
                title: '附近服务',
                subtitle: '展示当前位置相关的快捷入口',
                icon: Icons.place_rounded,
              ),
              const SizedBox(height: 12),
              const _MiniProgramEntry(
                title: '审批代办',
                subtitle: '点开就是一个独立的小功能流',
                icon: Icons.fact_check_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniProgramEntry extends StatelessWidget {
  const _MiniProgramEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: kPullDemoPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: kPullDemoText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: kPullDemoSubtleText,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFeatureCardData {
  const _MiniFeatureCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

void registerPullDepthSwitchDemo() {
  demoRegistry.register(PullDepthSwitchDemo());
}
