import 'dart:convert';
import 'package:http/http.dart' as http;
import '../github_config.dart';
import '../github_exception.dart';
import 'actions_models.dart';

/// GitHub Actions API 端点。
///
/// GitHub API 不走统一拦截器链（baseUrl 不同），自持 http.Client。
class GithubActionsEndpoint {
  final String token;
  final http.Client _client;

  GithubActionsEndpoint({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Accept': GithubConfig.acceptHeader,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': GithubConfig.version,
      };

  /// 列出最近 workflow runs。
  Future<List<WorkflowRunModel>> listRuns({
    required String owner,
    required String repo,
    int perPage = 3,
  }) async {
    final uri = Uri.parse(
      '${GithubConfig.baseUrl}/repos/$owner/$repo/actions/runs',
    ).replace(queryParameters: {'per_page': '$perPage'});
    final response = await _client.get(uri, headers: _headers);
    _checkError(response);
    final payload = json.decode(response.body) as Map<String, dynamic>;
    return (payload['workflow_runs'] as List<dynamic>?)
            ?.map((e) => WorkflowRunModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
  }

  /// 列出 run 的 jobs。
  Future<List<WorkflowJobModel>> listJobs({
    required String owner,
    required String repo,
    required int runId,
  }) async {
    final response = await _client.get(
      Uri.parse('${GithubConfig.baseUrl}/repos/$owner/$repo/actions/runs/$runId/jobs'),
      headers: _headers,
    );
    _checkError(response);
    final payload = json.decode(response.body) as Map<String, dynamic>;
    return (payload['jobs'] as List<dynamic>?)
            ?.map((e) => WorkflowJobModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
  }

  /// 一次调用获取 runs + 各自的 jobs。
  Future<List<WorkflowRunModel>> listRunsWithJobs({
    required String owner,
    required String repo,
    int perPage = 3,
  }) async {
    final runs = await listRuns(owner: owner, repo: repo, perPage: perPage);
    final result = <WorkflowRunModel>[];
    for (final run in runs) {
      final jobs = await listJobs(owner: owner, repo: repo, runId: run.id);
      result.add(run.copyWith(jobs: jobs));
    }
    return result;
  }

  void dispose() => _client.close();

  static void _checkError(http.Response response) {
    if (response.statusCode >= 400) {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final body = json.decode(response.body) as Map<String, dynamic>;
        msg = body['message'] as String? ?? msg;
      } catch (_) {}
      throw GithubApiException(response.statusCode, msg);
    }
  }
}
