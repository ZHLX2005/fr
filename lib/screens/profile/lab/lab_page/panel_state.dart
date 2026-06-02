part of '../lab_page.dart';

class LabPanelColors {
  final Color gradientTop;
  final Color gradientMiddle;
  final Color gradientBottom;
  final Color accent;
  final Color accentSoft;
  final Color accentDeep;
  final Color text;
  final Color mutedText;
  final Color glassFill;
  final Color glassBorder;
  final bool isDark;

  const LabPanelColors({
    required this.gradientTop,
    required this.gradientMiddle,
    required this.gradientBottom,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
    required this.text,
    required this.mutedText,
    required this.glassFill,
    required this.glassBorder,
    required this.isDark,
  });

  factory LabPanelColors.resolve(ColorScheme cs, {required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    return LabPanelColors(
      // 渐变背景：surface → surfaceContainerHighest，使用主题设计好的色阶
      gradientTop: cs.surface,
      gradientMiddle: ColorUtils.mix(cs.surface, cs.surfaceContainerHighest, 0.5),
      gradientBottom: cs.surfaceContainerHighest,
      // 强调色：直接使用 ColorScheme 设计好的主色关系
      accent: cs.primary,
      accentSoft: cs.primaryContainer,
      accentDeep: cs.onPrimaryContainer,
      // 文字色
      text: cs.onSurface,
      mutedText: cs.onSurfaceVariant,
      // 毛玻璃容器：用 surface 半透明，自然适配亮暗
      glassFill: cs.surface.withValues(alpha: isDark ? 0.18 : 0.60),
      glassBorder: cs.surface.withValues(alpha: isDark ? 0.12 : 0.50),
      isDark: isDark,
    );
  }
}

enum LabPullPanelState {
  collapsed,
  draggingMain,
  draggingPanel,
  settling,
  expanded,
}

enum LabPullPanelActionType { none, animateTo }

class LabPullPanelAction {
  final LabPullPanelActionType type;
  final double? targetProgress;

  const LabPullPanelAction._(this.type, {this.targetProgress});

  const LabPullPanelAction.none() : this._(LabPullPanelActionType.none);

  const LabPullPanelAction.animateTo(double target)
    : this._(LabPullPanelActionType.animateTo, targetProgress: target);
}

class LabPullPanelMetrics {
  static const double topEpsilon = 0.5;
  static const double mainDragDeadZone = 8.0;
  static const double panelDragDeadZone = 8.0;
  static const double collapsedEpsilon = 0.001;
  static const double openThreshold = 0.22;
  static const double closeThresholdPx = 96.0;
  static const double velocityOpen = 500;
  static const double velocityClose = -500;
  static const double dragDamping = 0.8;
  static const double overdragResistance = 0.10;
  static const double mainPushRatio = 1.0;

  const LabPullPanelMetrics._();

  static double applyDrag({
    required double currentProgress,
    required double deltaDy,
    required double fullHeight,
  }) {
    final panelRangePx = fullHeight;
    final dampedDelta = deltaDy * dragDamping;
    final raw = currentProgress * panelRangePx + dampedDelta;

    double resisted = raw;
    if (raw > panelRangePx) {
      resisted = panelRangePx + (raw - panelRangePx) * overdragResistance;
    } else if (raw < 0) {
      resisted = raw * overdragResistance;
    }

    return (resisted / panelRangePx).clamp(0.0, 1.0);
  }
}

class LabPullPanelStateMachine {
  LabPullPanelState _state = LabPullPanelState.collapsed;
  double _progress = 0.0;
  double _pendingMainDragDy = 0.0;
  double _pendingPanelDragDy = 0.0;
  double _panelDragDistancePx = 0.0;

  LabPullPanelState get state => _state;
  double get progress => _progress;

  bool get mainContentInteractive => _state == LabPullPanelState.collapsed;

  bool get panelScrollable =>
      _state == LabPullPanelState.expanded ||
      _state == LabPullPanelState.draggingPanel;

  bool get showMainCue =>
      _state == LabPullPanelState.collapsed ||
      _state == LabPullPanelState.draggingMain;

  bool get showCloseCue =>
      _state == LabPullPanelState.expanded ||
      _state == LabPullPanelState.draggingPanel;

  bool get readyToOpen => _progress >= LabPullPanelMetrics.openThreshold;

  double get closeProgress {
    if (_progress >= 1.0) return 0.0;
    return ((1.0 - _progress) / LabPullPanelMetrics.openThreshold).clamp(
      0.0,
      1.0,
    );
  }

  void syncProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
    if (_progress <= 0.0 && _state != LabPullPanelState.settling) {
      _state = LabPullPanelState.collapsed;
    }
  }

  void beginMainDrag() {
    if (_state == LabPullPanelState.settling) {
      print('[PanelBug] beginMainDrag blocked by settling!');
    }
    if (_state == LabPullPanelState.settling ||
        _state == LabPullPanelState.expanded ||
        _state == LabPullPanelState.draggingPanel) {
      return;
    }
    _pendingMainDragDy = 0.0;
  }

  void updateMainDrag({required double deltaDy, required double fullHeight}) {
    var effectiveDeltaDy = deltaDy;

    if (_state != LabPullPanelState.draggingMain) {
      _pendingMainDragDy += effectiveDeltaDy;
      final passedDeadZone =
          _pendingMainDragDy.abs() >= LabPullPanelMetrics.mainDragDeadZone;
      if (!passedDeadZone) return;

      if (_pendingMainDragDy <= 0) {
        _pendingMainDragDy = 0.0;
        return;
      }

      _state = LabPullPanelState.draggingMain;
      effectiveDeltaDy = _pendingMainDragDy;
      _pendingMainDragDy = 0.0;
    }

    _progress = LabPullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: effectiveDeltaDy,
      fullHeight: fullHeight,
    );
  }

  LabPullPanelAction endMainDrag({required double velocityDy}) {
    if (_state != LabPullPanelState.draggingMain) {
      _pendingMainDragDy = 0.0;
      if (_progress <= LabPullPanelMetrics.collapsedEpsilon) {
        _progress = 0.0;
        _state = LabPullPanelState.collapsed;
      }
      return const LabPullPanelAction.none();
    }

    _pendingMainDragDy = 0.0;

    if (_progress <= LabPullPanelMetrics.collapsedEpsilon) {
      _progress = 0.0;
      _state = LabPullPanelState.collapsed;
      return const LabPullPanelAction.none();
    }

    final shouldOpen =
        _progress >= LabPullPanelMetrics.openThreshold ||
        velocityDy > LabPullPanelMetrics.velocityOpen;

    _state = LabPullPanelState.settling;
    return LabPullPanelAction.animateTo(shouldOpen ? 1.0 : 0.0);
  }

  void beginPanelDrag() {
    if (_state == LabPullPanelState.settling) {
      print('[PanelBug] beginPanelDrag blocked by settling!');
    }
    if (_state == LabPullPanelState.draggingPanel) return;
    if (_state == LabPullPanelState.settling ||
        _state == LabPullPanelState.collapsed ||
        _state == LabPullPanelState.draggingMain) {
      return;
    }
    _pendingPanelDragDy = 0.0;
    _panelDragDistancePx = 0.0;
  }

  void updatePanelDrag({required double deltaDy, required double fullHeight}) {
    if (_state != LabPullPanelState.expanded &&
        _state != LabPullPanelState.draggingPanel) {
      return;
    }

    var effectiveDeltaDy = deltaDy;

    if (_state != LabPullPanelState.draggingPanel) {
      _pendingPanelDragDy += effectiveDeltaDy;
      final passedDeadZone =
          _pendingPanelDragDy.abs() >= LabPullPanelMetrics.panelDragDeadZone;
      if (!passedDeadZone) return;

      if (_pendingPanelDragDy >= 0) {
        _pendingPanelDragDy = 0.0;
        return;
      }

      _state = LabPullPanelState.draggingPanel;
      effectiveDeltaDy = _pendingPanelDragDy;
      _pendingPanelDragDy = 0.0;
    }

    _state = LabPullPanelState.draggingPanel;
    // Track net close distance so an immediate reverse drag can cancel closing.
    _panelDragDistancePx = math.max(0.0, _panelDragDistancePx - effectiveDeltaDy);
    _progress = LabPullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: effectiveDeltaDy,
      fullHeight: fullHeight,
    );
  }

  LabPullPanelAction endPanelDrag({required double velocityDy}) {
    if (_state != LabPullPanelState.draggingPanel) {
      _pendingPanelDragDy = 0.0;
      _panelDragDistancePx = 0.0;
      return const LabPullPanelAction.none();
    }

    _pendingPanelDragDy = 0.0;
    _state = LabPullPanelState.settling;
    final shouldClose =
        _panelDragDistancePx >= LabPullPanelMetrics.closeThresholdPx ||
        velocityDy < LabPullPanelMetrics.velocityClose;
    _panelDragDistancePx = 0.0;
    return LabPullPanelAction.animateTo(shouldClose ? 0.0 : 1.0);
  }

  void onAnimationStarted() {
    _pendingMainDragDy = 0.0;
    _pendingPanelDragDy = 0.0;
    _panelDragDistancePx = 0.0;
    _state = LabPullPanelState.settling;
  }

  void onAnimationCompleted(double targetProgress) {
    assert(
      _state == LabPullPanelState.settling,
      '[PanelBug] onAnimationCompleted called from invalid state: $_state (expected settling)',
    );
    _pendingMainDragDy = 0.0;
    _pendingPanelDragDy = 0.0;
    _panelDragDistancePx = 0.0;
    _progress = targetProgress.clamp(0.0, 1.0);
    if (_progress <= 0.0) {
      _state = LabPullPanelState.collapsed;
    } else if (_progress >= 1.0) {
      _state = LabPullPanelState.expanded;
    } else {
      _state = LabPullPanelState.collapsed;
    }
  }
}

const _kAnimationDuration = Duration(milliseconds: 260);
