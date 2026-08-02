#!/usr/bin/env dart
// .tool/color_block_scan/scan.dart
//
// 批量扫描 lib/ 下"色块范式"残留代码（应改为 border-emphasis 边框强调式）。
// 命中规则见 styles-skill/references/border-emphasis-style.md 的"错误案例"段。
//
// 用法（在项目根）：
//   dart .tool/color_block_scan/scan.dart                    # 扫所有命中
//   dart .tool/color_block_scan/scan.dart --lib=lib/lab      # 限定子目录
//   dart .tool/color_block_scan/scan.dart --strict           # 命中即 exit 1（CI 用）
//   dart .tool/color_block_scan/scan.dart --ignore=X,Y     # 跳过命中（误报或已知特例）
//
// 设计要点：
// - 纯 Dart、无外部依赖（避免 tool-isolation 之外的污染）
// - 正则匹配而非 AST：快、足够准、易维护
// - 必须能区分"色块"（literal Colors.X）与"主题色"（colorScheme.X）——
//   后者是合法的（border-emphasis 三件套也用 theme primary）
// - 多行匹配：color 和 foregroundColor/Icon 分两行写也会命中（用 `[\s\S]` 通配）
// - 跳过注释行（// 或 /*）减少噪声

import 'dart:io';

const _root = 'lib';
final _excludeDirNames = {
  'generated',
  'l10n',
};
const _excludeFileSuffixes = {
  '.g.dart',
  '.freezed.dart',
  '.mocks.dart',
};

/// 一条命中
class Hit {
  Hit(this.file, this.line, this.reason);
  final String file;
  final int line;
  final String reason;
  @override
  String toString() => '${file}:${line}: ${reason}';
}

/// 命中规则。每条规则：一个或多个正则模式 + 解读。
class Rule {
  Rule(this.id, this.patterns, this.reason);
  final String id;
  final List<RegExp> patterns;
  final String reason;
}

/// 命中规则集合。
final List<Rule> _rules = [
  // 1. FilledButton/ElevatedButton 用饱和 Colors.X + white 前景
  Rule(
    'filled-button-with-white',
    [
      RegExp(
        r'(FilledButton|ElevatedButton)\b[\s\S]{0,400}?styleFrom\s*\(\s*backgroundColor\s*:\s*Colors\.\w+[\s\S]{0,200}?foregroundColor\s*:\s*Colors\.white',
        multiLine: true,
      ),
      // 单行变体（无 foregroundColor 但 backgroundColor 是非主题色）—— 更宽，仅作参考
      RegExp(
        r'(FilledButton|ElevatedButton)\b[\s\S]{0,400}?styleFrom\s*\(\s*backgroundColor\s*:\s*Colors\.(?!transparent)\w+',
        multiLine: true,
      ),
    ],
    'FilledButton/ElevatedButton 用纯色填充 + 白前景 → 改 OutlinedButton + 撞色编码',
  ),

  // 2. Container/DecoratedBox/CircleAvatar 等"色块 icon 容器"：
  //    饱和 Colors.X 背景 + Icon(..., color: Colors.white)
  Rule(
    'icon-container-colorblock',
    [
      RegExp(
        r'(Container|DecoratedBox|CircleAvatar)\s*\([^)]*?(backgroundColor|color)\s*:\s*Colors\.(?!transparent|black|white)\w+[^)]*?(Icon|Text)\s*\([^)]*?color\s*:\s*Colors\.white',
        multiLine: true,
      ),
    ],
    '色块 icon 容器（饱和底 + 白前景）→ 改 border-emphasis（tint+描边+本色前景）',
  ),

  // 3. LinearGradient 装饰性 icon 容器
  Rule(
    'linear-gradient-icon-container',
    [
      RegExp(
        r'(Container|DecoratedBox)\s*\([^)]*?decoration\s*:\s*BoxDecoration\s*\(\s*gradient\s*:\s*LinearGradient',
        multiLine: true,
      ),
    ],
    'LinearGradient 装饰性容器 → 内容型页面留作封面；功能型页面改 border-emphasis',
  ),

  // 4. (可选) 饱和卡片 chip 容器：Chip/ChipTheme 用饱和 backgroundColor
  //    —— 暂不检测，避免噪声；按需手动审。
];

bool _isExcludedFile(File f) {
  final name = f.path;
  for (final suf in _excludeFileSuffixes) {
    if (name.endsWith(suf)) return true;
  }
  return false;
}

bool _isExcludedDir(Directory d) {
  final last = d.path.split(Platform.pathSeparator).last;
  return _excludeDirNames.contains(last) || last.startsWith('.');
}

/// 去掉字符串字面量内与注释里的内容（最简启发式：单行注释整行丢；块注释配对丢）。
/// 为简化，正则里靠 `[\s\S]` 跨行已能命中关键模式；注释里的命中可由人工筛。
String _stripComments(String src) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < src.length) {
    // 行注释
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl + 1;
      continue;
    }
    // 块注释
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
      final end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
      continue;
    }
    buffer.write(src[i]);
    i++;
  }
  return buffer.toString();
}

Future<void> main(List<String> args) async {
  var libDir = _root;
  var strict = false;
  final ignoredRuleIds = <String>{};
  for (final a in args) {
    if (a.startsWith('--lib=')) {
      libDir = a.substring('--lib='.length);
    } else if (a == '--strict') {
      strict = true;
    } else if (a.startsWith('--ignore=')) {
      ignoredRuleIds.addAll(a.substring('--ignore='.length).split(','));
    } else if (a == '--help' || a == '-h') {
      stdout.writeln('用法：dart .tool/color_block_scan/scan.dart [--lib=DIR] '
          '[--strict] [--ignore=rule_id,...]');
      exit(0);
    }
  }

  final root = Directory(libDir);
  if (!root.existsSync()) {
    stderr.writeln('目录不存在：$libDir');
    exit(2);
  }

  final hits = <Hit>[];
  await for (final entity in root.list(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (_isExcludedFile(entity)) continue;
    // 排除目录：以路径段判别（处理 lib/lab/demos/_generated/ 这种）
    final parts = entity.path.split(Platform.pathSeparator);
    if (parts.any(_isExcludedDirPathSegment)) continue;
    hits.addAll(await _scanFile(entity));
  }

  // 按文件分组
  hits.sort((a, b) {
    final byFile = a.file.compareTo(b.file);
    if (byFile != 0) return byFile;
    return a.line.compareTo(b.line);
  });

  // 过滤忽略规则
  final visible = hits.where((h) {
    final ruleId = _ruleIdForHit(h, hits);
    return ruleId == null || !ignoredRuleIds.contains(ruleId);
  }).toList();

  if (visible.isEmpty) {
    stdout.writeln('✓ 未发现色块范式代码（$libDir）');
    if (strict) exit(1); // strict 模式下"无命中"也算 OK；要看 --fail-on-found
    return;
  }

  stdout.writeln('发现 ${visible.length} 处色块范式：');
  for (final h in visible) {
    stdout.writeln('  $h');
  }

  if (strict) exit(1);
}

bool _isExcludedDirPathSegment(String seg) =>
    _excludeDirNames.contains(seg) || seg.startsWith('.');

Future<List<Hit>> _scanFile(File f) async {
  final raw = await f.readAsString();
  final src = _stripComments(raw);
  final hits = <Hit>[];
  for (final rule in _rules) {
    for (final pat in rule.patterns) {
      for (final m in pat.allMatches(src)) {
        final offset = m.start;
        final line = _lineOf(src, offset);
        hits.add(Hit(f.path, line, rule.reason));
      }
    }
  }
  return hits;
}

/// 给一个 hit 反查它的 rule id（用于 --ignore 过滤）。简单按原因匹配第一条规则。
String? _ruleIdForHit(Hit h, List<Hit> all) {
  for (final r in _rules) {
    if (all.any((other) => other.file == h.file &&
        other.line == h.line &&
        other.reason == r.reason)) {
      return r.id;
    }
  }
  return null;
}

int _lineOf(String s, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < s.length; i++) {
    if (s.codeUnitAt(i) == 10) line++; // \n
  }
  return line;
}
