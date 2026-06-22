// lib/core/jungle_chess/constants/jungle_constants.dart
import 'package:flutter/material.dart';

const int kBoardRows = 9;
const int kBoardCols = 7;

// 兽穴坐标 (1D index = row*7+col)
const int kBlueDen = 59; // (8,3) 蓝方在底部 → 蓝穴在底部中央
const int kRedDen = 3;   // (0,3) 红方在顶部 → 红穴在顶部中央

// 陷阱坐标
// 蓝方陷阱 = 围绕蓝穴 (8,3)=59：(8,2)=58, (8,4)=60, (7,3)=52
const List<int> kBlueTraps = [58, 60, 52];
// 红方陷阱 = 围绕红穴 (0,3)=3：(0,2)=2, (0,4)=4, (1,3)=10
const List<int> kRedTraps = [2, 4, 10];

// 河流坐标：左河 (3-5,1-2) + 右河 (3-5,4-5)
const List<int> kRiverCells = [
  22,23, 29,30, 36,37,  // 左河
  25,26, 32,33, 39,40,  // 右河
];

// 所有河流坐标 Set（快速查找）
final Set<int> kRiverSet = Set.from(kRiverCells);

// 棋盘视觉
const double kCellSize = 64.0;
const double kPieceRatio = 0.85;
const Color kBoardBg = Color(0xFFFAF7F0); // 暖米白（与白底主题协调）
const Color kRiverColor = Color(0xFFBFDBFE); // 浅蓝河
const Color kTrapColor = Color(0xFFE5E7EB); // 浅灰陷阱
const Color kDenColor = Color(0xFFFBBF24); // 金色兽穴（与边框呼应）

// 棋子圆盘 — 暖象牙底 + 玩家色描边
const Color kPieceDiskColor = Color(0xFFF5F0E1); // 棋子圆盘底色（象牙白）
const Color kPieceDiskBorder = Color(0xFF8B6F47); // 圆盘描边（木纹深棕）
const Color kBluePieceTint = Color(0xFF3B82F6); // 蓝方描边 / 高亮
const Color kRedPieceTint = Color(0xFFEF4444); // 红方描边 / 高亮
const double kPieceBorderWidth = 2.5;
const double kPieceIconRatio = 0.62; // SVG 占圆盘的比例（圆心居中）

// 和棋回合上限
const int kMaxRounds = 150;

// 坐标工具
int coordIndex(int row, int col) => row * 7 + col;
bool isRiver(int index) => kRiverSet.contains(index);
bool isBlueDen(int index) => index == kBlueDen;
bool isRedDen(int index) => index == kRedDen;
bool isBlueTrap(int index) => kBlueTraps.contains(index);
bool isRedTrap(int index) => kRedTraps.contains(index);

// 动物代码 → SVG 文件第二字符
const Map<int, String> kAnimalCode = {
  1: 'R', 2: 'C', 3: 'D', 4: 'W',
  5: 'H', 6: 'T', 7: 'L', 8: 'E',
};
