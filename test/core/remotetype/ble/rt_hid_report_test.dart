import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/ble/rt_hid_report.dart';

/// 标准 boot 鼠标的 HID 报告描述符（5 键 + 3 bit 填充 + X + Y + 滚轮）。
///
/// 字节序照抄 USB HID 规范里的经典鼠标描述符 —— 这是判断
/// [parseRtHidReportMap] 位域解析对不对的唯一凭据：字段位置必须
/// 落在 buttons@0(5bit) / x@8 / y@16 / wheel@24 上。
const List<int> kBootMouseReportMap = <int>[
  0x05, 0x01, // Usage Page (Generic Desktop)
  0x09, 0x02, // Usage (Mouse)
  0xA1, 0x01, // Collection (Application)
  0x09, 0x01, //   Usage (Pointer)
  0xA1, 0x00, //   Collection (Physical)
  0x05, 0x09, //     Usage Page (Button)
  0x19, 0x01, //     Usage Minimum (1)
  0x29, 0x05, //     Usage Maximum (5)
  0x15, 0x00, //     Logical Minimum (0)
  0x25, 0x01, //     Logical Maximum (1)
  0x95, 0x05, //     Report Count (5)
  0x75, 0x01, //     Report Size (1)
  0x81, 0x02, //     Input (Data,Var,Abs)
  0x95, 0x01, //     Report Count (1)
  0x75, 0x03, //     Report Size (3)
  0x81, 0x03, //     Input (Cnst,Var,Abs)
  0x05, 0x01, //     Usage Page (Generic Desktop)
  0x09, 0x30, //     Usage (X)
  0x09, 0x31, //     Usage (Y)
  0x15, 0x81, //     Logical Minimum (-127)
  0x25, 0x7F, //     Logical Maximum (127)
  0x75, 0x08, //     Report Size (8)
  0x95, 0x02, //     Report Count (2)
  0x81, 0x06, //     Input (Data,Var,Rel)
  0x05, 0x08, //     Usage Page (Wheel)
  0x09, 0x05, //     Usage (Wheel)
  0x15, 0x81, //     Logical Minimum (-127)
  0x25, 0x7F, //     Logical Maximum (127)
  0x75, 0x08, //     Report Size (8)
  0x95, 0x01, //     Report Count (1)
  0x81, 0x06, //     Input (Data,Var,Rel)
  0xC0, //   End Collection
  0xC0, // End Collection
];

void main() {
  group('decodeRtHidMouseReport / ISSC 4 字节布局', () {
    test('正常报文解出位移 / 按键 / 滚轮', () {
      final r = decodeRtHidMouseReport(
        <int>[0x01, 0x05, 0xFE, 0x03],
        RtHidMouseLayout.issc4,
      );
      expect(r, isNotNull);
      expect(r!.dx, 5);
      expect(r.dy, -2); // 0xFE = -2（int8 符号扩展）
      expect(r.wheel, 3);
      expect(r.buttons, RtHidButtons.left);
    });

    test('全零报文是空闲态', () {
      final r = decodeRtHidMouseReport(
        <int>[0x00, 0x00, 0x00, 0x00],
        RtHidMouseLayout.issc4,
      );
      expect(r!.isIdle, isTrue);
    });

    test('字节不够时返回 null（不猜、不截断）', () {
      expect(
        decodeRtHidMouseReport(<int>[0x00, 0x01], RtHidMouseLayout.issc4),
        isNull,
      );
      expect(
        decodeRtHidMouseReport(<int>[], RtHidMouseLayout.issc4),
        isNull,
      );
    });

    test('位移按 int8 符号扩展：0x80 = -128', () {
      final r = decodeRtHidMouseReport(
        <int>[0x00, 0x80, 0x7F, 0x00],
        RtHidMouseLayout.issc4,
      );
      expect(r!.dx, -128);
      expect(r.dy, 127);
    });
  });

  group('decodeRtHidMouseReport / Report ID 前缀', () {
    test('Report ID 不匹配的报文被拒', () {
      expect(
        decodeRtHidMouseReport(
          <int>[0x01, 0x00, 0x01, 0x00, 0x00],
          RtHidMouseLayout.issc4ReportId1,
        ),
        isNotNull,
      );
      expect(
        decodeRtHidMouseReport(
          <int>[0x07, 0x00, 0x01, 0x00, 0x00],
          RtHidMouseLayout.issc4ReportId1,
        ),
        isNull,
      );
    });

    test('带 Report ID 的布局，字段整体后移一个字节', () {
      final r = decodeRtHidMouseReport(
        <int>[0x01, 0x00, 0x03, 0x00, 0x02],
        RtHidMouseLayout.issc4ReportId1,
      );
      expect(r!.buttons, 0);
      expect(r.dx, 3);
      expect(r.dy, 0);
      expect(r.wheel, 2);
    });
  });

  group('HID 位序（字节内低位在前）', () {
    test('按键位图 bit0 = 左键、bit1 = 右键（不是高位在前）', () {
      final left = decodeRtHidMouseReport(
        <int>[0x01, 0x00, 0x00, 0x00],
        RtHidMouseLayout.issc4,
      );
      expect(left!.buttons & RtHidButtons.left, RtHidButtons.left);
      expect(left.buttons & RtHidButtons.right, 0);

      final right = decodeRtHidMouseReport(
        <int>[0x02, 0x00, 0x00, 0x00],
        RtHidMouseLayout.issc4,
      );
      expect(right!.buttons & RtHidButtons.right, RtHidButtons.right);
      expect(right.buttons & RtHidButtons.left, 0);
    });

    test('5 位按键位图同样低位在前（描述符解出来的布局）', () {
      final layout = parseRtHidReportMap(kBootMouseReportMap)!;
      final r = decodeRtHidMouseReport(
        <int>[0x03, 0x05, 0xFD, 0x01],
        layout,
      );
      expect(r!.buttons & RtHidButtons.left, RtHidButtons.left);
      expect(r.buttons & RtHidButtons.right, RtHidButtons.right);
    });
  });

  group('RtHidWheel 单位归一化', () {
    test('WHEEL_DELTA(120) 折算成 1 格', () {
      expect(RtHidWheel.normalize(120), 1);
      expect(RtHidWheel.normalize(-120), -1);
      expect(RtHidWheel.normalize(240), 2);
    });

    test('已经是 notch 的值原样保留', () {
      expect(RtHidWheel.normalize(1), 1);
      expect(RtHidWheel.normalize(-1), -1);
      expect(RtHidWheel.normalize(3), 3);
      expect(RtHidWheel.normalize(0), 0);
    });
  });

  group('parseRtHidReportMap / 标准 HOGP 描述符', () {
    test('推导出按钮位图 / X / Y / 滚轮的位置', () {
      final layout = parseRtHidReportMap(kBootMouseReportMap);
      expect(layout, isNotNull);
      expect(layout!.buttonsBitOffset, 0);
      expect(layout.buttonsBitCount, 5);
      expect(layout.xBitOffset, 8);
      expect(layout.yBitOffset, 16);
      expect(layout.wheelBitOffset, 24);
      expect(layout.reportIdBitOffset, -1);
    });

    test('按推导出的布局能正确解码报文', () {
      final layout = parseRtHidReportMap(kBootMouseReportMap)!;
      // buttons=左键(bit0) | 右键(bit1) = 0x03；x=+5；y=-3；wheel=+1
      final r = decodeRtHidMouseReport(
        <int>[0x03, 0x05, 0xFD, 0x01],
        layout,
      );
      expect(r!.buttons & RtHidButtons.left, RtHidButtons.left);
      expect(r.buttons & RtHidButtons.right, RtHidButtons.right);
      expect(r.dx, 5);
      expect(r.dy, -3);
      expect(r.wheel, 1);
    });

    test('没有 X/Y 的描述符返回 null（不是鼠标）', () {
      // 纯键盘描述符：Usage Page(Generic Desktop) / Usage(Keyboard) / 8 个按键
      const List<int> keyboard = <int>[
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
        0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7,
        0x15, 0x00, 0x25, 0x01, 0x95, 0x08, 0x75, 0x01, 0x81, 0x02,
        0xC0,
      ];
      expect(parseRtHidReportMap(keyboard), isNull);
    });

    test('空描述符返回 null', () {
      expect(parseRtHidReportMap(const <int>[]), isNull);
    });
  });

  group('inferRtHidMouseLayout / 从样本反推（ISSC 分支没有 Report Map）', () {
    test('4 字节样本反推出 ISSC 4 字节布局', () {
      final samples = <List<int>>[
        <int>[0x00, 0x05, 0x00, 0x00],
        <int>[0x00, 0x00, 0x05, 0x00],
        <int>[0x01, 0x02, 0x00, 0x00],
        <int>[0x00, 0x00, 0x00, 0x00],
        <int>[0x00, 0x10, 0x10, 0x00],
      ];
      final layout = inferRtHidMouseLayout(samples);
      expect(layout, isNotNull);
      expect(layout!.label, RtHidMouseLayout.issc4.label);
    });

    test('5 字节 + Report ID 的样本反推出对应布局', () {
      final samples = <List<int>>[
        <int>[0x01, 0x00, 0x05, 0x00, 0x00],
        <int>[0x01, 0x00, 0x00, 0x05, 0x00],
        <int>[0x01, 0x01, 0x00, 0x00, 0x00],
        <int>[0x01, 0x00, 0x00, 0x00, 0x00],
      ];
      final layout = inferRtHidMouseLayout(samples);
      expect(layout, isNotNull);
      expect(layout!.label, RtHidMouseLayout.issc4ReportId1.label);
    });

    test('样本为空返回 null', () {
      expect(inferRtHidMouseLayout(const <List<int>>[]), isNull);
    });

    test('候选得分可单独查询（设置页诊断区用）', () {
      final samples = <List<int>>[
        <int>[0x00, 0x05, 0x00, 0x00],
        <int>[0x00, 0x00, 0x05, 0x00],
      ];
      expect(
        scoreRtHidMouseLayout(samples, RtHidMouseLayout.issc4),
        greaterThan(0.5),
      );
      // 4 字节样本解不出 5 字节布局 → 得分 0
      expect(
        scoreRtHidMouseLayout(samples, RtHidMouseLayout.issc5),
        0,
      );
    });
  });

  group('RtHidButtons → RT1 按键名', () {
    test('左右中映射到协议认识的三个键名', () {
      expect(RtHidButtons.rtButtonName(RtHidButtons.left), 'left');
      expect(RtHidButtons.rtButtonName(RtHidButtons.right), 'right');
      expect(RtHidButtons.rtButtonName(RtHidButtons.middle), 'middle');
    });

    test('侧键不映射（PC 端白名单只认三个键）', () {
      expect(RtHidButtons.rtButtonName(RtHidButtons.back), isNull);
      expect(RtHidButtons.rtButtonName(RtHidButtons.forward), isNull);
      expect(RtHidButtons.rtButtonName(0), isNull);
    });
  });

  group('rtHidHex', () {
    test('补零到两位并用空格分隔', () {
      expect(rtHidHex(<int>[0x00, 0x0A, 0xFF]), '00 0a ff');
      expect(rtHidHex(const <int>[]), '');
    });
  });
}
