// relation-calc demo 常量 —— 全部经 RelationCalcConsts.* 暴露，禁止散落硬编码。
//
// 命名遵循项目 flutter-work-flow 规范：const_xxxx.dart 统一管理模块常量。

/// demo 元信息。
class RelationCalcConsts {
  RelationCalcConsts._();

  static const String demoTitle = '关系计算器';
  static const String demoSlug = 'relation-calc';
  static const String demoDescription = '通用关系链式计算：A 的 B = C，无限嵌套，内置亲戚称呼预设';

  /// 默认起点实体名（预设里的「我」）。
  static const String defaultStartEntityName = '我';
}

/// UI 文案。
class RelationCalcUiText {
  RelationCalcUiText._();

  static const String calcTab = '计算';
  static const String manageTab = '管理';
  static const String presetTab = '预设';

  static const String startEntityLabel = '起点';
  static const String chainLabel = '关系链';
  static const String resultLabel = '结果';
  static const String emptyChainHint = '点击下方关系词开始计算';
  static const String notResolvable = '无法计算';
  static const String notResolvableHint = '当前关系链在此步骤无匹配规则';

  static const String undo = '撤销';
  static const String clear = '清空';
  static const String pickStart = '选择起点';

  static const String entitiesTab = '实体';
  static const String termsTab = '关系词';
  static const String rulesTab = '规则';

  static const String addEntity = '新增实体';
  static const String editEntity = '编辑实体';
  static const String addTerm = '新增关系词';
  static const String editTerm = '编辑关系词';
  static const String addRule = '新增规则';

  static const String nameLabel = '名称';
  static const String noteLabel = '描述';
  static const String fromLabel = '起点实体';
  static const String termLabel = '关系词';
  static const String toLabel = '结果实体';

  static const String save = '保存';
  static const String cancel = '取消';
  static const String delete = '删除';

  static const String presetInfoTitle = '亲戚称呼预设';
  static const String presetInfoBody = '内置「常用直系 + 主要旁系」约 50+ 称谓。'
      '首次进入自动导入；重置会清空你的自定义数据并恢复预设。';
  static const String resetPreset = '重置为预设';
  static const String resetPresetConfirm = '将清空全部自定义实体/关系词/规则并恢复内置预设，确定？';
}
