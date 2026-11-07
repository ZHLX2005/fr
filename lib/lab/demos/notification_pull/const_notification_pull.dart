// 网易云音乐通知卡 —— 模块常量（几何 / 文本样式 / 通知数据）。
//
// 所有数值与 docs/prototypes/notification-pull-expand.html 一一对应，
// 改这里 = 改原型，改完请同步比对 HTML。
//
// 主题豁免：本模块整体是「网易云通知卡」的视觉复刻，
// 卡片渐变底、网易云红图标、时间/正文灰阶均为该设计的固定色，
// 不随项目主题切换 —— 与 tetris / team 头像同理，属于「复刻保真」豁免。

import 'package:flutter/material.dart';

import '../../../design_tokens/typography.dart';

// ── 固定几何（与 HTML 一致） ─────────────────────────────────
const double kPadT = 14;
const double kPadB = 14;
const double kPadL = 16;
const double kPadR = 16;

/// 390 - 左右各 14
const double kCardW = 362;

/// 内容宽度 = 卡片宽 - 左右内边距 = 330
const double kContentW = kCardW - kPadL - kPadR;

/// 展开态行距
const double kGap = 14;

/// 折叠态行距
const double kGap0 = 3;

/// 折叠态单行高度
const double kCompactRow = 20;

/// 标题行高
const double kTitleLine = 20;

/// 拖动死区（4px 内不响应）
const double kDead = 4;

/// 字体回退链（Flutter 只认单个 fontFamily，OS 回退走 fontFamilyFallback）
const List<String> kFontFallback = <String>[
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans SC',
];

// ── 文本样式 ────────────────────────────────────────────────
//
// ⚠️ letterSpacing / fontFamily 必须**显式写死**，不能留 null。
//
// 原因：本模块用 TextPainter 实测时间文字宽度来决定时间列宽
// （见 notification_pull_card.dart 的 _measure / _textWidth）。
// 如果样式不写 letterSpacing，实测时是 0，渲染时却会从外层
// DefaultTextStyle 继承到非 0 值（Flutter M3 bodyMedium 是 0.25），
// 实测比渲染窄 1.25px → 文字换行 → maxLines:1 把最后一个字裁掉
// （「13:41」变「13:4」、「昨天」变「昨」）。
//
// 这里与 HTML 原型保持一致：.r-title / .r-time / .r-inline / .r-body
// 均未声明 letter-spacing（= normal = 0），.name 声明 .2px。
// 因此除 kNameStyle 外，其余一律显式 letterSpacing: 0。

const TextStyle kNameStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.6923076923076923, // 22 / 13
  letterSpacing: .2,
  color: Color(0xA8FFFFFF),
  fontFamily: AppFontFamily.sans,
  fontFamilyFallback: kFontFallback,
);

const TextStyle kTitleStyle = TextStyle(
  fontSize: 13.5,
  fontWeight: FontWeight.w500,
  height: 1.4814814814814816, // 20 / 13.5
  letterSpacing: 0,
  color: Color(0xEDFFFFFF),
  fontFamily: AppFontFamily.sans,
  fontFamilyFallback: kFontFallback,
);

const TextStyle kInlineStyle = TextStyle(
  fontSize: 13,
  height: 1.5384615384615385, // 20 / 13
  letterSpacing: 0,
  color: Color(0xB3F2F0F8),
  fontFamily: AppFontFamily.sans,
  fontFamilyFallback: kFontFallback,
);

const TextStyle kBodyStyle = TextStyle(
  fontSize: 13,
  height: 1.4615384615384617, // 19 / 13
  letterSpacing: 0,
  color: Color(0xB3F2F0F8),
  fontFamily: AppFontFamily.sans,
  fontFamilyFallback: kFontFallback,
);

const TextStyle kTimeStyle = TextStyle(
  fontSize: 11.5,
  height: 1.7391304347826086, // 20 / 11.5
  letterSpacing: 0,
  color: Color(0x70F2F0F8),
  fontFamily: AppFontFamily.sans,
  fontFamilyFallback: kFontFallback,
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

const TextStyle kPlusStyle = TextStyle(
  fontSize: 12,
  height: 1.6666666666666667, // 20 / 12
  letterSpacing: 0,
  color: Color(0x70F2F0F8),
  fontFamily: AppFontFamily.sans,
  fontFamilyFallback: kFontFallback,
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

/// 应用名（头部）
const String kAppName = '网易云音乐';

/// 卡片背景渐变（主题豁免：复刻网易云通知卡的固定底色）
const List<Color> kCardGradient = <Color>[
  Color(0xA8423D4C),
  Color(0xBD2D2A36),
  Color(0xC924222D),
];

/// 网易云图标红（主题豁免：品牌色）
const Color kMusicIconRed = Color(0xFFEF2A2A);
const Color kMusicIconRedDark = Color(0xFFC21018);

/// 箭头 / 提示色（主题豁免）
const Color kChevronColor = Color(0x8CFFFFFF);

/// 舞台预设：'three' / 'four' / 'five' / 'h180'
const List<String> kStagePresets = <String>['three', 'four', 'five'];

/// 舞台预设的中文标签（demo 切换器用）
const Map<String, String> kStageLabels = <String, String>{
  'three': '三条',
  'four': '四条',
  'five': '五条',
};

/// 一条通知。
class NotificationNotice {
  const NotificationNotice({
    required this.title,
    required this.time,
    required this.summary,
    required this.body,
    required this.bodyLines,
    this.lazyTime = false,
    this.plus = false,
    this.timeRight = 0,
  });

  final String title;
  final String time;

  /// 折叠态与标题同行的紧凑摘要
  final String summary;

  /// 展开态正文
  final String body;

  /// 正文行数（与 HTML 实测结果一致 2/1/2/1/1）。
  ///
  /// 不依赖首帧字体是否就绪 —— 表情字体异步加载会让行数测量漂移，
  /// 进而把 H2/H3/H4 算大，展开态底边对不上。
  final int bodyLines;

  /// 折叠态不显示时间，展开态才浮出来
  final bool lazyTime;

  /// 折叠态右下角显示 +N
  final bool plus;

  /// 时间右侧留白：让开右上角箭头（首行）/ 让开 +N（第三行）
  final double timeRight;
}

/// 通知数据（与 HTML 完全一致）
const List<NotificationNotice> kNotices = <NotificationNotice>[
  NotificationNotice(
    title: '回忆坐标',
    time: '13:41',
    summary: '3 年前的今天，你与《以后不会了》相遇，点击查看回忆坐标>',
    body: '3 年前的今天，你与《以后不会了》相遇，点击查看回忆坐标>',
    bodyLines: 2,
    timeRight: 21,
  ),
  NotificationNotice(
    title: '黄霄雲',
    time: '12:20',
    summary: '快来听《留不住的夏天》',
    body: '快来听《留不住的夏天》',
    bodyLines: 1,
    lazyTime: true,
  ),
  NotificationNotice(
    title: '🥺 真挚的感情最珍贵',
    time: '昨天',
    summary: '综艺「后会友期」主题曲上线🇨🇳在这个瞬息万变的时代…',
    body:
        '综艺「后会友期」主题曲上线🇨🇳在这个瞬息万变的时代，那些曾经无话不谈的朋友，依然让人牵挂>>',
    bodyLines: 2,
    lazyTime: true,
    plus: true,
    timeRight: 21,
  ),
  NotificationNotice(
    title: '@假日的栈桥 速听→',
    time: '昨天',
    summary: '王赫野热歌榜TOP1已送达！',
    body: '王赫野热歌榜TOP1已送达！',
    bodyLines: 1,
    lazyTime: true,
  ),
  NotificationNotice(
    title: '陈卓璇 [可能喜欢]',
    time: '2026/11/4',
    summary: '快来听《杨花落尽子规啼》',
    body: '快来听《杨花落尽子规啼》',
    bodyLines: 1,
    lazyTime: true,
  ),
];
