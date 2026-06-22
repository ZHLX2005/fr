# BFS 寻路与多路径分析

## 单源最短路径（BFS）

### 核心实现

`GameAi.swift:226-266` 实现了标准的 BFS：

```swift
// 来源: GameAi.swift:226-266
private class func pathForPlayer(player: Node, end: (Int)->Bool) -> [Int] {
    var logs = [player]        // 已访问节点
    var queue = [player]       // BFS 队列
    var finish: Node?

    while !queue.isEmpty {
        let path = queue.removeFirst()
        if end(path.data) {
            finish = path
            break
        } else {
            let near = GameModel.shared.gameNears[path.data]
            for n in near {
                if !logs.contains({ $0.data == n }) {
                    logs.append(Node(data: n, parent: path.data))
                    queue.append(Node(data: n, parent: path.data))
                }
            }
        }
    }
    // 回溯路径
    if let finish = finish {
        var node = finish
        var path = [node.data]
        while node.parent != -1 {
            if let log = logs.indexOf({ $0.data == node.parent }) {
                node = logs[log]
                path.insert(node.data, atIndex: 0)
            }
        }
        return path
    }
    return []
}
```

特点：
- 用 `Node` 结构体记录每个节点的父节点，用于回溯路径
- `end` 闭包判断是否到达终点（`topEnd`: id > 71，`downEnd`: id < 9）
- **不需要计算边权**——棋盘格移动每步权重相同，BFS 天然保证最短

## 全路径（多分支）分析

### 递归分支算法

`GameAi.swift:271-360` 实现了递归的全路径探索：

```swift
// 来源: GameAi.swift:271-286
private class func allPathForPlayer(var logs: [Node], var scanQueue: [Node], end: (Int)->Bool ) -> [[Int]]? {
    while !scanQueue.isEmpty {
        // 检查队列是否包含终点
        for queueNode in scanQueue {
            if end(queueNode.data) {
                // 回溯输出路径
                ...
                return [path]
            }
        }
```

### 分支生成逻辑

`GameAi.swift:292-314` 将扩展节点按邻接关系分组：

```swift
// 来源: GameAi.swift:292-314
for scanNode in scanQueue {
    var nodeScopes = [Node]()
    let nodeNears = GameModel.shared.gameNears[scanNode.data]
    for scope in nodeNears {
        if !logs.contains({ $0.data == scope }) {
            nodeScopes.append(Node(data: scope, parent: scanNode.data))
        }
    }
    if nodeScopes.count == 2 {
        let absValue = abs(nodeScopes[0].data - nodeScopes[1].data)
        if absValue == 18 || absValue == 2 {
            // 两个扩展点是相邻的（属于同一分支）→ 分成两组
            union(&nodeSets, newSet: [nodeScopes[0]])
            union(&nodeSets, newSet: [nodeScopes[1]])
        } else {
            // 不相邻 → 合并为一组
            union(&nodeSets, newSet: Set(nodeScopes))
        }
    } else if nodeScopes.count > 0 {
        union(&nodeSets, newSet: Set(nodeScopes))
    }
}
```

当某层的扩展节点**不相邻**时（不连续），就会产生分支，然后对每个分支递归调用自己，形成多路径树。

### Union 操作

`GameAi.swift:416-442`：

```swift
// 来源: GameAi.swift:416-442
private class func union(inout allSets: [Set<Node>], newSet: Set<Node>) {
    // 如果 newSet 与现有任一集合重叠，则合并
    for (i = 0; i < allSets.count; i++) {
        if !allSets[i].isDisjointWith(newSet) {
            allSets[i] = allSets[i].union(newSet)
            // 合并后检查是否与其他集合相连
            ...
            return
        }
    }
    allSets.append(newSet)  // 完全孤立的新集合
}
```

## AI 五层策略

`GameAi.swift:27-54` 的主入口 `Ai()`：

```swift
// 来源: GameAi.swift:27-54
class func Ai() -> DataModel {
    if GameModel.shared.gameStack.count < 8 { return opening() }
    if GameModel.shared.iWallIsEmpty() { return moveAi() }
    if let wall = longPathForPlayer() { return wall }
    if let wall = AiCount() { return wall }
    if let wall = strongSelfWall() { return wall }
    return moveAi()
}
```

优先级从高到低：

### Tier 1：开局（opening）

`GameAi.swift:365-401`，前 7 步使用随机策略：
- 70% 概率移动棋子（沿 BFS 最短路径走一步）
- 30% 概率随机放置墙壁（需通过合法性校验）
- 墙壁放置位置需要：不阻挡自己、给对方增加变数

### Tier 2：切断自己长路径（longPathForPlayer）

`GameAi.swift:152-185`，当玩家有**两条路径**且长度差 > 3 步时：
- 找到最长路径中的墙壁安装位置
- 如果切断该位置后只剩下最短路径 → 放置墙壁（消除远路）

### Tier 3：挡板策略（AiCount）

`GameAi.swift:102-135`，在对手最短路径上寻找最优堵截位置：
- 遍历对手路径上的每一对相邻格子
- 模拟放置墙壁后计算对手新路径长度
- 选取使对手路径**最长化**的位置

```swift
// 来源: GameAi.swift:114-124
for (var i = 0; i < rival.count-1; i++) {
    if let wall = wallData([rival[i], rival[i+1]]) {
        game.removeNearLink(wall)
        let rivalTest = pathForPlayer(false).count
        if rivalTest > maxPath {
            if player.count >= pathForPlayer(true).count {
                maxPath = rivalTest
                bestWall = wall
            }
        }
        game.removeGameWalls(wall)
        game.addNearLink(wall)
    }
}
```

### Tier 4：加强自身防御（strongSelfWall）

`GameAi.swift:67-99`，在自己路径上寻找墙壁位置：
- 找到会显著延长自己路径的墙壁位置
- 然后在旁边寻找一个能补位但不影响路径长度的"守卫"位置

### Tier 5：移动（moveAi）

`GameAi.swift:139-149`，沿 BFS 最短路径走一步：

```swift
// 来源: GameAi.swift:139-149
private class func moveAi() -> DataModel {
    let player = pathForPlayer(true)
    let scope = GameModel.shared.scopeForPlayer(...)
    for (i = player.count-1; i > 0; i--) {
        if scope.contains(player[i]) { break }
    }
    return DataModel.idConvertToPlayer(player[i], player: true)
}
```

从终点方向逆向查找可移动的格子，确保朝目标前进。

## 墙壁创建检测

`GameAi.swift:188-221` 的 `wallData` 方法：

```swift
// 来源: GameAi.swift:188-221
private class func wallData(var ids: [Int]) -> DataModel? {
    ids.sortInPlace()
    let x = ids[0] % 9
    let y = ids[0] / 9
    let h = (ids[1] - ids[0]) == 9

    var id = (x * 2 + 1) + (y * 2 + 1) * 17
    let offset = h ? 1 : 17

    // 尝试主位置
    if x != 8 && y != 8 {
        if !GameModel.shared.gameWalls[id] {
            if !GameModel.shared.gameWalls[id + offset] {
                ...
                return DataModel(x: x, y: y, h: h)
            }
        }
    }
    // 失败则尝试副位置（偏移一格）
    if (h && x > 0) || (!h && y > 0) {
        id -= (h ? 2 : 34)
        ...
        return DataModel(x: h ? x-1 : x, y: h ? y : y-1, h: h)
    }
    return nil
}
```

给定两个相邻格子编号，函数判断能否在它们之间放置墙壁，并返回墙壁的 DataModel。支持主/副两个位置的尝试。

## 算法复杂度

| 算法 | 时间复杂度 | 调用场景 |
|------|-----------|---------|
| BFS 最短路径 | O(V+E)，V≤81, E≤~280 | 每次 `pathForPlayer()` |
| 全路径分析 | 指数级（分支数） | 墙壁合法性校验、Tier 2 |
| Tier 3 AiCount | O(n×BFS) | 每一步最多调用 |
| `iWallIsAllow` | O(n×BFS) | 墙壁放置前调用 |
