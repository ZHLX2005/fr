// Rive 演示模块常量
//
// 集中管理 asset 路径、tab key、动画参数、缓冲范围，
// 减少多文件间的耦合和改动成本。

/// Rive 资源文件路径
class RiveAssets {
  RiveAssets._();

  /// 摆钟动画（pendulum.riv）
  static const String pendulum = 'assets/rive/pendulum/pendulum.riv';

  /// 数据绑定动画（input_machine.riv，ViewModel 暴露 in_input 布尔属性）
  static const String inputMachine = 'assets/rive/input_machine/input_machine.riv';

  /// 实验室压力释放表情（笑脸）
  static const String smiley = 'assets/rive/smiley_stress_reliever.riv';
}

/// Demo 子页 Tab 标识
///
/// 在 [RiveDemoPage] IndexedStack 中用于切换。
enum RiveDemoTab {
  /// 摆钟
  pendulum,

  /// 数据绑定
  dataBind,

  /// 实验室
  lab;

  String get label {
    switch (this) {
      case RiveDemoTab.pendulum:
        return '摆钟';
      case RiveDemoTab.dataBind:
        return '数据绑定';
      case RiveDemoTab.lab:
        return '实验室';
    }
  }

  String get slug {
    switch (this) {
      case RiveDemoTab.pendulum:
        return 'rive-pendulum';
      case RiveDemoTab.dataBind:
        return 'rive-data-bind';
      case RiveDemoTab.lab:
        return 'demo-lab';
    }
  }
}

/// 数据绑定 ViewModel 字段名
class RiveDataBindKeys {
  RiveDataBindKeys._();

  /// input_machine.riv 中 ViewModel 暴露的布尔属性名
  static const String inInput = 'in_input';
}

/// 动画交互参数
class RiveLabParams {
  RiveLabParams._();

  /// 横向最大偏移（像素）
  static const double maxOffsetX = 110.0;

  /// 纵向最大偏移（像素）
  static const double maxOffsetY = 150.0;

  /// 点击时缩放比例
  static const double pressedScale = 0.94;

  /// 动画过渡时长
  static const Duration animDuration = Duration(milliseconds: 180);

  /// 阴影 glow 基数（点击次数为 0 时的 blurRadius）
  static const double baseGlow = 14.0;

  /// 每次点击增加的 glow（最多累计 8 次）
  static const double glowPerTap = 3.0;
}

/// 数据绑定演示参数
class RiveDataBindParams {
  RiveDataBindParams._();

  /// 脉冲触发后回到 false 的延迟
  static const Duration pulseDuration = Duration(milliseconds: 300);
}

/// fr:// URL slug
class RiveDemoSlugs {
  RiveDemoSlugs._();

  /// 主 slug（统一入口）
  static const String main = 'rive-demo';

  /// 旧 slug 别名（兼容历史链接，打开默认跳到对应 tab）
  static const String legacyPendulum = 'rive-pendulum';
  static const String legacyDataBind = 'rive-data-bind';
  static const String legacyLab = 'demo-lab';
}