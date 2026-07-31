// 存储导入导出格式常量
//
// 文本格式设计（v1）：
//
// ```
// # STORAGE_DUMP_V1
// # timestamp=2026-07-31T10:00:00.000
// # total_keys=42
// # total_size=8192
//
// [meta]
// app_version=1.0.0
// platform=android
// export_time=2026-07-31T10:00:00.000
//
// [hive:calendarEvents]
// K:0
// T:Event
// V:{"title":"Birthday","type":"solar",...}
//
// [hive:body_records]
// K:1719822000000
// T:BodyRecord
// V:{"bodyPartId":"head","content":"头痛","painLevel":3,"createdAt":"2026-07-01T..."}
//
// [prefs]
// K:theme_mode
// T:String
// V:dark
//
// [notes]
// F:abc123.toml
// B:TOML_BASE64_ENCODED_CONTENT
//
// [media]
// P:relative/path/to/file.jpg
// T:image
// B:BASE64_ENCODED_FILE_BYTES
// ```
//
// 关键设计：
// - 使用 `# 注释` 开头行作为头信息
// - 多行用一对前缀标签（K/T/V 或 F/B 或 P/T/B），便于手动复制粘贴保留语义
// - 大字段（二进制/TOML/媒体文件）使用 Base64 编码
// - 块定义以 `[section]` 单独成行开始
// - 完整可靠：可被任意新 app 解析还原

const String kStorageDumpHeader = 'STORAGE_DUMP_V1';
const String kStorageDumpCommentPrefix = '# ';

/// section header
String storageSection(String name) => '[$name]';

/// key marker
String storageKeyMarker(String key) => 'K:$key';

/// type marker
String storageTypeMarker(String type) => 'T:$type';

/// value marker
String storageValueMarker(String value) => 'V:$value';

/// file marker
String storageFileMarker(String name) => 'F:$name';

/// path marker
String storagePathMarker(String path) => 'P:$path';

/// base64 marker
String storageBase64Marker(String b64) => 'B:$b64';

/// 已知 Hive value 类型字符串
class HiveTypeNames {
  static const String event = 'Event';
  static const String person = 'Person';
  static const String bodyRecord = 'BodyRecord';
  static const String map = 'Map<String,dynamic>';
  static const String list = 'List<dynamic>';
  static const String string = 'String';
  static const String int = 'int';
  static const String double = 'double';
  static const String bool = 'bool';
  static const String dynamic = 'dynamic';
  static const String null_ = 'null';
}

/// 导出进度阶段
enum ExportStage {
  meta,
  hive,
  prefs,
  notes,
  media,
  done,
}

String exportStageLabel(ExportStage stage) {
  switch (stage) {
    case ExportStage.meta:
      return '元数据';
    case ExportStage.hive:
      return 'Hive Boxes';
    case ExportStage.prefs:
      return '应用配置';
    case ExportStage.notes:
      return '笔记文件';
    case ExportStage.media:
      return '媒体文件';
    case ExportStage.done:
      return '完成';
  }
}

/// 导入进度阶段
enum ImportStage {
  parse,
  prefs,
  hive,
  notes,
  media,
  done,
}

String importStageLabel(ImportStage stage) {
  switch (stage) {
    case ImportStage.parse:
      return '解析文本';
    case ImportStage.prefs:
      return '写入应用配置';
    case ImportStage.hive:
      return '写入 Hive Boxes';
    case ImportStage.notes:
      return '写入笔记';
    case ImportStage.media:
      return '写入媒体文件';
    case ImportStage.done:
      return '完成';
  }
}
