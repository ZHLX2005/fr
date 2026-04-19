import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_actions_models.dart';
import 'github_api_exception.dart';

class GithubActionsService {
  final String owner;
  final String repo;
  final String token;

  GithubActionsService({
    required this.owner,
    required this.repo,
    required this.token,
  });

  String get _apiBase => 'https://api.github.com/repos/$owner/$repo';

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<List<WorkflowRunModel>> listLatestWorkflowRuns({
    int perPage = 3,
  }) async {
    final uri = Uri.parse(
      '$_apiBase/actions/runs',
    ).replace(queryParameters: {'per_page': '$perPage'});
    final response = await http.get(uri, headers: _headers);
    _checkError(response);
    final payload = json.decode(response.body) as Map<String, dynamic>;
    return (payload['workflow_runs'] as List<dynamic>? ?? const [])
        .map((e) => WorkflowRunModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<WorkflowJobModel>> listRunJobs(int runId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/actions/runs/$runId/jobs'),
      headers: _headers,
    );
    _checkError(response);
    final payload = json.decode(response.body) as Map<String, dynamic>;
    return (payload['jobs'] as List<dynamic>? ?? const [])
        .map((e) => WorkflowJobModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<WorkflowRunModel>> listLatestWorkflowRunsWithJobs({
    int perPage = 3,
  }) async {
    final runs = await listLatestWorkflowRuns(perPage: perPage);
    final result = <WorkflowRunModel>[];
    for (final run in runs) {
      final jobs = await listRunJobs(run.id);
      result.add(run.copyWith(jobs: jobs));
    }
    return result;
  }

  void _checkError(http.Response response) {
    if (response.statusCode >= 400) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final body = json.decode(response.body) as Map<String, dynamic>;
        message = body['message'] as String? ?? message;
      } catch (_) {}
      throw GithubApiException(response.statusCode, message);
    }
  }
}
