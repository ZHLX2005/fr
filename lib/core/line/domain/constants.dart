/// 背景样式
enum BackgroundStyle { none, grid, lines }

// ── 布局常量 ──
const int columnCount = 3;
const double noteSizeRatio = 0.168;
const double judgeLineRatio = 0.75;

// ── 判定窗口（ms） ──
const int perfectWindow = 50;
const int greatWindow = 100;
const int goodWindow = 150;
const int missWindow = 200;

/// Hold 身段 tick 间隔（ms）
const int holdTickIntervalMs = 200;

/// Hold 尾判：相对 (time + holdDuration) 的窗口仍用 missWindow
const double holdEarlyReleaseRatio = 0.75;

// ── 手势阈值 ──
/// 滑动判定：位移超过此值即判为 swipe（px）
const double swipeDistanceThreshold = 48.0;

/// 滑动判定：速度超过此值（px/s）辅助确认
const double swipeVelocityThreshold = 280.0;

// ── 计分 ──
/// 连击倍率上限（base × min(1 + combo*k, max)）
const double comboMultiplierPerHit = 0.02;
const double comboMultiplierMax = 2.0;

// ── 持久化 key ──
const String lineTimingScaleKey = 'line_demo_timing_scale';
const String lineBackgroundKey = 'line_demo_background';
const String lineScrollSpeedKey = 'line_demo_scroll_speed';
const String lineInputOffsetKey = 'line_demo_input_offset_ms';
const String lineHapticsKey = 'line_demo_haptics';
const String lineHitSfxKey = 'line_demo_hit_sfx';
const String lineShowEarlyLateKey = 'line_demo_show_early_late';
