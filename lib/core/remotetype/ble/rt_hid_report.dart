// lib/core/remotetype/ble/rt_hid_report.dart
//
// BLE 鼠标输入报告解码（纯逻辑，零 Flutter / 零插件依赖，可单测）。
//
// 两类来源，布局来源完全不同：
//
//   · 标准 HOGP（SIG 蓝牙 HID over GATT 规范）
//     设备在 Report Map 特征（0x2A4B）里给出完整的 HID 报告描述符，
//     字段位置由描述符推导 —— 见 parseRtHidReportMap。精确、无需猜。
//
//   · ISSC / TSB HID（厂商私有服务 49535343-FE7D-4AE5-8FA9-9FAFD205E455）
//     小米 / Rapoo / Inphic / XISEM 一整片国产鼠标键盘的同源固件。
//     这条路**没有** Report Map 特征，报告布局靠预设或从样本反推
//     —— 见 RtHidMouseLayout.isscXxx 与 inferRtHidMouseLayout。
//
// 术语对齐：
//   · 报告（report）= 设备通知上来的一整包字节
//   · 字段（field）  = 报告里的一个逻辑量（按键位图 / X / Y / 滚轮）
//   · 位偏移         = 字段在报告里的起始 bit 位置（从第 0 bit 算，MSB 在前）
//
// 字段偏移一律用 **bit** 而不是 byte：HID 允许字段不按字节对齐，
// 按 bit 记才能覆盖「3 个按键 + 5 bit 填充 + 8 bit X」这类真实布局。

/// HID Button Page 的按键位掩码。
///
/// 位序与 HID 规范一致（Usage 1 = 左键）。真实鼠标的按键个数由 Report Map
/// 决定，这里的掩码只覆盖通用前 5 个（左/右/中/侧键后/侧键前）。
class RtHidButtons {
  const RtHidButtons._();

  static const int left = 0x01;
  static const int right = 0x02;
  static const int middle = 0x04;
  static const int back = 0x08;
  static const int forward = 0x10;

  /// 已知的按键位掩码全集。
  static const int knownMask = left | right | middle | back | forward;

  /// 按键位掩码 → RT1 协议的按键名（mn-rt rt-align.js 的白名单）。
  ///
  /// 侧键（back/forward）**不映射**：PC 端只认 left/right/middle，
  /// 映射过去会被 normalizeMouseOp 直接丢弃（那里是白名单，不是黑名单）。
  static String? rtButtonName(int buttons) {
    if (buttons & left != 0) return 'left';
    if (buttons & right != 0) return 'right';
    if (buttons & middle != 0) return 'middle';
    return null;
  }
}

/// 一次鼠标输入报告的解码结果。
class RtHidMouseReport {
  const RtHidMouseReport({
    required this.dx,
    required this.dy,
    required this.wheel,
    required this.hWheel,
    required this.buttons,
    this.raw = const <int>[],
  });

  /// 相对位移（计数单位，未做灵敏度缩放）。
  final int dx;
  final int dy;

  /// 垂直滚轮格数。**单位由设备决定**：多数是 notch（±1/±2），
  /// 部分设备发 Windows 的 WHEEL_DELTA（±120）——用 RtHidWheel 归一化。
  final int wheel;

  /// 水平滚轮格数（AC Pan / 横向倾斜）。
  final int hWheel;

  /// 按键位掩码，位义见 [RtHidButtons]。
  final int buttons;

  /// 原始字节，探针与排障用。
  final List<int> raw;

  bool get isIdle => dx == 0 && dy == 0 && wheel == 0 && hWheel == 0 && buttons == 0;

  @override
  String toString() =>
      'dx=$dx dy=$dy wheel=$wheel hWheel=$hWheel buttons=0x${buttons.toRadixString(16)}';
}

/// 报告字节里各字段的位置。
///
/// 全部偏移都是 **bit** 偏移；-1 表示该字段不存在。
class RtHidMouseLayout {
  const RtHidMouseLayout({
    required this.label,
    this.reportIdBitOffset = -1,
    this.reportId = -1,
    this.buttonsBitOffset = -1,
    this.buttonsBitCount = 0,
    this.xBitOffset = -1,
    this.xBitCount = 8,
    this.yBitOffset = -1,
    this.yBitCount = 8,
    this.wheelBitOffset = -1,
    this.wheelBitCount = 8,
    this.hWheelBitOffset = -1,
    this.hWheelBitCount = 8,
  });

  /// 人类可读的名字，探针里显示「当前用的是哪种布局」。
  final String label;

  /// Report ID 字段的 bit 偏移（-1 = 这份报告没有 ID 前缀）。
  final int reportIdBitOffset;

  /// 期望的 Report ID 值（-1 = 不校验）。
  final int reportId;

  /// 按键位图的 bit 偏移与位宽。
  final int buttonsBitOffset;
  final int buttonsBitCount;

  /// X / Y 位移的 bit 偏移与位宽（常见 8，也可 16）。
  final int xBitOffset;
  final int xBitCount;
  final int yBitOffset;
  final int yBitCount;

  /// 垂直 / 水平滚轮的 bit 偏移与位宽。
  final int wheelBitOffset;
  final int wheelBitCount;
  final int hWheelBitOffset;
  final int hWheelBitCount;

  /// 报告最少需要多少字节。
  int get minBytes {
    int bits = 0;
    void take(int offset, int count) {
      if (offset < 0 || count <= 0) return;
      final int end = offset + count;
      if (end > bits) bits = end;
    }

    take(reportIdBitOffset, 8);
    take(buttonsBitOffset, buttonsBitCount);
    take(xBitOffset, xBitCount);
    take(yBitOffset, yBitCount);
    take(wheelBitOffset, wheelBitCount);
    take(hWheelBitOffset, hWheelBitCount);
    return (bits + 7) ~/ 8;
  }

  // ── 预设布局 ────────────────────────────────────────────────────────
  //
  // ISSC / TSB 鼠标的经典布局：[buttons(1B), x(int8), y(int8), wheel(int8)]
  static const RtHidMouseLayout issc4 = RtHidMouseLayout(
    label: 'ISSC 4B [buttons,x,y,wheel]',
    buttonsBitOffset: 0,
    buttonsBitCount: 8,
    xBitOffset: 8,
    yBitOffset: 16,
    wheelBitOffset: 24,
  );

  /// ISSC 5B：末尾多一个水平滚轮（AC Pan）。
  static const RtHidMouseLayout issc5 = RtHidMouseLayout(
    label: 'ISSC 5B [buttons,x,y,wheel,hwheel]',
    buttonsBitOffset: 0,
    buttonsBitCount: 8,
    xBitOffset: 8,
    yBitOffset: 16,
    wheelBitOffset: 24,
    hWheelBitOffset: 32,
  );

  /// Boot Mouse Input Report（0x2A33）固定布局：
  /// [buttons(1B), x(int8), y(int8), wheel(int8)]。
  ///
  /// 为什么重要：HID **boot 协议**的报告布局是规范写死的，不需要 Report Map。
  /// 而 Android 对 0x1812 服务下的 2A4A/2A4B/2A4C/2A4D 全封锁
  /// （含 read），唯独 2A33 不在受限清单里 —— 所以「切 boot 协议 +
  /// 订阅 0x2A33」是唯一一条既合规又全速率的读鼠标数据通路。
  static const RtHidMouseLayout bootMouse = RtHidMouseLayout(
    label: 'Boot Mouse [buttons,x,y,wheel]',
    buttonsBitOffset: 0,
    buttonsBitCount: 8,
    xBitOffset: 8,
    yBitOffset: 16,
    wheelBitOffset: 24,
  );

  /// ISSC 5B，首字节是 Report ID（值 0）：[rid, buttons, x, y, wheel]
  static const RtHidMouseLayout issc4ReportId0 = RtHidMouseLayout(
    label: 'ISSC 5B rid=0 [rid,buttons,x,y,wheel]',
    reportIdBitOffset: 0,
    reportId: 0,
    buttonsBitOffset: 8,
    buttonsBitCount: 8,
    xBitOffset: 16,
    yBitOffset: 24,
    wheelBitOffset: 32,
  );

  /// ISSC 5B，首字节是 Report ID（值 1）：[rid, buttons, x, y, wheel]
  static const RtHidMouseLayout issc4ReportId1 = RtHidMouseLayout(
    label: 'ISSC 5B rid=1 [rid,buttons,x,y,wheel]',
    reportIdBitOffset: 0,
    reportId: 1,
    buttonsBitOffset: 8,
    buttonsBitCount: 8,
    xBitOffset: 16,
    yBitOffset: 24,
    wheelBitOffset: 32,
  );

  /// ISSC 6B，首字节是 Report ID（值 0）：[rid, buttons, x, y, wheel, hwheel]
  static const RtHidMouseLayout issc5ReportId0 = RtHidMouseLayout(
    label: 'ISSC 6B rid=0 [rid,buttons,x,y,wheel,hwheel]',
    reportIdBitOffset: 0,
    reportId: 0,
    buttonsBitOffset: 8,
    buttonsBitCount: 8,
    xBitOffset: 16,
    yBitOffset: 24,
    wheelBitOffset: 32,
    hWheelBitOffset: 40,
  );

  /// ISSC 6B，首字节是 Report ID（值 1）：[rid, buttons, x, y, wheel, hwheel]
  static const RtHidMouseLayout issc5ReportId1 = RtHidMouseLayout(
    label: 'ISSC 6B rid=1 [rid,buttons,x,y,wheel,hwheel]',
    reportIdBitOffset: 0,
    reportId: 1,
    buttonsBitOffset: 8,
    buttonsBitCount: 8,
    xBitOffset: 16,
    yBitOffset: 24,
    wheelBitOffset: 32,
    hWheelBitOffset: 40,
  );

  /// 标准 HOGP 常见布局（boot 风格，与 ISSC 4B 同形）。
  static const RtHidMouseLayout hogpBoot = RtHidMouseLayout(
    label: 'HOGP boot [buttons,x,y,wheel]',
    buttonsBitOffset: 0,
    buttonsBitCount: 8,
    xBitOffset: 8,
    yBitOffset: 16,
    wheelBitOffset: 24,
  );

  /// 参与「从样本反推布局」的候选集。
  ///
  /// 顺序 = 字节数从少到多。得分相同时取先出现者（短的更可能是真布局 ——
  /// 多出来的字段多半是猜出来的）。
  static const List<RtHidMouseLayout> inferenceCandidates = <RtHidMouseLayout>[
    issc4,
    issc5,
    issc4ReportId0,
    issc4ReportId1,
    issc5ReportId0,
    issc5ReportId1,
    hogpBoot,
  ];
}

/// 从 HID 报告描述符（Report Map）推导鼠标字段布局。
///
/// 返回 null 表示这份描述符里没有成对的 X / Y —— 不是鼠标，或描述符不完整。
///
/// 解析范围刻意收窄到鼠标用得到的三种 Usage Page：
///   · 0x01 Generic Desktop：0x30 = X，0x31 = Y
///   · 0x08 Wheel：0x05 = Wheel，0x06 = AC Pan（水平）
///   · 0x09 Button：Usage >= 1 的位图
///
/// 其它 Usage（Consumer Control 音量键之类）直接忽略 —— 我们的 RT1 协议
/// 本来也只支持 left/right/middle 三键，多出来的键发过去会被 PC 端丢弃。
///
/// 已知简化：**只取第一个同时含 X 与 Y 的 report id**。鼠标通常只有一个
/// 输入报告；带 Report ID 的复合设备（键鼠一体）会只取到第一个。
RtHidMouseLayout? parseRtHidReportMap(List<int> map) {
  if (map.isEmpty) return null;

  int usagePage = 0;
  int reportSize = 0;
  int reportCount = 0;
  int? reportId;

  final List<int> usages = <int>[];
  int? usageMin;
  int? usageMax;

  // 每个 report id 一套字段；鼠标通常只有一个
  final Map<int?, _RtHidFields> perReport = <int?, _RtHidFields>{};

  int bitOffset = 0;
  int i = 0;

  while (i < map.length) {
    // HID 项目前缀字节的位域：
    //   bit 1..0 = bSize（0/1/2/4 字节）   bit 3..2 = bType（0 主 / 1 全局 / 2 局部）
    //   bit 7..4 = bTag
    final int prefix = map[i++];
    final int size = const <int>[0, 1, 2, 4][prefix & 0x03];
    final int type = (prefix >> 2) & 0x03;
    final int tag = (prefix >> 4) & 0x0F;

    int data = 0;
    if (size > 0) {
      if (i + size > map.length) break;
      for (int k = 0; k < size; k++) {
        data |= map[i + k] << (8 * k);
      }
      i += size;
    }

    switch (type) {
      case 0: // Main
        if (tag == 8) {
          // Input：真正吃报告位的地方
          final List<int> itemUsages = _resolveUsages(usages, usageMin, usageMax);
          final fields = perReport.putIfAbsent(reportId, () => _RtHidFields());
          for (int f = 0; f < reportCount; f++) {
            final int usage = (f < itemUsages.length) ? itemUsages[f] : 0;
            final int bit = bitOffset + f * reportSize;
            _applyUsage(fields, usagePage, usage, bit, reportSize, reportCount);
          }
          bitOffset += reportSize * reportCount;
        } else if (tag == 9 || tag == 10) {
          // Output / Feature 也占报告位 —— 位偏移要跟着走，否则后面全错位
          bitOffset += reportSize * reportCount;
        }
        // 本地项只作用于下一个 Main 项，用完即清
        usages.clear();
        usageMin = null;
        usageMax = null;

      case 1: // Global
        switch (tag) {
          case 0:
            usagePage = data;
          case 7:
            reportSize = data;
          case 8:
            reportId = data;
            bitOffset = 0; // 换 report id = 换一份报告，位偏移从头算
          case 9:
            reportCount = data;
        }

      case 2: // Local
        switch (tag) {
          case 0:
            usages.add(data);
          case 1:
            usageMin = data;
          case 2:
            usageMax = data;
        }
    }
  }

  // 取第一个同时有 X 与 Y 的报告
  for (final entry in perReport.entries) {
    final f = entry.value;
    if (f.xBitOffset < 0 || f.yBitOffset < 0) continue;

    // 设备用 Report ID 时，通知上来的数据首字节就是 Report ID，
    // 所有字段偏移整体后移 8 bit。
    final int shift = entry.key != null ? 8 : 0;

    return RtHidMouseLayout(
      label: 'HOGP reportMap id=${entry.key ?? "-"}',
      reportIdBitOffset: entry.key != null ? 0 : -1,
      reportId: entry.key ?? -1,
      buttonsBitOffset: f.buttonsBitOffset >= 0 ? f.buttonsBitOffset + shift : -1,
      buttonsBitCount: f.buttonsBitCount,
      xBitOffset: f.xBitOffset + shift,
      xBitCount: f.xBitCount,
      yBitOffset: f.yBitOffset + shift,
      yBitCount: f.yBitCount,
      wheelBitOffset: f.wheelBitOffset >= 0 ? f.wheelBitOffset + shift : -1,
      wheelBitCount: f.wheelBitCount,
      hWheelBitOffset: f.hWheelBitOffset >= 0 ? f.hWheelBitOffset + shift : -1,
      hWheelBitCount: f.hWheelBitCount,
    );
  }
  return null;
}

/// 按 Usage 把一个 Input 字段记到对应位置上。
void _applyUsage(
  _RtHidFields fields,
  int usagePage,
  int usage,
  int bit,
  int reportSize,
  int reportCount,
) {
  if (usagePage == 0x01) {
    // Generic Desktop
    if (usage == 0x30 && fields.xBitOffset < 0) {
      fields.xBitOffset = bit;
      fields.xBitCount = reportSize;
    } else if (usage == 0x31 && fields.yBitOffset < 0) {
      fields.yBitOffset = bit;
      fields.yBitCount = reportSize;
    }
  } else if (usagePage == 0x08) {
    // Wheel
    if (usage == 0x05 && fields.wheelBitOffset < 0) {
      fields.wheelBitOffset = bit;
      fields.wheelBitCount = reportSize;
    } else if (usage == 0x06 && fields.hWheelBitOffset < 0) {
      fields.hWheelBitOffset = bit;
      fields.hWheelBitCount = reportSize;
    }
  } else if (usagePage == 0x09) {
    // Button：位图，每个按键 1 bit
    if (usage >= 1 && fields.buttonsBitOffset < 0) {
      fields.buttonsBitOffset = bit;
      fields.buttonsBitCount = reportSize == 1 ? reportCount : reportSize;
    }
  }
}

/// Usage Min/Max 展开成区间；没有就用显式 Usage 列表。
List<int> _resolveUsages(List<int> usages, int? min, int? max) {
  if (min != null && max != null && max >= min) {
    return <int>[for (int u = min; u <= max; u++) u];
  }
  return usages;
}

/// 报告描述符解析过程中的字段累加器。
class _RtHidFields {
  int xBitOffset = -1;
  int xBitCount = 8;
  int yBitOffset = -1;
  int yBitCount = 8;
  int wheelBitOffset = -1;
  int wheelBitCount = 8;
  int hWheelBitOffset = -1;
  int hWheelBitCount = 8;
  int buttonsBitOffset = -1;
  int buttonsBitCount = 0;
}

/// 按布局解码一份报告。
///
/// 返回 null 表示「这份报告不属于这个布局」——只有带 Report ID 校验的布局
/// 才会这样（Report ID 对不上）。
RtHidMouseReport? decodeRtHidMouseReport(List<int> bytes, RtHidMouseLayout layout) {
  if (bytes.isEmpty) return null;
  if (bytes.length < layout.minBytes) return null;

  if (layout.reportIdBitOffset >= 0 && layout.reportId >= 0) {
    final int v = _readBits(bytes, layout.reportIdBitOffset, 8);
    if (v != layout.reportId) return null;
  }

  final int buttons = layout.buttonsBitOffset >= 0
      ? _readBits(bytes, layout.buttonsBitOffset, layout.buttonsBitCount)
      : 0;
  final int dx = layout.xBitOffset >= 0
      ? _toSigned(_readBits(bytes, layout.xBitOffset, layout.xBitCount), layout.xBitCount)
      : 0;
  final int dy = layout.yBitOffset >= 0
      ? _toSigned(_readBits(bytes, layout.yBitOffset, layout.yBitCount), layout.yBitCount)
      : 0;
  final int wheel = layout.wheelBitOffset >= 0
      ? _toSigned(_readBits(bytes, layout.wheelBitOffset, layout.wheelBitCount), layout.wheelBitCount)
      : 0;
  final int hWheel = layout.hWheelBitOffset >= 0
      ? _toSigned(
          _readBits(bytes, layout.hWheelBitOffset, layout.hWheelBitCount),
          layout.hWheelBitCount,
        )
      : 0;

  return RtHidMouseReport(
    dx: dx,
    dy: dy,
    wheel: wheel,
    hWheel: hWheel,
    buttons: buttons,
    raw: List<int>.unmodifiable(bytes),
  );
}

/// 从样本反推布局（ISSC 分支没有 Report Map，只能这么干）。
///
/// 判据：**按键字节与滚轮字节应当大部分时候是 0**。
/// 布局猜错时，这两处会错位到 X/Y 上 —— 鼠标一动它们就非零，
/// 于是分数掉下来。
///
/// 返回 null 表示所有候选都解释不通（样本太少或字节数超出所有候选）。
RtHidMouseLayout? inferRtHidMouseLayout(List<List<int>> samples) {
  if (samples.isEmpty) return null;

  RtHidMouseLayout? best;
  double bestScore = -1;

  for (final layout in RtHidMouseLayout.inferenceCandidates) {
    final double score = _scoreLayout(samples, layout);
    if (score > bestScore) {
      bestScore = score;
      best = layout;
    }
  }
  if (best == null || bestScore <= 0) return null;
  return best;
}

/// 布局评分：0..1。1 = 完美解释所有样本。
double _scoreLayout(List<List<int>> samples, RtHidMouseLayout layout) {
  int total = 0;
  int zeroButtons = 0;
  int zeroWheel = 0;

  for (final s in samples) {
    final r = decodeRtHidMouseReport(s, layout);
    if (r == null) return 0; // 有样本解不出来 → 布局不对
    total++;
    if (r.buttons == 0) zeroButtons++;
    if (r.wheel == 0) zeroWheel++;
  }
  if (total == 0) return 0;
  return (zeroButtons + zeroWheel) / (2 * total);
}

/// 对某个候选布局打分（探针里展示各候选得分，便于肉眼核对）。
double scoreRtHidMouseLayout(List<List<int>> samples, RtHidMouseLayout layout) =>
    _scoreLayout(samples, layout);

/// 从报告字节里读 bit。
///
/// **位序是 HID 的关键约定**：字段的每一位按「字节内低位在前」打包 ——
/// 字段的第 0 位落在所在字节的最低位，跨字节则是小端（先低字节后高字节）。
///
/// 这条约定有两个直接后果，踩错就会全盘错位：
///   · 按键位图：byte0 的 bit0 = 按钮 1（右键是 bit1，不是 bit7）
///   · 16 位 X/Y：低字节在前（little-endian）
///
/// 所以这里**不能**按「字节内高位在前」读 —— 那样按钮位图会整个反过来
/// （0x03 变成「只有左键」），而 0x01 明明是左键却读成 0。
int _readBits(List<int> bytes, int bitOffset, int bitCount) {
  if (bitCount <= 0) return 0;
  int value = 0;
  for (int i = 0; i < bitCount; i++) {
    final int bit = bitOffset + i;
    final int byteIndex = bit >> 3;
    if (byteIndex >= bytes.length) break;
    final int b = (bytes[byteIndex] >> (bit & 7)) & 1;
    value |= b << i;
  }
  return value;
}

/// 按位宽做符号扩展（8 bit 的 0xFF = -1）。
int _toSigned(int value, int bitCount) {
  if (bitCount <= 0) return 0;
  final int signBit = 1 << (bitCount - 1);
  if (value & signBit != 0) return value - (1 << bitCount);
  return value;
}

/// 滚轮单位归一化。
///
/// 设备发两套单位：
///   · notch（±1/±2 一格）—— 多数国产鼠标
///   · WHEEL_DELTA（±120 一格）—— Windows 传统约定，部分设备照抄
/// 直接转发会让 PC 滚一格滚 120 格。这里统一折算成 notch。
class RtHidWheel {
  const RtHidWheel._();

  static const int windowsDetent = 120;

  static int normalize(int value) {
    if (value == 0) return 0;
    final int a = value.abs();
    if (a >= windowsDetent) return value ~/ windowsDetent;
    return value;
  }
}

/// 字节数组 → 便于人读的 hex（探针与日志用）。
String rtHidHex(List<int> bytes) =>
    bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join(' ');
