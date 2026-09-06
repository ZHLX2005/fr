/// 背景样式
enum BackgroundStyle { none, grid, lines }

// ── 布局常量 ──
const int columnCount = 3;
/// 音符相对列宽半径比例（越大音符越大）
const double noteSizeRatio = 0.22;
const double judgeLineRatio = 0.75;

// ── 判定窗口（ms）——偏宽容，优先手感与可玩性 ──
const int perfectWindow = 70;
const int greatWindow = 130;
const int goodWindow = 200;
const int missWindow = 280;

/// Hold 身段 tick 间隔（ms）
const int holdTickIntervalMs = 200;

/// Hold 尾判：相对 (time + holdDuration) —— 当前机制**不启用尾判**，
/// 仅用此比例判断「过早松手」是否 Miss。
const double holdEarlyReleaseRatio = 0.62;

// ── 手势阈值 ──
/// 滑动判定：位移超过此值即判为 swipe（px）
const double swipeDistanceThreshold = 28.0;

/// 滑动判定：速度超过此值（px/s）辅助确认
const double swipeVelocityThreshold = 150.0;

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
const String lineSfxVolumeKey = 'line_demo_sfx_volume';
const String lineBgmVolumeKey = 'line_demo_bgm_volume';

/// 默认击打音量 / BGM 音量（用户偏好；音效可到 [lineSfxVolumeMax]）
const double lineDefaultSfxVolume = 0.65;
const double lineDefaultBgmVolume = 0.7;

/// 音效音量滑条上限（>1 为轻度额外增益）
const double lineSfxVolumeMax = 1.5;

/// 下落速度倍率范围
const double lineScrollSpeedMin = 0.5;
const double lineScrollSpeedMax = 5.0;
