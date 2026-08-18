// Color 数据模型

class Cmyk {
  final int c, m, y, k;
  const Cmyk({required this.c, required this.m, required this.y, required this.k});
}

class Rgb {
  final int r, g, b;
  const Rgb({required this.r, required this.g, required this.b});
}

class ColorSwatchModel {
  final String name;
  final Cmyk cmyk;
  final Rgb rgb;
  final String hex;

  const ColorSwatchModel({
    required this.name,
    required this.cmyk,
    required this.rgb,
    required this.hex,
  });
}

class ColorPairModel {
  final ColorSwatchModel a;
  final ColorSwatchModel b;

  const ColorPairModel({required this.a, required this.b});
}
