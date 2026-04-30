# 火焰图阅读指南

## 什么是火焰图

火焰图(Flame Graph)是由 Linux 性能优化大师 Brendan Gregg 发明的性能分析工具。它以全局视野看待时间分布，从底部往顶部列出所有可能导致性能瓶颈的调用栈。

## 核心特征

| 维度 | 含义 |
|------|------|
| **纵轴 (Y轴)** | 函数调用栈深度，从下到上是调用关系，最顶层是正在占用CPU的函数 |
| **横轴 (X轴)** | CPU占用时间/抽样次数，宽度越宽说明执行时间越长 |

## 关键解读

1. **宽火焰 = 瓶颈**：X轴越宽的"火苗"越是性能问题点
2. **高火焰 = 深调用**：Y轴越高表示调用栈越深
3. **平顶山**：特别要注意类似平顶山的宽阔火焰，通常是CPU热点
4. **颜色无意义**：火焰图颜色仅作视觉区分

## 常见火焰图类型

- **On-CPU**：分析CPU占用时间
- **Off-CPU**：分析阻塞/等待时间
- **Memory**：分析内存分配
- **Hot/Cold**：分析CPU繁忙程度
- **Differential**：对比两个采样差异

## 生成工具

```bash
# 安装 FlameGraph
git clone https://github.com/brendangregg/FlameGraph.git

# 采集数据
perf record -F 99 -p <PID> -g -- sleep 30

# 生成火焰图
perf script | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl > out.svg
```

## 互动功能

- **鼠标悬浮**：显示函数名、抽样次数、百分比
- **点击放大**：可聚焦特定调用栈分析
- **搜索**：可以在SVG中搜索特定函数

## 采样原理

1. perf 以固定频率(默认99Hz)采样CPU正在执行的函数
2. 记录函数调用栈信息
3. 相同调用栈合并统计次数
4. 按调用栈生成火焰图

## 参考链接

- [FlameGraph GitHub](https://github.com/brendangregg/FlameGraph)
- [腾讯云-火焰图原理](https://cloud.tencent.com/developer/article/2348066)
- [SegmentFault-火焰图理论](https://segmentfault.com/a/1190000045672110)
