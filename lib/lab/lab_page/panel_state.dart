part of '../../screens/lab/lab_page.dart';

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
  static const double mainPushRatio = 0.60;

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
    if (effectiveDeltaDy < 0) {
      _panelDragDistancePx += -effectiveDeltaDy;
    }
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

const _kPanelGradientTop = Color(0xFFF8F3EE);
const _kPanelGradientMiddle = Color(0xFFEFE6DD);
const _kPanelGradientBottom = Color(0xFFE4D6C8);
const _kAccentColor = Color(0xFFC88A5A);
const _kAccentSoftColor = Color(0xFFD9A97C);
const _kAccentDeepColor = Color(0xFF8B5E3C);
const _kPanelTextColor = Color(0xFF5E4735);
const _kPanelMutedTextColor = Color(0xFF8E7561);
const _kAnimationDuration = Duration(milliseconds: 260);
const _kWaveDuration = Duration(seconds: 2);
