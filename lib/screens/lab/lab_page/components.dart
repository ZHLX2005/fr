part of '../lab_page.dart';

class _DemoCard extends StatefulWidget {
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DemoCard({
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  State<_DemoCard> createState() => _DemoCardState();
}

class _DemoCardState extends State<_DemoCard> {
  final _provider = LabCardProvider();
  final _cacheService = LabImageCacheService();
  bool _isPressed = false;
  Uint8List? _cachedImageBytes;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
    _cacheService.init();
    _initAndPreload();
  }

  Future<void> _initAndPreload() async {
    await _provider.onLoaded;
    if (mounted) _preloadImage();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() async {
    if (mounted) {
      await _provider.onLoaded;
      if (mounted) {
        _preloadImage();
        setState(() {});
      }
    }
  }

  Future<void> _preloadImage() async {
    final backgroundUrl = _provider.getBackground(widget.title);
    if (backgroundUrl != null && _provider.isLocalFile(widget.title)) {
      final bytes = await _cacheService.getThumbnailBytes(backgroundUrl);
      if (bytes != null && mounted) {
        setState(() {
          _cachedImageBytes = bytes;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundUrl = _provider.getBackground(widget.title);
    final isLocalFile =
        backgroundUrl != null && _provider.isLocalFile(widget.title);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: () => _showBackgroundDialog(context),
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backgroundUrl != null && backgroundUrl.isNotEmpty)
                Positioned.fill(
                  child: isLocalFile
                      ? _buildLocalImage(backgroundUrl, theme)
                      : _buildNetworkImage(backgroundUrl, theme),
                ),
              if (backgroundUrl != null && backgroundUrl.isNotEmpty)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.widgets,
                      color: backgroundUrl != null
                          ? Colors.white
                          : theme.colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: backgroundUrl != null ? Colors.white : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        widget.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: backgroundUrl != null
                              ? Colors.white70
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildNetworkImage(String url, ThemeData theme) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(color: theme.colorScheme.surfaceContainerHighest);
      },
    );
  }

  Widget _buildLocalImage(String path, ThemeData theme) {
    if (_cachedImageBytes != null) {
      return Image.memory(
        _cachedImageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image),
        ),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image),
      ),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }

  void _showBackgroundDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BackgroundSettingSheet(
        demoTitle: widget.title,
        currentUrl: _provider.getBackground(widget.title),
        isLocalFile: _provider.isLocalFile(widget.title),
        isFavorite: _provider.isFavorite(widget.title),
        onImageSelected: (url) async {
          await _provider.setBackground(widget.title, url);
          if (context.mounted) Navigator.pop(context);
        },
        onFavoriteChanged: (value) =>
            _provider.setFavorite(widget.title, value),
        onRemove: () async {
          await _provider.removeBackground(widget.title);
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

class _BackgroundSettingSheet extends StatefulWidget {
  final String demoTitle;
  final String? currentUrl;
  final bool isLocalFile;
  final bool isFavorite;
  final Future<void> Function(String) onImageSelected;
  final Future<void> Function(bool) onFavoriteChanged;
  final VoidCallback onRemove;

  const _BackgroundSettingSheet({
    required this.demoTitle,
    required this.currentUrl,
    this.isLocalFile = false,
    required this.isFavorite,
    required this.onImageSelected,
    required this.onFavoriteChanged,
    required this.onRemove,
  });

  @override
  State<_BackgroundSettingSheet> createState() =>
      _BackgroundSettingSheetState();
}

class _BackgroundSettingSheetState extends State<_BackgroundSettingSheet> {
  String _customUrl = '';
  bool _isLoading = false;
  late bool _isFavorite = widget.isFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image, size: 24),
              const SizedBox(width: 8),
              Text('Set Background Image', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (widget.currentUrl != null)
                TextButton.icon(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _pickAndCropImage,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.crop),
                  label: const Text('Pick And Crop'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickLocalImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Pick Only'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _isLoading ? null : _toggleFavorite,
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
              label: Text(_isFavorite ? 'Unfavorite Demo' : 'Favorite Demo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Custom Image URL', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/image.jpg',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) => _customUrl = value,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _isLoading || _customUrl.isEmpty
                    ? null
                    : () => _selectImage(_customUrl),
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Preset Images', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
              ),
              itemCount: LabCardProvider.presetImages.length,
              itemBuilder: (context, index) {
                final url = LabCardProvider.presetImages[index];
                final isSelected = widget.currentUrl == url;

                return GestureDetector(
                  onTap: () => _selectImage(url),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image),
                              ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndCropImage() async {
    setState(() => _isLoading = true);
    try {
      final imagePath = await ImagePickerPage.navigate(
        context,
        config: const ImagePickerConfig(
          aspectRatioX: 1,
          aspectRatioY: 1,
          lockAspectRatio: false,
        ),
        initialImagePath: widget.isLocalFile ? widget.currentUrl : null,
        title: 'Set Card Background',
        emptyStateHint: 'Select a background image',
        emptyStateSubHint: 'Freely adjust the crop area',
      );
      if (imagePath != null) {
        await widget.onImageSelected(imagePath);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLocalImage() async {
    setState(() => _isLoading = true);
    try {
      final imagePath = await ImagePickerPage.navigate(
        context,
        config: const ImagePickerConfig(enableCrop: false),
        initialImagePath: widget.isLocalFile ? widget.currentUrl : null,
        title: 'Select Background Image',
        emptyStateHint: 'Select a background image',
        emptyStateSubHint: '',
      );
      if (imagePath != null) {
        await widget.onImageSelected(imagePath);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectImage(String url) async {
    setState(() => _isLoading = true);
    try {
      await widget.onImageSelected(url);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isLoading = true);
    try {
      final nextValue = !_isFavorite;
      await widget.onFavoriteChanged(nextValue);
      if (mounted) {
        setState(() => _isFavorite = nextValue);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _DemoDetailPage extends StatelessWidget {
  final DemoPage demo;

  const _DemoDetailPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: demo.preferFullScreen
          ? null
          : AppBar(
              title: GestureDetector(
                onTap: () => _showDemoDesc(context),
                behavior: HitTestBehavior.opaque,
                child: Text(demo.title),
              ),
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
      body: demo.buildPage(context),
    );
  }

  void _showDemoDesc(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.widgets),
            const SizedBox(width: 8),
            Flexible(child: Text(demo.title)),
          ],
        ),
        content: Text(demo.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ScrollRevealGrid extends StatefulWidget {
  const _ScrollRevealGrid({
    required this.demos,
    required this.controller,
    required this.onDemoTap,
    required this.physics,
  });

  final List<MapEntry<String, DemoPage>> demos;
  final ScrollController controller;
  final ValueChanged<DemoPage> onDemoTap;
  final ScrollPhysics physics;

  @override
  State<_ScrollRevealGrid> createState() => _ScrollRevealGridState();
}

class _ScrollRevealGridState extends State<_ScrollRevealGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: widget.controller,
      physics: widget.physics,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: widget.demos.length,
      itemBuilder: (context, index) {
        final demo = widget.demos[index].value;
        return _RevealItem(
          index: index,
          controller: _controller,
          child: _DemoCard(
            title: demo.title,
            description: demo.description,
            onTap: () => widget.onDemoTap(demo),
          ),
        );
      },
    );
  }
}

class _RevealItem extends StatefulWidget {
  const _RevealItem({
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final AnimationController controller;
  final Widget child;

  @override
  State<_RevealItem> createState() => _RevealItemState();
}

class _RevealItemState extends State<_RevealItem> {
  double get _delay => (widget.index * 0.06).clamp(0.0, 0.72);
  double get _dur => 0.28;

  double _progress(double t) {
    final start = _delay;
    final end = start + _dur;
    if (t < start) return 0.0;
    if (t >= end) return 1.0;
    return Curves.easeOutCubic.transform((t - start) / (end - start));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = _progress(widget.controller.value);
        if (p >= 1.0) {
          return widget.child;
        }
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - p)),
            child: widget.child,
          ),
        );
      },
    );
  }
}
