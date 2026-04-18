import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_api_exception.dart';
import 'github_issues_models.dart';

class GithubIssuesService {
  final String owner;
  final String repo;
  final String token;

  GithubIssuesService({
    required this.owner,
    required this.repo,
    required this.token,
  });

  String get _apiBase => 'https://api.github.com/repos/$owner/$repo/issues';

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<IssueModel> createIssue(CreateIssueRequest request) async {
    final response = await http.post(
      Uri.parse(_apiBase),
      headers: _headers,
      body: json.encode(request.toJson()),
    );
    _checkError(response);
    return IssueModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<IssueModel>> listIssues({
    String state = 'open',
    int perPage = 50,
    int page = 1,
  }) async {
    final uri = Uri.parse(_apiBase).replace(
      queryParameters: {
        'state': state,
        'per_page': '$perPage',
        'page': '$page',
      },
    );
    final response = await http.get(uri, headers: _headers);
    _checkError(response);
    final list = json.decode(response.body) as List<dynamic>;
    return list
        .map((e) => IssueModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<IssueModel> updateIssue(int number, UpdateIssueRequest request) async {
    final response = await http.patch(
      Uri.parse('$_apiBase/$number'),
      headers: _headers,
      body: json.encode(request.toJson()),
    );
    _checkError(response);
    return IssueModel.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  Future<IssueModel> closeIssue(int number) {
    return updateIssue(number, UpdateIssueRequest(state: 'closed'));
  }

  Future<IssueModel> reopenIssue(int number) {
    return updateIssue(number, UpdateIssueRequest(state: 'open'));
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
