// lib/core/chess/endgame/chess_endgame_prompt.dart
//
// 残局 AI 生成提示词（常量）。
//
// 用途：残局列表页"AI 生成"入口展示此提示词，用户复制后粘贴给任意 AI
// （ChatGPT / Claude / 豆包…），AI 按此格式输出 JSON → 用户保存为
// .chessendgame.json 文件 → 残局列表页导入。
//
// 提示词与 lib/core/chess/endgame/chess_endgame.dart 的校验规则同源：
// format/version 必填、snapshots 非空、FEN 可解析 + 双方各恰一王。

/// AI 生成残局文件的提示词。
const String kChessEndgameGenPrompt = '''
你是国际象棋残局专家。请生成一个国际象棋残局文件，输出**纯 JSON**（不要 markdown 代码块、不要任何解释文字）。

## JSON 格式要求

{
  "format": "fr-chess-endgame",
  "version": 1,
  "id": "eg-<8位日期>-<6位随机hex>",
  "title": "残局标题（中文，简短）",
  "description": "残局说明（中文，含取胜思路提示）",
  "createdAt": "<ISO8601 时间，如 2026-08-31T12:00:00Z>",
  "source": "imported",
  "tags": ["标签1", "标签2"],
  "difficulty": 1到5的整数,
  "snapshots": [
    {
      "label": "局面名（中文，可空）",
      "fen": "<FEN 局面串>"
    }
  ]
}

## FEN 格式（国际象棋标准记法，6 个空格分隔字段）

- 第 1 字段：棋盘。8 行从第 8 横线到第 1 横线，`/` 分隔。大写=白方（K后Q车R象B马N兵P），小写=黑方；数字=连续空格数。
- 第 2 字段：轮走方。`w`=白，`b`=黑。
- 第 3 字段：易位权。`KQkq` 或 `-`。
- 第 4 字段：吃过路兵目标格（如 `e3`）或 `-`。
- 第 5 字段：半回合计数（无吃子/兵动的半回合数），填 0 即可。
- 第 6 字段：回合数，填 1 即可。

## 硬性校验（违反会被 App 拒绝）

1. 每个局面双方**必须恰好各有一个王**（一个 K 和一个 k）。
2. FEN 第 1 字段必须恰好 8 行、每行格数合计为 8。
3. snapshots 至少 1 个；同一残局可给多个快照（如"起点"和"关键局面"）。
4. 只输出一个 JSON 对象，不要输出数组、注释或多余文字。

## 示例 1（后单王杀王）

{
  "format": "fr-chess-endgame",
  "version": 1,
  "id": "eg-20260831-a1b2c3",
  "title": "后单王杀王",
  "description": "用后把黑王逼到边线后送将。注意防逼和。",
  "createdAt": "2026-08-31T12:00:00Z",
  "source": "imported",
  "tags": ["杀王", "后"],
  "difficulty": 1,
  "snapshots": [
    { "label": "起点", "fen": "8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1" }
  ]
}

## 示例 2（黑先残局 —— 轮黑走）

{
  "format": "fr-chess-endgame",
  "version": 1,
  "id": "eg-20260831-d4e5f6",
  "title": "黑先兵残局",
  "description": "轮黑走的局面，适合练习防守。",
  "createdAt": "2026-08-31T12:00:00Z",
  "source": "imported",
  "tags": ["兵", "黑先"],
  "difficulty": 2,
  "snapshots": [
    { "label": "轮黑走", "fen": "8/8/8/4k3/8/8/4P3/4K3 b - - 0 1" }
  ]
}

## 出题要求

请生成 2 个不同主题的残局（如一步杀、王兵残局、战术组合），难度有梯度，FEN 必须是真实合法的国际象棋局面。每个残局输出一个独立的 JSON 对象（分开两段输出，方便分别保存）。
''';
