// lib/core/jungle_chess/constants/jungle_constants.dart
import 'package:flutter/material.dart';
import '../models/piece.dart';

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
const Color kBluePieceTint = Color(0xFF3B82F6); // 蓝方描边 / 高亮
const Color kRedPieceTint = Color(0xFFEF4444); // 红方描边 / 高亮
const double kPieceBorderWidth = 2.5;
const double kPieceIconRatio = 0.82; // PNG 占圆盘的比例（PNG 平均高/宽≈1.09，比 SVG 略胖）

// 和棋回合上限
const int kMaxRounds = 150;

// 坐标工具
int coordIndex(int row, int col) => row * 7 + col;
bool isRiver(int index) => kRiverSet.contains(index);
bool isBlueDen(int index) => index == kBlueDen;
bool isRedDen(int index) => index == kRedDen;
bool isBlueTrap(int index) => kBlueTraps.contains(index);
bool isRedTrap(int index) => kRedTraps.contains(index);

// 动物代码 → assets/animals/ 下的 PNG 文件名
// 注意：鼠对应 mouse.png（命名沿用旧版习惯，没改成 rat.png）
const Map<Animal, String> kAnimalFile = {
  Animal.rat: 'mouse.png',
  Animal.cat: 'cat.png',
  Animal.dog: 'dog.png',
  Animal.wolf: 'wolf.png',
  Animal.leopard: 'leopard.png',
  Animal.tiger: 'tiger.png',
  Animal.lion: 'lion.png',
  Animal.elephant: 'elephant.png',
};
