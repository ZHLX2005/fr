import '../../domain/models.dart';

/// DSL 解析结果
class DslParseResult {
  final List<CourseItem> courses;
  final List<String> errors;

  /// 可选的 config 段（`config: ...` 行解析出的配置；不存在为 null）
  final TimetableConfig? config;

  const DslParseResult({
    required this.courses,
    required this.errors,
    this.config,
  });
}

/// 解析 DSL 文本
///
/// DSL 格式:
/// ```
/// # 注释行跳过
/// # 可选 config 段（表达行数/列数/开始时间等配置，必须在课程行之前）:
/// config: days=7 slots=5 cycles=16 start=2026-08-15 mode=school left=1 duration=45
/// #   days    每周期天数(列数, 1-7)
/// #   slots   每天节数(行数, 1-6)
/// #   cycles  周期总数(1-32)
/// #   start   开始日期 YYYY-MM-DD
/// #   mode    school(周一对齐/7天固定) | general(通用)
/// #   left    左侧指示模式: 0=序号 | 1=时间段 | 2=自定义
/// #   duration 每节时长分钟(时间段模式计算结束时间用)
///
/// # 格式: 课程名 @ 星期(1-7) 节次 [w周次] [位置] [教师]
/// # 周次可选，不写表示所有周期都显示
/// # 节次: 单节 "3" 或范围 "1-4"
///
/// 高等数学 @ 1 1-2 w1,3,5 教学楼A101 张老师
/// 大学英语 @ 1 3-4 w2,4
/// 体育 @ 2 1
/// 线性代数 @ 3 1-2 教学楼B101
/// ```
///
/// 周次 w1,3,5 表示在第1、3、5周显示（对应 cycleIndex 0, 2, 4）
DslParseResult parseDsl(String input, {int defaultSlotCount = 6}) {
  final courses = <CourseItem>[];
  final errors = <String>[];
  TimetableConfig? config;
  final now = DateTime.now().millisecondsSinceEpoch;
  // config 段的 slots 优先约束后续课程行的节次范围
  var slotCount = defaultSlotCount;

  for (final rawLine in input.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    if (line.startsWith('config:')) {
      final cfg = _parseConfigLine(line, now);
      if (cfg != null) {
        config = cfg;
        slotCount = cfg.slotsPerDay;
      } else {
        errors.add('config 段格式无效: $line');
      }
      continue;
    }

    final result = _parseLine(line, slotCount, now, courses.length);
    if (result.error != null) {
      errors.add(result.error!);
    } else if (result.multipleItems != null) {
      courses.addAll(result.multipleItems!);
    } else if (result.course != null) {
      courses.add(result.course!);
    }
  }

  return DslParseResult(courses: courses, errors: errors, config: config);
}

/// 解析 config 段：`config: days=7 slots=5 cycles=16 start=2026-08-15 mode=school left=1 duration=45`
///
/// 只取合法字段，非法值回退默认；解析失败（非 k=v 结构）返回 null。
TimetableConfig? _parseConfigLine(String line, int now) {
  final body = line.substring('config:'.length).trim();
  if (body.isEmpty) return null;

  final kv = <String, String>{};
  for (final pair in body.split(RegExp(r'\s+'))) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    if (eq == -1) return null;
    kv[pair.substring(0, eq)] = pair.substring(eq + 1);
  }

  final defaults = TimetableConfig.defaultConfig;
  return TimetableConfig(
    startDateIso: kv['start'] ?? defaults.startDateIso,
    cycleCount:
        (int.tryParse(kv['cycles'] ?? '') ?? defaults.cycleCount).clamp(
          TimetableConfig.minCycles,
          TimetableConfig.maxCycles,
        ),
    daysPerCycle:
        (int.tryParse(kv['days'] ?? '') ?? defaults.daysPerCycle).clamp(
          TimetableConfig.minDaysPerCycle,
          TimetableConfig.maxDaysPerCycle,
        ),
    slotsPerDay:
        (int.tryParse(kv['slots'] ?? '') ?? defaults.slotsPerDay).clamp(
          TimetableConfig.minSlotsPerDay,
          TimetableConfig.maxSlotsPerDay,
        ),
    isSchoolMode: kv['mode'] == 'school',
    leftLabelMode: (int.tryParse(kv['left'] ?? '') ?? 0).clamp(0, 2),
    slotDurationMin: int.tryParse(kv['duration'] ?? '') ?? 45,
    updatedAt: now,
  );
}

_DslLineResult _parseLine(String line, int defaultSlotCount, int now, int index) {
  // 检查格式: 必须有 @
  if (!line.contains('@')) {
    return _DslLineResult(error: '格式错误，缺少 @ 分隔符: $line');
  }

  final parts = line.split('@');
  if (parts.length != 2) {
    return _DslLineResult(error: '格式错误，只能有一个 @: $line');
  }

  final titlePart = parts[0].trim();
  final infoPart = parts[1].trim();

  if (titlePart.isEmpty) {
    return _DslLineResult(error: '课程名称不能为空: $line');
  }

  final title = titlePart;
  final infoParts = infoPart.split(RegExp(r'\s+'));

  if (infoParts.length < 2) {
    return _DslLineResult(error: '排课信息不完整，需指定星期和节次: $line');
  }

  // 第1个: 星期 (1-7)
  final dayStr = infoParts[0];
  final dayOfCycle = int.tryParse(dayStr);
  if (dayOfCycle == null || dayOfCycle < 1 || dayOfCycle > 7) {
    return _DslLineResult(error: '星期无效，应为 1-7: $line');
  }
  final dayIndex = dayOfCycle - 1; // 转为 0-based

  // 第2个: 节次 (单节 "3" 或范围 "1-4")
  final slotStr = infoParts[1];
  List<int>? slotIndices = _parseSlotRange(slotStr, defaultSlotCount);
  if (slotIndices == null) {
    return _DslLineResult(error: '节次无效，应为 "3" 或 "1-4" 格式: $line');
  }

  // 可选: 周次 w1,3,5
  List<int>? visibleInCycles;
  String? location;
  String? teacher;

  int i = 2;
  while (i < infoParts.length) {
    final part = infoParts[i];
    if (part.startsWith('w')) {
      // 周次列表
      visibleInCycles = _parseCycleList(part);
      if (visibleInCycles == null) {
        return _DslLineResult(error: '周次格式无效，应为 w1,3,5: $line');
      }
    } else if (location == null) {
      location = part;
    } else {
      teacher ??= part;
    }
    i++;
  }

  // 为每个节次创建一个 CourseItem
  final items = <CourseItem>[];
  for (final slot in slotIndices) {
    items.add(CourseItem(
      id: '${now}_${index}_${dayIndex}_$slot',
      dayOfCycle: dayIndex,
      slotIndex: slot,
      title: title,
      location: location,
      teacher: teacher,
      colorSeed: now + index,
      version: 1,
      visibleInCycles: visibleInCycles,
      createdAt: now,
      updatedAt: now,
    ));
  }

  return _DslLineResult(course: items.length == 1 ? items.first : null, multipleItems: items.length > 1 ? items : null);
}

class _DslLineResult {
  final String? error;
  final CourseItem? course;
  final List<CourseItem>? multipleItems;

  const _DslLineResult({this.error, this.course, this.multipleItems});
}

/// 解析节次范围 "3" -> [2] 或 "1-4" -> [0,1,2,3]
List<int>? _parseSlotRange(String slotStr, int maxSlot) {
  if (slotStr.contains('-')) {
    final parts = slotStr.split('-');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null || end == null || start < 1 || end > maxSlot || start > end) {
      return null;
    }
    return List.generate(end - start + 1, (i) => start - 1 + i);
  } else {
    final slot = int.tryParse(slotStr);
    if (slot == null || slot < 1 || slot > maxSlot) return null;
    return [slot - 1];
  }
}

/// 解析周次列表 "w1,3,5" -> [0, 2, 4] (cycleIndex 0-based)
List<int>? _parseCycleList(String part) {
  final numStr = part.substring(1); // 去掉 'w' 前缀
  final indices = <int>[];
  for (final s in numStr.split(',')) {
    final n = int.tryParse(s.trim());
    if (n == null || n < 1) return null;
    indices.add(n - 1); // 转为 0-based
  }
  return indices.isEmpty ? null : indices;
}
