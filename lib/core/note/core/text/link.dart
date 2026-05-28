part of 'inline_format.dart';

class LinkFormat extends InlineFormat {
  final String url;
  const LinkFormat(this.url);

  @override
  Map<String, dynamic> toJson() => {'type': 'link', 'url': url};

  @override
  bool operator ==(Object other) => other is LinkFormat && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
