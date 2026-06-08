import 'dart:convert';
import 'package:http/http.dart' as http;
import '../github_config.dart';
import '../github_exception.dart';
import 'issues_models.dart';

/// GitHub Issues API 端点。
class GithubIssuesEndpoint {
  final String token;
  final http.Client _client;

  GithubIssuesEndpoint({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Accept': GithubConfig.acceptHeader,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': GithubConfig.version,
      };

  String _apiBase(String owner, String repo) =>
      '${GithubConfig.baseUrl}/repos/$owner/$repo/issues';

  Future<IssueModel> create({
    required String owner,
    required String repo,
    required CreateIssueRequest request,
  }) async {
    final response = await http.post(
      Uri.parse(_apiBase(owner, repo)),
      headers: _headers,
      body: json.encode(request.toJson()),
    );
    _checkError(response);
    return IssueModel.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<List<IssueModel>> list({
    required String owner,
    required String repo,
    String state = 'open',
    int perPage = 50,
    int page = 1,
  }) async {
    final uri = Uri.parse(_apiBase(owner, repo)).replace(queryParameters: {
      'state': state,
      'per_page': '$perPage',
      'page': '$page',
    });
    final response = await http.get(uri, headers: _headers);
    _checkError(response);
    return (json.decode(response.body) as List<dynamic>)
        .map((e) => IssueModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<IssueModel> update({
    required String owner,
    required String repo,
    required int number,
    required UpdateIssueRequest request,
  }) async {
    final response = await http.patch(
      Uri.parse('${_apiBase(owner, repo)}/$number'),
      headers: _headers,
      body: json.encode(request.toJson()),
    );
    _checkError(response);
    return IssueModel.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<IssueModel> close({
    required String owner,
    required String repo,
    required int number,
  }) =>
      update(owner: owner, repo: repo, number: number, request: UpdateIssueRequest(state: 'closed'));

  Future<IssueModel> reopen({
    required String owner,
    required String repo,
    required int number,
  }) =>
      update(owner: owner, repo: repo, number: number, request: UpdateIssueRequest(state: 'open'));

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
