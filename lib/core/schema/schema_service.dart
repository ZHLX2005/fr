// Schema 服务 - 内部链接协议管理
//
// 协议格式: fr://lab/demo/{demo-key}
// 示例: [悬浮截屏](fr://lab/demo/悬浮截屏)
//
// 使用方式:
// - 在文本中使用 [显示文字](fr://lab/demo/目标Demo) 格式
// - 渲染后显示为下划线高亮文本
// - 点击后跳转到对应的 Demo 页面

import 'package:flutter/material.dart';
import '../../lab/lab_container.dart';

/// Schema 路由协议
class SchemaRoutes {
  SchemaRoutes._();

  /// 协议前缀
  static const String scheme = 'fr';

  /// 基础路径
  static const String base = '//lab';

  /// Demo 路径
  static const String demo = '$base/demo';

  /// Core 页面路径
  static const String core = '$base/core';

  /// 构建 Demo 完整路径
  static String demoPath(String demoKey) => '$scheme:$demo/$demoKey';

  /// 构建 Core 页面完整路径
  static String corePath(String pageKey) => '$scheme:$core/$pageKey';

  /// 解析路径获取 demo key
  static String? parseDemoKey(String path) {
    final prefix = '$scheme:$demo/';
    if (path.startsWith(prefix)) {
      return path.substring(prefix.length);
    }
    return null;
  }

  /// 检查是否是有效的 demo schema
  static bool isDemoSchema(String path) {
    return path.startsWith('$scheme:$demo/');
  }

  /// 解析路径获取 core page key
  static String? parseCoreKey(String path) {
    final prefix = '$scheme:$core/';
    if (path.startsWith(prefix)) {
      return path.substring(prefix.length);
    }
    return null;
  }

  /// 检查是否是有效的 core schema
  static bool isCoreSchema(String path) {
    return path.startsWith('$scheme:$core/');
  }
}

/// Schema 映射项
class SchemaEntry {
  final String key;
  final String title;
  final String schema;
  final IconData icon;

  const SchemaEntry({
    required this.key,
    required this.title,
    required this.schema,
    this.icon = Icons.apps,
  });
}

/// Schema 注册表 - 自动发现所有注册的 Demo
class SchemaRegistry {
  static final SchemaRegistry _instance = SchemaRegistry._internal();
  factory SchemaRegistry() => _instance;
  SchemaRegistry._internal();

  final Map<String, SchemaEntry> _entries = {};

  /// 初始化 - 从 DemoRegistry 自动发现 + 注册核心页面
  void discover() {
    _entries.clear();
    final demos = demoRegistry.getAll();
    for (final entry in demos) {
      final demoKey = entry.key;
      final demo = entry.value;
      _entries[demoKey] = SchemaEntry(
        key: demoKey,
        title: demo.title,
        schema: SchemaRoutes.demoPath(demoKey),
        icon: Icons.apps,
      );
    }
    _registerCorePages();
  }

  /// 注册核心主页面
  void _registerCorePages() {
    final corePages = [
      const SchemaEntry(
        key: 'profile',
        title: '个人中心',
        schema: 'fr://lab/core/profile',
        icon: Icons.person,
      ),
      const SchemaEntry(
        key: 'focus',
        title: '专注',
        schema: 'fr://lab/core/focus',
        icon: Icons.timer,
      ),
      const SchemaEntry(
        key: 'home',
        title: 'AI 助手',
        schema: 'fr://lab/core/home',
        icon: Icons.chat_bubble,
      ),
      const SchemaEntry(
        key: 'timetable',
        title: '课表',
        schema: 'fr://lab/core/timetable',
        icon: Icons.calendar_month,
      ),
    ];
    for (final page in corePages) {
      _entries[page.key] = page;
    }
  }

  /// 手动注册
  void register(SchemaEntry entry) {
    _entries[entry.key] = entry;
  }

  /// 获取所有条目
  List<SchemaEntry> getAll() => _entries.values.toList();

  /// 根据 key 获取
  SchemaEntry? get(String key) => _entries[key];

  /// 根据 schema 获取
  SchemaEntry? getBySchema(String schema) {
    for (final entry in _entries.values) {
      if (entry.schema == schema) {
        return entry;
      }
    }
    return null;
  }

  /// 根据 path 获取
  SchemaEntry? getByPath(String path) {
    final demoKey = SchemaRoutes.parseDemoKey(path);
    if (demoKey != null) {
      return _entries[demoKey];
    }
    return null;
  }

  /// 检查是否存在
  bool contains(String key) => _entries.containsKey(key);

  /// 条目数量
  int get count => _entries.length;
}

/// 全局 Schema 注册表
final schemaRegistry = SchemaRegistry();

/// 初始化 Schema 发现
void initSchemaRegistry() {
  schemaRegistry.discover();
}
