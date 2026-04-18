class WorkflowRunModel {
  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final String branch;
  final String event;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String url;
  final List<WorkflowJobModel> jobs;

  WorkflowRunModel({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.branch,
    required this.event,
    required this.createdAt,
    required this.updatedAt,
    required this.url,
    this.jobs = const [],
  });

  bool get isCompleted => status == 'completed';

  bool get isSuccess => conclusion == 'success';

  WorkflowRunModel copyWith({List<WorkflowJobModel>? jobs}) {
    return WorkflowRunModel(
      id: id,
      name: name,
      status: status,
      conclusion: conclusion,
      branch: branch,
      event: event,
      createdAt: createdAt,
      updatedAt: updatedAt,
      url: url,
      jobs: jobs ?? this.jobs,
    );
  }

  factory WorkflowRunModel.fromJson(Map<String, dynamic> json) {
    return WorkflowRunModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unnamed workflow',
      status: json['status'] as String? ?? 'unknown',
      conclusion: json['conclusion'] as String?,
      branch: json['head_branch'] as String? ?? '',
      event: json['event'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      url: json['html_url'] as String? ?? '',
    );
  }
}

class WorkflowJobModel {
  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String url;

  WorkflowJobModel({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.startedAt,
    required this.completedAt,
    required this.url,
  });

  factory WorkflowJobModel.fromJson(Map<String, dynamic> json) {
    return WorkflowJobModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unnamed job',
      status: json['status'] as String? ?? 'unknown',
      conclusion: json['conclusion'] as String?,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      url: json['html_url'] as String? ?? '',
    );
  }
}
