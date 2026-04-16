// GitHub Issues 数据模型

class IssueModel {
  final int number;
  final String title;
  final String? body;
  final String state;
  final String author;
  final DateTime createdAt;
  final String url;

  IssueModel({
    required this.number,
    required this.title,
    this.body,
    required this.state,
    required this.author,
    required this.createdAt,
    required this.url,
  });

  factory IssueModel.fromJson(Map<String, dynamic> json) {
    return IssueModel(
      number: json['number'] as int,
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      state: json['state'] as String? ?? 'open',
      author: (json['user'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      url: json['html_url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'title': title,
        'body': body,
        'state': state,
        'author': author,
        'created_at': createdAt.toIso8601String(),
        'url': url,
      };
}

class CreateIssueRequest {
  final String title;
  final String? body;
  final List<String>? labels;

  CreateIssueRequest({
    required this.title,
    this.body,
    this.labels,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'title': title};
    if (body != null && body!.isNotEmpty) map['body'] = body;
    if (labels != null && labels!.isNotEmpty) map['labels'] = labels;
    return map;
  }
}

class UpdateIssueRequest {
  final String? title;
  final String? body;
  final String? state;
  final List<String>? labels;

  UpdateIssueRequest({this.title, this.body, this.state, this.labels});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (body != null) map['body'] = body;
    if (state != null) map['state'] = state;
    if (labels != null) map['labels'] = labels;
    return map;
  }
}
