// 颜色配置数据

import 'color_models.dart';

class ColorPaletteConst {
  static const List<ColorSwatchModel> swatches = [
    // 奶茶色系
    ColorSwatchModel(
      name: '杏仁白',
      cmyk: Cmyk(c: 5, m: 8, y: 12, k: 0),
      rgb: Rgb(r: 243, g: 237, b: 227),
      hex: '#F3EDE3',
    ),
    ColorSwatchModel(
      name: '玫瑰褐',
      cmyk: Cmyk(c: 20, m: 45, y: 35, k: 0),
      rgb: Rgb(r: 199, g: 152, b: 147),
      hex: '#C79893',
    ),
    // 薄荷系
    ColorSwatchModel(
      name: '抹茶绿',
      cmyk: Cmyk(c: 45, m: 5, y: 60, k: 0),
      rgb: Rgb(r: 136, g: 184, b: 139),
      hex: '#88B88B',
    ),
    ColorSwatchModel(
      name: '海沫蓝',
      cmyk: Cmyk(c: 25, m: 10, y: 5, k: 0),
      rgb: Rgb(r: 168, g: 213, b: 226),
      hex: '#A8D5E2',
    ),
    // 暖阳系
    ColorSwatchModel(
      name: '蜜瓜绿',
      cmyk: Cmyk(c: 20, m: 0, y: 50, k: 0),
      rgb: Rgb(r: 189, g: 221, b: 149),
      hex: '#BDDD95',
    ),
    ColorSwatchModel(
      name: '珊瑚粉',
      cmyk: Cmyk(c: 5, m: 35, y: 20, k: 0),
      rgb: Rgb(r: 245, g: 194, b: 199),
      hex: '#F5C2C7',
    ),
    // 薰衣草系
    ColorSwatchModel(
      name: '雾紫',
      cmyk: Cmyk(c: 15, m: 25, y: 0, k: 0),
      rgb: Rgb(r: 203, g: 187, b: 221),
      hex: '#CBBBDD',
    ),
    ColorSwatchModel(
      name: '深茄紫',
      cmyk: Cmyk(c: 45, m: 60, y: 0, k: 0),
      rgb: Rgb(r: 137, g: 109, b: 167),
      hex: '#896DA7',
    ),
  ];
}
