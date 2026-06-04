import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

import '../../core/novel_reader/canvas_reader_engine.dart';
import '../../widgets/hexagon_radar_painter.dart';

class CharacterProfilePage extends StatefulWidget {
  const CharacterProfilePage({super.key});

  @override
  State<CharacterProfilePage> createState() => _CharacterProfilePageState();
}

class _CharacterProfilePageState extends State<CharacterProfilePage> {
  late final Future<CharacterProfileData> _profileFuture = _loadProfile();
  late final rive.FileLoader _douziFileLoader = rive.FileLoader.fromAsset(
    'assets/rive/douzi.riv',
    riveFactory: rive.Factory.flutter,
  );
  _ProfileSection _activeSection = _ProfileSection.character;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _douziFileLoader.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onSectionChanged(int index) {
    setState(() {
      _activeSection = index == 0 ? _ProfileSection.character : _ProfileSection.story;
    });
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<CharacterProfileData> _loadProfile() async {
    final raw = await rootBundle.loadString(
      'assets/data/character_profiles/douzi_profile.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return CharacterProfileData.fromJson(json);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.05),
        colorScheme.surface,
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('人物小谱'),
      ),
      body: FutureBuilder<CharacterProfileData>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!;
          final hexagonItems = profile.analysis.items
              .map(
                (item) => HexagonItem(
                  label: item.label,
                  value: item.value,
                  color: item.color,
                ),
              )
              .toList();

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProfileDot(
                        active: _activeSection == _ProfileSection.character,
                        color: colorScheme.primary,
                        onTap: () => _goToPage(0),
                      ),
                      const SizedBox(width: 8),
                      _ProfileDot(
                        active: _activeSection == _ProfileSection.story,
                        color: colorScheme.secondary,
                        onTap: () => _goToPage(1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onSectionChanged,
                    children: [
                      _CharacterDetailPanel(
                        profile: profile,
                        fileLoader: _douziFileLoader,
                        hexagonItems: hexagonItems,
                      ),
                      _StoryDetailPanel(
                        story: profile.story,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _ProfileSection { character, story }

class _ProfileDot extends StatelessWidget {
  const _ProfileDot({
    required this.active,
    required this.color,
    this.onTap,
  });

  final bool active;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : Colors.transparent,
          border: active
              ? null
              : Border.all(
                  color: color.withValues(alpha: 0.4),
                  width: 1.5,
                ),
        ),
      ),
    );
  }
}

class _CharacterDetailPanel extends StatelessWidget {
  const _CharacterDetailPanel({
    required this.profile,
    required this.fileLoader,
    required this.hexagonItems,
  });

  final CharacterProfileData profile;
  final rive.FileLoader fileLoader;
  final List<HexagonItem> hexagonItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Expanded(
          child: _PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        profile.code,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        colorScheme.primary.withValues(alpha: 0.04),
                        colorScheme.surface,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: rive.RiveWidgetBuilder(
                        fileLoader: fileLoader,
                        dataBind: rive.DataBind.auto(),
                        builder: (context, state) => switch (state) {
                          rive.RiveLoading() => const SizedBox.shrink(),
                          rive.RiveFailed() => const SizedBox.shrink(),
                          rive.RiveLoaded(:final controller) => rive.RiveWidget(
                            controller: controller,
                            fit: rive.Fit.contain,
                            hitTestBehavior: rive.RiveHitTestBehavior.opaque,
                          ),
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  profile.tagline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.analysis.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight - 8,
                      );
                      return Center(
                        child: CustomPaint(
                          size: Size(size, size),
                          painter: HexagonRadarPainter(items: hexagonItems),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryDetailPanel extends StatefulWidget {
  const _StoryDetailPanel({
    required this.story,
  });

  final ProfileStoryData story;

  @override
  State<_StoryDetailPanel> createState() => _StoryDetailPanelState();
}

class _StoryDetailPanelState extends State<_StoryDetailPanel> {
  late NovelCanvasReaderController _readerController = _buildController(
    widget.story,
  );

  NovelCanvasReaderController _buildController(ProfileStoryData story) {
    final controller = NovelCanvasReaderController(title: story.title);
    controller.initialize(
      text: story.toReaderText(),
      initialPageIndex: 0,
      initialPageOffset: null,
    );
    controller.setTheme(NovelReaderTheme.paper);
    return controller;
  }

  @override
  void didUpdateWidget(covariant _StoryDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.story == widget.story) return;
    final oldController = _readerController;
    _readerController = _buildController(widget.story);
    oldController.dispose();
  }

  @override
  void dispose() {
    _readerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _PanelCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.story.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.story.caption,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AnimatedBuilder(
                    animation: _readerController,
                    builder: (context, _) {
                      final total = _readerController.totalDisplayPages;
                      final current = _readerController.currentDisplayPage;
                      return Text(
                        total == 0 ? '...' : '$current/$total',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: _StoryReaderPanel(controller: _readerController),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StoryReaderPanel extends StatelessWidget {
  const _StoryReaderPanel({
    required this.controller,
  });

  final NovelCanvasReaderController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF7E6CB),
                Color(0xFFE9CDA7),
                Color(0xFFD7AF7E),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF6EEE1).withValues(alpha: 0.74),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: NovelCanvasReaderView(
                  controller: controller,
                  onToggleChrome: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CharacterProfileData {
  CharacterProfileData({
    required this.code,
    required this.name,
    required this.subtitle,
    required this.tagline,
    required this.analysis,
    required this.story,
  });

  final String code;
  final String name;
  final String subtitle;
  final String tagline;
  final ProfileAnalysisData analysis;
  final ProfileStoryData story;

  factory CharacterProfileData.fromJson(Map<String, dynamic> json) {
    return CharacterProfileData(
      code: json['code'] as String,
      name: json['name'] as String,
      subtitle: json['subtitle'] as String,
      tagline: json['tagline'] as String,
      analysis: ProfileAnalysisData.fromJson(
        json['analysis'] as Map<String, dynamic>,
      ),
      story: ProfileStoryData.fromJson(json['story'] as Map<String, dynamic>),
    );
  }
}

class ProfileAnalysisData {
  ProfileAnalysisData({required this.title, required this.items});

  final String title;
  final List<ProfileTraitData> items;

  factory ProfileAnalysisData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>;
    return ProfileAnalysisData(
      title: json['title'] as String,
      items: rawItems
          .map((item) => ProfileTraitData.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ProfileTraitData {
  ProfileTraitData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  factory ProfileTraitData.fromJson(Map<String, dynamic> json) {
    return ProfileTraitData(
      label: json['label'] as String,
      value: (json['value'] as num).toDouble(),
      color: _colorFromHex(json['color'] as String),
    );
  }
}

class ProfileStoryData {
  ProfileStoryData({
    required this.title,
    required this.caption,
    required this.pages,
  });

  final String title;
  final String caption;
  final List<StoryPageData> pages;

  factory ProfileStoryData.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'] as List<dynamic>;
    return ProfileStoryData(
      title: json['title'] as String,
      caption: json['caption'] as String,
      pages: rawPages
          .map((item) => StoryPageData.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  String toReaderText() {
    return pages
        .map(
          (page) => [
            page.chapter,
            page.heading,
            '',
            page.content,
            if (page.footer.isNotEmpty) '',
            if (page.footer.isNotEmpty) page.footer,
          ].join('\n'),
        )
        .join('\n\n');
  }
}

class StoryPageData {
  StoryPageData({
    required this.chapter,
    required this.heading,
    required this.content,
    required this.footer,
  });

  final String chapter;
  final String heading;
  final String content;
  final String footer;

  factory StoryPageData.fromJson(Map<String, dynamic> json) {
    return StoryPageData(
      chapter: json['chapter'] as String,
      heading: json['heading'] as String,
      content: json['content'] as String,
      footer: json['footer'] as String,
    );
  }
}

Color _colorFromHex(String raw) {
  final normalized = raw.replaceFirst('#', '');
  final value = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.parse(value, radix: 16));
}
