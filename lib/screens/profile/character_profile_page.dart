import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

import '../../core/novel_reader/page_curl_view.dart';
import '../../lab/demos/hexagon_panel_demo.dart';

class CharacterProfilePage extends StatefulWidget {
  const CharacterProfilePage({super.key});

  @override
  State<CharacterProfilePage> createState() => _CharacterProfilePageState();
}

class _CharacterProfilePageState extends State<CharacterProfilePage> {
  late final Future<CharacterProfileData> _profileFuture = _loadProfile();
  late final rive.FileLoader _douziFileLoader = rive.FileLoader.fromAsset(
    'assets/rive/douzi.riv',
    riveFactory: rive.Factory.rive,
  );
  int _storyPageIndex = 0;
  _ProfileSection _activeSection = _ProfileSection.character;

  @override
  void dispose() {
    _douziFileLoader.dispose();
    super.dispose();
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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previousChildren,
                          ...?switch (currentChild) {
                            final child? => [child],
                            null => null,
                          },
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final isCharacter =
                          child.key == const ValueKey('character-panel');
                      final begin = isCharacter
                          ? const Offset(-0.08, 0)
                          : const Offset(0.08, 0);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: begin,
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _activeSection == _ProfileSection.character
                        ? _CharacterDetailPanel(
                            key: const ValueKey('character-panel'),
                            profile: profile,
                            fileLoader: _douziFileLoader,
                            hexagonItems: hexagonItems,
                          )
                        : _StoryDetailPanel(
                            key: const ValueKey('story-panel'),
                            story: profile.story,
                            pageIndex: _storyPageIndex,
                            onPageChanged: (value) {
                              setState(() {
                                _storyPageIndex = value;
                              });
                            },
                          ),
                  ),
                ),
                Positioned(
                  left: -14,
                  top: 28,
                  child: _BookmarkTab(
                    label: '人物',
                    side: _BookmarkSide.left,
                    active: _activeSection == _ProfileSection.character,
                    accentColor: colorScheme.primary,
                    onTap: () {
                      if (_activeSection != _ProfileSection.character) {
                        setState(() {
                          _activeSection = _ProfileSection.character;
                        });
                      }
                    },
                  ),
                ),
                Positioned(
                  right: -14,
                  top: 28,
                  child: _BookmarkTab(
                    label: '故事',
                    side: _BookmarkSide.right,
                    active: _activeSection == _ProfileSection.story,
                    accentColor: colorScheme.secondary,
                    onTap: () {
                      if (_activeSection != _ProfileSection.story) {
                        setState(() {
                          _activeSection = _ProfileSection.story;
                        });
                      }
                    },
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

enum _BookmarkSide { left, right }

class _BookmarkTab extends StatelessWidget {
  const _BookmarkTab({
    required this.label,
    required this.side,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final _BookmarkSide side;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = active
        ? accentColor
        : Color.alphaBlend(
            accentColor.withValues(alpha: 0.14),
            colorScheme.surfaceContainerHigh,
          );
    final foregroundColor = active
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: 48,
      height: 136,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(side == _BookmarkSide.left ? 18 : 14),
          right: Radius.circular(side == _BookmarkSide.right ? 18 : 14),
        ),
        boxShadow: [
          BoxShadow(
            color: (active ? accentColor : colorScheme.shadow).withValues(
              alpha: active ? 0.28 : 0.10,
            ),
            blurRadius: active ? 20 : 12,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(side == _BookmarkSide.left ? 18 : 14),
            right: Radius.circular(side == _BookmarkSide.right ? 18 : 14),
          ),
          onTap: onTap,
          child: Center(
            child: RotatedBox(
              quarterTurns: side == _BookmarkSide.left ? 3 : 1,
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: foregroundColor,
                  letterSpacing: 3.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterDetailPanel extends StatelessWidget {
  const _CharacterDetailPanel({
    super.key,
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

class _StoryDetailPanel extends StatelessWidget {
  const _StoryDetailPanel({
    super.key,
    required this.story,
    required this.pageIndex,
    required this.onPageChanged,
  });

  final ProfileStoryData story;
  final int pageIndex;
  final ValueChanged<int> onPageChanged;

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
                        story.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        story.caption,
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
                  child: Text(
                    '${pageIndex + 1}/${story.pages.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: _StoryReaderPanel(
                pages: story.pages,
                pageIndex: pageIndex,
                onPageChanged: onPageChanged,
              ),
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
    required this.pages,
    required this.pageIndex,
    required this.onPageChanged,
  });

  final List<StoryPageData> pages;
  final int pageIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final canTurnNext = pageIndex < pages.length - 1;
    final canTurnPrevious = pageIndex > 0;

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
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
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
              ),
            ),
            Positioned.fill(
              child: PageCurlView(
                currentPageBuilder: (context) =>
                    _StoryPaperPage(page: pages[pageIndex]),
                targetPageBuilder: canTurnNext
                    ? (context) => _StoryPaperPage(page: pages[pageIndex + 1])
                    : canTurnPrevious
                        ? (context) =>
                            _StoryPaperPage(page: pages[pageIndex - 1])
                        : null,
                canTurnNext: canTurnNext,
                canTurnPrevious: canTurnPrevious,
                onTurnFinished: (request) {
                  if (!request.completed) return;
                  final nextIndex = request.direction == PageTurnDirection.next
                      ? pageIndex + 1
                      : pageIndex - 1;
                  if (nextIndex < 0 || nextIndex >= pages.length) return;
                  onPageChanged(nextIndex);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryPaperPage extends StatelessWidget {
  const _StoryPaperPage({required this.page});

  final StoryPageData page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF4), Color(0xFFF5EBD9)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.chapter,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF402A1D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      page.heading,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF8A6A52),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Text(
                page.content,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF4B3527),
                  height: 1.8,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              page.footer,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF8A6A52),
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
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
