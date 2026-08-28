// Layer 1 — tokens barrel：re-export 颜色相关常量。
//
// 实际 hex 定义分散在子目录：
//   · raw/         中性骨架（pureWhite/nearBlack/9 档灰/shadow alpha）
//   · base/        通用规范（功能色 + 国际识别色）
//   · theme/       5 套主题调色板（zen/purple/ink/rose/lemon）
//   · board/       对弈棋盘 11 角色常量
//   · tetris/      俄罗斯方块 4 角色常量
//   · team/        团队卡 6 头像色常量
//   · torch/       灯具护眼色常量

export 'color/raw/raw.dart';
export 'color/base/base.dart';
export 'color/app_colors_extension.dart';
export 'color/theme/zen.dart';
export 'color/theme/purple.dart';
export 'color/theme/ink.dart';
export 'color/theme/rose.dart';
export 'color/theme/lemon.dart';
export 'color/board/board.dart';
export 'color/tetris/tetris.dart';
export 'color/team/team.dart';
export 'color/torch/torch.dart';