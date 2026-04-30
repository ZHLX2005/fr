---
name: mmx-research-gitclone
description: |
  使用mmx进行深度搜索并git clone开源项目到.claude/repo目录。
  当用户想要搜索技术资料、调研开源项目、查找最佳实践时触发。
  例如："搜索Flutter liquid glass实现"、"搜索React组件库并clone"、"调研某个技术的开源方案"。
  优先使用SSH (git@)进行克隆，限制最多clone 2个最有价值的项目。
---

# mmx-research-gitclone 工作流程

## 工作流程

### 1. 深度搜索 (使用mmx)

执行3-5次并行搜索，覆盖不同角度：

```bash
# 主搜索 - 找github项目
mmx search query --q "<技术方向> github implementation 2025" --output json --quiet

# 技术细节搜索
mmx search query --q "<技术方向> fragment shader implementation code" --output json --quiet

# 包/库搜索
mmx search query --q "<技术方向> pub.dev package widget 2025" --output json --quiet

# 最佳实践搜索
mmx search query --q "<技术方向> best practice example tutorial" --output json --quiet
```

### 2. 分析搜索结果

从搜索结果中识别最有价值的项目：

- GitHub stars数量高
- 最近更新 (2024-2025)
- 与需求最匹配
- 有实际代码实现

### 3. Git Clone 克隆

**优先使用SSH**，创建`.claude/repo`目录并克隆：

```bash
# 检查目录是否存在
mkdir -p .claude/repo

# 使用SSH克隆 (更快)
git clone --depth 1 git@github.com:<owner>/<repo>.git .claude/repo/<repo-name>

# 如果SSH不可用，回退到HTTPS
git clone --depth 1 https://github.com/<owner>/<repo>.git .claude/repo/<repo-name>
```

### 4. 验证克隆结果

**必须检查目录和文件是否存在**：

```bash
# 检查目录是否存在
if [ -d ".claude/repo/<repo-name>" ]; then
    echo "目录存在: .claude/repo/<repo-name>"
else
    echo "错误: 目录不存在"
    exit 1
fi

# 检查关键文件是否存在
if [ -f ".claude/repo/<repo-name>/README.md" ] || [ -f ".claude/repo/<repo-name>/build.gradle" ] || [ -f ".claude/repo/<repo-name>/pubspec.yaml" ]; then
    echo "关键文件存在"
else
    echo "警告: 可能克隆不完整，缺少关键文件"
fi

# 列出目录内容
ls -la .claude/repo/<repo-name>/
```

### 5. 限制

- **最多克隆2个**最有价值的项目
- 优先克隆与当前任务最相关的
- 使用 `--depth 1` 进行浅克隆减少体积

## 输出格式

完成后报告：

```
## 搜索结果总结

已克隆项目到 .claude/repo/ 目录：

1. [项目名](github链接) - stars数
   - 主要功能
   - 技术栈

2. [项目名](github链接) - stars数
   - 主要功能
   - 技术栈

项目位置: .claude/repo/<project-name>/
```

## 常见搜索示例

### Flutter相关
```bash
mmx search query --q "Flutter liquid glass iOS 26 implementation github 2025" --output json --quiet
mmx search query --q "flutter glassmorphism widget github pub.dev 2025" --output json --quiet
mmx search query --q "flutter ImageFilter.blur sigmaX sigmaY implementation" --output json --quiet
```

### React/Vue相关
```bash
mmx search query --q "React liquid glass component github implementation 2025" --output json --quiet
mmx search query --q "Vue glassmorphism UI component github" --output json --quiet
```

### Swift/iOS相关
```bash
mmx search query --q "SwiftUI liquid glass iOS 26 implementation" --output json --quiet
mmx search query --q "iOS glassmorphism swift package github" --output json --quiet
```

## 错误处理

- **SSH clone失败**：回退到HTTPS
- **目录已存在**：跳过，使用已有目录
- **clone被拒绝**：尝试另一个项目
