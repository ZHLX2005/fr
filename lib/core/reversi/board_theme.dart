// lib/core/reversi/board_theme.dart
//
// 翻转棋语义色令牌系统 — 与 surround_game 的 BoardThemeData 共用同一设计语言。
//
// 视觉栈分层（自下而上）：
//   0. boardSurface       — 棋盘底板
//   1. cellBase          — 格子底色
//   2. cellFaceLight     — 格子左上高光（凸起感）
//   3. cellFaceShadow    — 格子右下暗部
//   4. cellEdge          — 格子描边
//
// 棋子：
//   - pieceBlack         — 黑棋基色
//   - pieceWhite         — 白棋基色
//   - pieceHighlight     — 棋子高光
//   - pieceRim           — 棋子边缘暗
//
// 状态色：
//   - legalHint         — 合法步提示点
//   - lastMoveRing      — 最近一步高亮环
//
// UI 面板：
//   - panelBg           — 面板背景
//   - panelBorder       — 面板边框
//   - btnText           — 按钮主文字
//   - btnSub            — 按钮副文字
import 'package:flutter/material.dart';

/// 翻转棋语义色令牌集合
@immutable
class ReversiThemeData {
  // ── 棋盘 ──
  final Color boardSurface;
  final Color cellBase;
  final Color cellFaceLight;
  final Color cellFaceShadow;
  final Color cellEdge;

  // ── 棋子 ──
  final Color pieceBlack;
  final Color pieceBlackHighlight;
  final Color pieceBlackRim;
  final Color pieceWhite;
  final Color pieceWhiteHighlight;
  final Color pieceWhiteRim;

  // ── 状态色 ──
  final Color legalHintBlack; // 黑方回合时合法步提示色
  final Color legalHintWhite; // 白方回合时合法步提示色
  final Color lastMoveRing;
  final Color winAccent; // 胜利强调色（用于弹层/遮罩）

  // ── UI 面板 ──
  final Color panelBg;
  final Color panelBorder;
  final Color btnText;
  final Color btnSub;

  const ReversiThemeData({
    required this.boardSurface,
    required this.cellBase,
    required this.cellFaceLight,
    required this.cellFaceShadow,
    required this.cellEdge,
    required this.pieceBlack,
    required this.pieceBlackHighlight,
    required this.pieceBlackRim,
    required this.pieceWhite,
    required this.pieceWhiteHighlight,
    required this.pieceWhiteRim,
    required this.legalHintBlack,
    required this.legalHintWhite,
    required this.lastMoveRing,
    required this.winAccent,
    required this.panelBg,
    required this.panelBorder,
    required this.btnText,
    required this.btnSub,
  });

  /// 默认主题 — 参考 surround_game warm 暖色（深米白底 + 黑/白木质感棋子）
  /// 棋盘底色温暖，格子带柔和凸起感，棋子白底黑边/黑底白边
  static const ReversiThemeData classic = ReversiThemeData(
    boardSurface: Color(0xFFF8F0E3),
    cellBase: Color(0xFFEDE3D0),
    cellFaceLight: Color(0xFFF5ECDA),
    cellFaceShadow: Color(0xFFD8CCB0),
    cellEdge: Color(0xFFC4B49A),
    pieceBlack: Color(0xFF2C1810),
    pieceBlackHighlight: Color(0xFF5A3820),
    pieceBlackRim: Color(0xFF1A0A05),
    pieceWhite: Color(0xFFFAF5EE),
    pieceWhiteHighlight: Color(0xFFFFFFFF),
    pieceWhiteRim: Color(0xFFD4C9B5),
    // 合法步提示色 = 当前方棋子本色呼应（黑回合深棕黑点，白回合乳米白点）
    legalHintBlack: Color(0x992C1810), // ~60% 不透的 pieceBlack
    legalHintWhite: Color(0x99FAF5EE), // ~60% 不透的 pieceWhite
    lastMoveRing: Color(0x90C4A070),
    winAccent: Color(0xFFD4A853), // 暖金色：暖底上醒目
    panelBg: Color(0xFFE8DDCB),
    panelBorder: Color(0xFFD4C5A9),
    btnText: Color(0xFF5C4E3A),
    btnSub: Color(0xFF9C8E7A),
  );

  /// 暗夜主题 — 参考 surround_game cool 冷色（深靛蓝底）
  static const ReversiThemeData dark = ReversiThemeData(
    boardSurface: Color(0xFF1E1E2E),
    cellBase: Color(0xFF2A2A3E),
    cellFaceLight: Color(0xFF3A3A50),
    cellFaceShadow: Color(0xFF1A1A28),
    cellEdge: Color(0xFF252535),
    pieceBlack: Color(0xFF1A1A1A),
    pieceBlackHighlight: Color(0xFF4A4A4A),
    pieceBlackRim: Color(0xFF000000),
    pieceWhite: Color(0xFFF5F5F0),
    pieceWhiteHighlight: Color(0xFFFFFFFF),
    pieceWhiteRim: Color(0xFFAAAAAA),
    // 合法步提示色 = 当前方棋子本色呼应（黑回合深棕黑点，白回合乳米白点）
    legalHintBlack: Color(0x991A1A1A), // ~60% 不透的 pieceBlack
    legalHintWhite: Color(0x99F5F5F0), // ~60% 不透的 pieceWhite
    lastMoveRing: Color(0x80FFD54F),
    winAccent: Color(0xFFFFD54F), // 金黄色：暗底上醒目
    panelBg: Color(0xFF2A2A3E),
    panelBorder: Color(0xFF3A3A50),
    btnText: Color(0xFFE8E0F0),
    btnSub: Color(0xFF9090B0),
  );
}

/// Flutter ThemeExtension 包装
@immutable
class ReversiTheme extends ThemeExtension<ReversiTheme> {
  final ReversiThemeData data;
  const ReversiTheme({required this.data});

  static const ReversiTheme classic = ReversiTheme(data: ReversiThemeData.classic);
  static const ReversiTheme dark = ReversiTheme(data: ReversiThemeData.dark);

  static ReversiThemeData of(BuildContext context) {
    final ext = Theme.of(context).extension<ReversiTheme>();
    return ext?.data ?? ReversiThemeData.classic;
  }

  @override
  ReversiTheme copyWith({ReversiThemeData? data}) =>
      ReversiTheme(data: data ?? this.data);

  @override
  ReversiTheme lerp(ThemeExtension<ReversiTheme>? other, double t) {
    // 单主题暂不支持插值，直接返回 this
    return this;
  }
}
