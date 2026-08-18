import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/torch/const_torch.dart';

void main() {
  group('TorchConst — 边界守卫', () {
    test('仅保留动画/亮度字段', () {
      // 直接访问：编译期挡住任何新增的 UI hex 字段（reviewer 须主动加新断言）
      expect(TorchConst.modeSwitchDuration.inMilliseconds, 200);
      expect(TorchConst.pulseDuration.inMilliseconds, 1500);
      expect(TorchConst.controlsHideDelay.inSeconds, 3);
      expect(TorchConst.controlsFadeDuration.inMilliseconds, 400);
      expect(TorchConst.minBrightness, 0.1);
      expect(TorchConst.maxBrightness, 1.0);
      expect(TorchConst.brightnessSwipeSensitivity, 200.0);
    });
  });

  group('EyeProtectionColors — 护眼色预设保留', () {
    test('10 个预设颜色与名称对齐', () {
      expect(EyeProtectionColors.presets.length, 10);
      expect(EyeProtectionColors.presetNames.length, 10);
      expect(EyeProtectionColors.presets[0], EyeProtectionColors.warmYellow);
      expect(EyeProtectionColors.presetNames[0], '护眼黄');
    });
  });
}
