// Color 仓库

import 'color_models.dart';
import 'const_color_palette.dart';

class ColorPaletteRepository {
  static List<ColorSwatchModel> get swatches => ColorPaletteConst.swatches;

  static List<ColorPairModel> buildPairs(List<ColorSwatchModel> list) {
    final result = <ColorPairModel>[];
    for (var i = 0; i + 1 < list.length; i += 2) {
      result.add(ColorPairModel(a: list[i], b: list[i + 1]));
    }
    return result;
  }
}
