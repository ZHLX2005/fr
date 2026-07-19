# Flutter Hive TypeAdapter Part文件CI构建失败问题

## 问题概述

**场景**: Flutter项目中使用`part`文件机制分离Hive的`TypeAdapter`生成代码,在本地开发正常,但CI构建(Android APK)反复失败。

**错误信息**:
```
body_record.g.dart: No such file or directory
```

**影响**: 连续3次CI构建失败,无法通过流水线发布APK。

---

## NOK Example (问题代码)

### 原始结构 — 使用part文件

**文件: `lib/core/body/models/body_record.dart`**
```dart
part 'body_record.g.dart';

@HiveType(typeId: 0)
class BodyRecord extends HiveObject {
  @HiveField(0)
  final String bodyPartId;
  // ...
}
```

**文件: `lib/core/body/models/body_record.g.dart`** (手动创建/预期由build_runner生成)
```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_record.dart';

class BodyRecordAdapter extends TypeAdapter<BodyRecord> {
  // ...
}
```

**问题**: CI环境中,`part 'body_record.g.dart'`声明存在,但构建系统无法正确解析该part文件,即使`git ls-files`确认文件已提交。

---

## OK Example (修复代码)

### 修复后结构 — 合并TypeAdapter到主文件

**文件: `lib/core/body/models/body_record.dart`** (最终正确版本)
```dart
import 'package:hive_flutter/hive_flutter.dart';

@HiveType(typeId: 0)
class BodyRecord extends HiveObject {
  @HiveField(0)
  final String bodyPartId;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final int? painLevel;

  @HiveField(3)
  final DateTime createdAt;

  BodyRecord({
    required this.bodyPartId,
    required this.content,
    this.painLevel,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class BodyRecordAdapter extends TypeAdapter<BodyRecord> {
  @override
  final int typeId = 0;

  @override
  BodyRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BodyRecord(
      bodyPartId: fields[0] as String,
      content: fields[1] as String,
      painLevel: fields[2] as int?,
      createdAt: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BodyRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.bodyPartId)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.painLevel)
      ..writeByte(3)
      ..write(obj.createdAt);
  }
}
```

**结果**: CI构建成功,12分30秒完成全部步骤。

---

## 修复思路和原理

### 根本原因分析

`part`文件在Dart中的机制是:
1. `part of`文件被认为是主文件的一部分,由主文件的构建系统管辖
2. 在Flutter/Gradle构建过程中,`build_runner`或代码生成步骤需要在正确的时间点解析`part`声明
3. CI环境的构建流水线(特别是Android APK构建)中,代码生成步骤(`flutter pub run build_runner build`)与Gradle的编译步骤存在时序或路径问题

**关键洞察**: 这个问题在本地开发环境不出现,只在CI环境出现,说明是**构建环境差异**而非代码本身错误。

### 修复策略

采用**简化架构**策略 — 消除不必要的代码生成依赖:

| 方案 | 思路 | 优点 | 缺点 |
|------|------|------|------|
| 方案A: 合并TypeAdapter | 将Adapter直接写入主文件 | 零生成依赖,CI友好 | 文件稍长 |
| 方案B: 手动维护.g.dart | 不依赖build_runner | 完全可控 | 维护成本高 |
| 方案C: 排查CI配置 | 修复build_runner在CI中的执行 | 保持干净代码 | 耗时,不稳定 |

**选择方案A** — 最直接有效,彻底消除part文件机制带来的CI不确定性。

### 原理总结

```
本地开发:  .dart文件 -> Dart VM -> 正常解析part -> 正常加载
CI构建:    .dart文件 -> Gradle编译 -> part路径解析失败 -> No such file or directory

消除part:  .dart文件 -> Gradle编译 -> 直接引用 -> 正常编译
```

---

## 更专业的解决方案思考(Brainstorm)

### 方案1: 官方的Hive Generator (build_runner)
**标准做法**: 使用`hive_generator`和`build_runner`自动生成Adapter代码。
```yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0
dev_dependencies:
  hive_generator: ^2.0.1
  build_runner: ^2.4.8
```
**何时适用**: 项目规模较大,多个Hive模型需要统一管理。需要在CI中确保`flutter pub run build_runner build`正确执行。

### 方案2: 手工实现TypeAdapter(当前采用)
**适用场景**: 模型数量较少(<10个),不想引入额外的代码生成依赖。

### 方案3: 使用Isar替代Hive
**Isar**: 另一个Flutter数据库,提供更好的类型安全和代码生成。
**转换成本**: 需要重写Repository层。

### 方案4: 在CI中增加代码生成验证步骤
在`build-apk.yml`中添加:
```yaml
- name: Verify generated files
  run: |
    if [ ! -f "lib/core/body/models/body_record.g.dart" ]; then
      echo "ERROR: Generated file missing"
      exit 1
    fi
```
**评价**: 治标不治本,不推荐。

---

## 经验教训

1. **part文件机制在CI中有不确定性** — 特别是在多步骤构建流水线中,part文件的解析依赖于构建系统正确配置
2. **简单即可靠** — 对于小型功能,手工实现比代码生成更稳定
3. **CI失败优先本地复现** — 本次问题本地无法复现,说明是环境差异,此时简化架构比排查环境更有效
4. **手动合并Adapter到主文件** — 是解决此类CI生成代码问题的有效手段

---

## 相关文件

- `lib/core/body/models/body_record.dart` — 修复后的文件
- `lib/core/body/models/body_record_repo.dart` — Hive Repository
- `.github/workflows/build-apk.yml` — CI配置文件
- Commit: `3404292` — fix(body): 合并BodyRecordAdapter到主文件,解决CI构建问题
