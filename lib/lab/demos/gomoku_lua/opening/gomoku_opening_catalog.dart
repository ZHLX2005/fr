import '../engine.dart' show GomokuMove;
import 'gomoku_opening_models.dart';

const _huaYue = GomokuOpeningCase(
  id: 'hua-yue',
  title: '花月',
  tagline: '直指强攻：先学制造双线压力。',
  moves: [
    GomokuMove(x: 7, y: 7, isBlack: true),
    GomokuMove(x: 8, y: 7, isBlack: false),
    GomokuMove(x: 7, y: 6, isBlack: true),
    GomokuMove(x: 6, y: 6, isBlack: false),
    GomokuMove(x: 6, y: 7, isBlack: true),
    GomokuMove(x: 9, y: 8, isBlack: false),
    GomokuMove(x: 8, y: 6, isBlack: true),
    GomokuMove(x: 8, y: 8, isBlack: false),
  ],
  stepNotes: [
    '黑1 天元，建立中心控制。',
    '白2 斜向应手。',
    '黑3 直指，形成花月骨架。',
    '白4 先挡外侧。',
    '黑5 继续压迫，准备扩展两翼。',
    '白6 选择常见防守。',
    '黑7 形成三线联动，观察四三机会。',
    '白8 示例应手；继续练习四三杀识别。',
  ],
);

const _puYue = GomokuOpeningCase(
  id: 'pu-yue',
  title: '浦月',
  tagline: '直指变化：重点观察黑方的双向延展。',
  moves: [
    GomokuMove(x: 7, y: 7, isBlack: true),
    GomokuMove(x: 8, y: 7, isBlack: false),
    GomokuMove(x: 7, y: 8, isBlack: true),
    GomokuMove(x: 6, y: 8, isBlack: false),
    GomokuMove(x: 6, y: 7, isBlack: true),
    GomokuMove(x: 9, y: 6, isBlack: false),
    GomokuMove(x: 8, y: 8, isBlack: true),
    GomokuMove(x: 8, y: 6, isBlack: false),
  ],
  stepNotes: [
    '黑1 天元。',
    '白2 斜向应手。',
    '黑3 直指，进入浦月骨架。',
    '白4 压制一侧。',
    '黑5 拉开第二个攻击方向。',
    '白6 示例防守。',
    '黑7 继续制造双线威胁。',
    '白8 示例应手；检查是否出现四三机会。',
  ],
);

const _fourThree = GomokuOpeningCase(
  id: 'four-three',
  title: '四三杀训练',
  tagline: '训练目标：一步同时形成活四与活三。',
  moves: [
    GomokuMove(x: 7, y: 7, isBlack: true),
    GomokuMove(x: 0, y: 0, isBlack: false),
    GomokuMove(x: 6, y: 7, isBlack: true),
    GomokuMove(x: 1, y: 0, isBlack: false),
    GomokuMove(x: 8, y: 7, isBlack: true),
    GomokuMove(x: 2, y: 0, isBlack: false),
    GomokuMove(x: 7, y: 6, isBlack: true),
  ],
  stepNotes: [
    '黑1 中心落子。',
    '白方在边角练习性落子。',
    '黑2 连成横向二。',
    '白方继续无关落子。',
    '黑3 横向三。',
    '白方继续无关落子。',
    '黑4 形成训练局面：下一步寻找同时打开两条活路的四三杀。',
  ],
);

const gomokuOpeningCases = <GomokuOpeningCase>[_huaYue, _puYue, _fourThree];
