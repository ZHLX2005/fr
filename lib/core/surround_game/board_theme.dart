// lib/core/surround_game/board_theme.dart
//
// 棋盘语义色令牌系统 — 6 层视觉栈的所有颜色都从这里取。
//
// 设计原则：
// - 每个颜色 token 都对应一个语义角色（surface / faceLight / edgeShadow ...）
//   而不是一个具体十六进制值。换肤只需替换 token 值，绘制代码完全不动。
// - 通过 Flutter 官方 [ThemeExtension] 注入，组件从 BuildContext 读取；
//   老代码里的 [GameTheme] 静态常量将逐步迁移到本系统。
// - 提供两套预设（warm 暖色 / cool 紫色），并支持新增主题。
//
// ──────────────────────────────────────────────────────────────
// 视觉栈分层（自下而上，绘制顺序）：
//   0. boardSurface        — 棋盘底板（9×9 之外的边距）
//   1. cellBase            — 格子底色（未命中合法步时）
//   2. cellFaceLight       — 格子"凸起"面的高光色（光源在左上）
//   3. cellFaceShadow      — 格子"凹陷"面的暗部色
//   4. cellEdge            — 格子描边色
//   5. cellInsetHighlight  — 确认阶段，目标格的二次高亮
//
// 棋子与墙壁的 3D 效果也使用语义令牌：
//   - piecePlayerA/B       — 双方棋子基色（中心渐变起点）
//   - pieceHighlightA/B    — 棋子高光色（径向渐变中心）
//   - pieceRimA/B          — 棋子边缘暗色（径向渐变外圈）
//   - wallPlayerA/B        — 双方墙基色
//   - wallEdgeLightA/B     — 墙"上沿"高光（凸起感）
//   - wallEdgeShadowA/B    — 墙"下沿"暗色
//
// 状态色：
//   - validMoveRing        — 合法落子提示环
//   - wallPreviewValid     — 墙放置预览（合法）
//   - wallPreviewInvalid   — 墙放置预览（非法）
//   - confirmOverlay       — 确认阶段的薄薄一层
// ──────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

/// 棋盘语义色令牌集合
///
/// 一个不可变的颜色集合，对应棋盘视觉栈里的每一个角色。
/// 切换主题就是换一个 [BoardThemeData] 实例，所有引用 token 的
/// 绘制代码不需要任何修改。
@immutable
class BoardThemeData {
  // ── 0. 棋盘底板 ──
  final Color boardSurface;

  // ── 1-5. 格子 ──
  final Color cellBase;
  final Color cellFaceLight;
  final Color cellFaceShadow;
  final Color cellEdge;
  final Color cellInsetHighlight;

  // ── 棋子（双方） ──
  final Color piecePlayerA;
  final Color pieceHighlightA;
  final Color pieceRimA;

  final Color piecePlayerB;
  final Color pieceHighlightB;
  final Color pieceRimB;

  // ── 墙壁（双方） ──
  final Color wallPlayerA;
  final Color wallEdgeLightA;
  final Color wallEdgeShadowA;

  final Color wallPlayerB;
  final Color wallEdgeLightB;
  final Color wallEdgeShadowB;

  // ── 状态色 ──
  final Color validMoveRing;
  final Color wallPreviewValid;
  final Color wallPreviewInvalid;

  // ── UI 面板色（与 GameTheme 对齐） ──
  final Color panelBg;
  final Color panelBorder;
  final Color btnBg;
  final Color btnBorder;
  final Color btnText;
  final Color btnSub;

  const BoardThemeData({
    required this.boardSurface,
    required this.cellBase,
    required this.cellFaceLight,
    required this.cellFaceShadow,
    required this.cellEdge,
    required this.cellInsetHighlight,
    required this.piecePlayerA,
    required this.pieceHighlightA,
    required this.pieceRimA,
    required this.piecePlayerB,
    required this.pieceHighlightB,
    required this.pieceRimB,
    required this.wallPlayerA,
    required this.wallEdgeLightA,
    required this.wallEdgeShadowA,
    required this.wallPlayerB,
    required this.wallEdgeLightB,
    required this.wallEdgeShadowB,
    required this.validMoveRing,
    required this.wallPreviewValid,
    required this.wallPreviewInvalid,
    required this.panelBg,
    required this.panelBorder,
    required this.btnBg,
    required this.btnBorder,
    required this.btnText,
    required this.btnSub,
  });

  // ─────────────────── 预设主题 ───────────────────

  /// 默认主题 — 暖色（米白/棕）+ 橙粉棋子
  ///
  /// 玩家 A = 上方 = 橙色， 玩家 B = 下方 = 粉色。
  /// 棋盘底色温暖，格子带柔和的浅米高光。
  static const BoardThemeData warm = BoardThemeData(
    // 棋盘底板
    boardSurface: Color(0xFFF8F0E3),
    // 格子
    cellBase: Color(0xFFEDE3D0),
    cellFaceLight: Color(0xFFF5ECDA), // 高光：左上角
    cellFaceShadow: Color(0xFFD8CCB0), // 暗部：右下角
    cellEdge: Color(0xFFC4B49A),
    cellInsetHighlight: Color(0xFFB8E0B0), // 确认目标格：柔绿
    // 玩家 A — 橙色（顶部）
    piecePlayerA: Color(0xFFF4A523),
    pieceHighlightA: Color(0xFFFFD27A),
    pieceRimA: Color(0xFFB36A00),
    // 玩家 B — 粉色（底部）
    piecePlayerB: Color(0xFFEE8E9A),
    pieceHighlightB: Color(0xFFFFC2CC),
    pieceRimB: Color(0xFFB85A68),
    // 墙壁 A
    wallPlayerA: Color(0xFFF4A523),
    wallEdgeLightA: Color(0xFFFFD27A),
    wallEdgeShadowA: Color(0xFFA06400),
    // 墙壁 B
    wallPlayerB: Color(0xFFEE8E9A),
    wallEdgeLightB: Color(0xFFFFC2CC),
    wallEdgeShadowB: Color(0xFFA85060),
    // 状态色
    validMoveRing: Color(0xFF7CFFE5),
    wallPreviewValid: Color(0xFF7CFFE5),
    wallPreviewInvalid: Color(0xFFFF7CB8),
    // 面板
    panelBg: Color(0xFFE8DDCB),
    panelBorder: Color(0xFFD4C5A9),
    btnBg: Color(0xFFF5EDE0),
    btnBorder: Color(0xFFD4C5A9),
    btnText: Color(0xFF5C4E3A),
    btnSub: Color(0xFF9C8E7A),
  );

  /// 备选主题 — 冷色（紫色）+ 青绿墙
  ///
  /// 对应 Swift 原版亮色主题。
  static const BoardThemeData cool = BoardThemeData(
    // 棋盘底板
    boardSurface: Color(0xFFBA99F1),
    // 格子
    cellBase: Color(0xFFFFFFFF),
    cellFaceLight: Color(0xFFFFFFFF),
    cellFaceShadow: Color(0xFFE6DCFB),
    cellEdge: Color(0xFF89DFF1),
    cellInsetHighlight: Color(0xFFB8E0B0),
    // 玩家 A — 同 warm（棋子颜色保持品牌识别）
    piecePlayerA: Color(0xFFF4A523),
    pieceHighlightA: Color(0xFFFFD27A),
    pieceRimA: Color(0xFFB36A00),
    piecePlayerB: Color(0xFFEE8E9A),
    pieceHighlightB: Color(0xFFFFC2CC),
    pieceRimB: Color(0xFFB85A68),
    // 墙壁 — 冷色版保持青绿
    wallPlayerA: Color(0xFF76FFD0),
    wallEdgeLightA: Color(0xFFB0FFE6),
    wallEdgeShadowA: Color(0xFF26B98A),
    wallPlayerB: Color(0xFF76FFD0),
    wallEdgeLightB: Color(0xFFB0FFE6),
    wallEdgeShadowB: Color(0xFF26B98A),
    // 状态色
    validMoveRing: Color(0xFF76FFD0),
    wallPreviewValid: Color(0xFF76FFD0),
    wallPreviewInvalid: Color(0xFFFF7CB8),
    // 面板
    panelBg: Color(0xFFC9ADE8),
    panelBorder: Color(0xFFB89DE0),
    btnBg: Color(0xFFD4BCF0),
    btnBorder: Color(0xFFB89DE0),
    btnText: Color(0xFF1A1A1A),
    btnSub: Color(0xFF6A6A6A),
  );

  /// 线性插值 — 用于主题切换动画
  ///
  /// 返回一个新的 [BoardThemeData]，所有颜色取两个主题对应颜色
  /// 在 [t]（0..1）位置的中间值。
  static BoardThemeData lerp(BoardThemeData a, BoardThemeData b, double t) {
    return BoardThemeData(
      boardSurface: Color.lerp(a.boardSurface, b.boardSurface, t)!,
      cellBase: Color.lerp(a.cellBase, b.cellBase, t)!,
      cellFaceLight: Color.lerp(a.cellFaceLight, b.cellFaceLight, t)!,
      cellFaceShadow: Color.lerp(a.cellFaceShadow, b.cellFaceShadow, t)!,
      cellEdge: Color.lerp(a.cellEdge, b.cellEdge, t)!,
      cellInsetHighlight:
          Color.lerp(a.cellInsetHighlight, b.cellInsetHighlight, t)!,
      piecePlayerA: Color.lerp(a.piecePlayerA, b.piecePlayerA, t)!,
      pieceHighlightA: Color.lerp(a.pieceHighlightA, b.pieceHighlightA, t)!,
      pieceRimA: Color.lerp(a.pieceRimA, b.pieceRimA, t)!,
      piecePlayerB: Color.lerp(a.piecePlayerB, b.piecePlayerB, t)!,
      pieceHighlightB: Color.lerp(a.pieceHighlightB, b.pieceHighlightB, t)!,
      pieceRimB: Color.lerp(a.pieceRimB, b.pieceRimB, t)!,
      wallPlayerA: Color.lerp(a.wallPlayerA, b.wallPlayerA, t)!,
      wallEdgeLightA: Color.lerp(a.wallEdgeLightA, b.wallEdgeLightA, t)!,
      wallEdgeShadowA: Color.lerp(a.wallEdgeShadowA, b.wallEdgeShadowA, t)!,
      wallPlayerB: Color.lerp(a.wallPlayerB, b.wallPlayerB, t)!,
      wallEdgeLightB: Color.lerp(a.wallEdgeLightB, b.wallEdgeLightB, t)!,
      wallEdgeShadowB: Color.lerp(a.wallEdgeShadowB, b.wallEdgeShadowB, t)!,
      validMoveRing: Color.lerp(a.validMoveRing, b.validMoveRing, t)!,
      wallPreviewValid: Color.lerp(a.wallPreviewValid, b.wallPreviewValid, t)!,
      wallPreviewInvalid:
          Color.lerp(a.wallPreviewInvalid, b.wallPreviewInvalid, t)!,
      panelBg: Color.lerp(a.panelBg, b.panelBg, t)!,
      panelBorder: Color.lerp(a.panelBorder, b.panelBorder, t)!,
      btnBg: Color.lerp(a.btnBg, b.btnBg, t)!,
      btnBorder: Color.lerp(a.btnBorder, b.btnBorder, t)!,
      btnText: Color.lerp(a.btnText, b.btnText, t)!,
      btnSub: Color.lerp(a.btnSub, b.btnSub, t)!,
    );
  }
}

/// Flutter [ThemeExtension] 包装
///
/// 用法：在 MaterialApp 里
/// ```dart
/// theme: ThemeData(extensions: [BoardTheme.warm]),
/// darkTheme: ThemeData(extensions: [BoardTheme.cool]),
/// ```
/// 然后组件内 `Theme.of(context).extension<BoardTheme>()!.data` 拿 token。
@immutable
class BoardTheme extends ThemeExtension<BoardTheme> {
  final BoardThemeData data;

  const BoardTheme({required this.data});

  /// 默认（暖色）主题
  static const BoardTheme warm = BoardTheme(data: BoardThemeData.warm);

  /// 备选（冷色紫色）主题
  static const BoardTheme cool = BoardTheme(data: BoardThemeData.cool);

  /// 便捷读取：context → token 集合
  ///
  /// 若主题未注入（开发期或单元测试），回退到 [BoardThemeData.warm]
  /// 以保证绘制代码始终拿到非空 token。
  static BoardThemeData of(BuildContext context) {
    final ext = Theme.of(context).extension<BoardTheme>();
    return ext?.data ?? BoardThemeData.warm;
  }

  @override
  BoardTheme copyWith({BoardThemeData? data}) =>
      BoardTheme(data: data ?? this.data);

  @override
  BoardTheme lerp(ThemeExtension<BoardTheme>? other, double t) {
    if (other is! BoardTheme) return this;
    return BoardTheme(data: BoardThemeData.lerp(data, other.data, t));
  }
}