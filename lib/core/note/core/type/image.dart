part of 'type.dart';

class ImageType extends BlockType {
  final String src;
  final String? caption;
  final double? width;
  final double? height;

  const ImageType({
    required this.src,
    this.caption,
    this.width,
    this.height,
  }) : super(tag: 'image');

  factory ImageType.fromData(Map<String, dynamic> data) {
    return ImageType(
      src: data['src'] as String? ?? '',
      caption: data['caption'] as String?,
      width: (data['width'] as num?)?.toDouble(),
      height: (data['height'] as num?)?.toDouble(),
    );
  }

  ImageType copyWith({
    String? src,
    String? caption,
    double? width,
    double? height,
  }) {
    return ImageType(
      src: src ?? this.src,
      caption: caption ?? this.caption,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'src': src};
    if (caption != null) map['caption'] = caption;
    if (width != null) map['width'] = width;
    if (height != null) map['height'] = height;
    return map;
  }

  @override
  bool operator ==(Object other) =>
    other is ImageType &&
    other.src == src &&
    other.caption == caption &&
    other.width == width &&
    other.height == height;
  @override
  int get hashCode => Object.hash(runtimeType, src, caption, width, height);
}
