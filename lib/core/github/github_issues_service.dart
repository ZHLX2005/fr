// GitHub Issues API Service
// 独立 Service，支持完整 CRUD 操作

import 'dart:convert';
import 'package:http/http.dart' as http;
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

  // ============================================================
  // C - Create Issue
  // ============================================================
  Future<IssueModel> createIssue(CreateIssueRequest request) async {
    final resp = await http.post(
      Uri.parse(_apiBase),
      headers: _headers,
      body: json.encode(request.toJson()),
    );
    _checkError(resp);
    final json_ = json.decode(resp.body) as Map<String, dynamic>;
    return IssueModel.fromJson(json_);
  }

  // ============================================================
  // R - List Issues
  // ============================================================
  Future<List<IssueModel>> listIssues({
    String state = 'open',
    int perPage = 50,
    int page = 1,
  }) async {
    final uri = Uri.parse(_apiBase).replace(queryParameters: {
      'state': state,
      'per_page': '$perPage',
      'page': '$page',
    });
    final resp = await http.get(uri, headers: _headers);
    _checkError(resp);
    final list = json.decode(resp.body) as List;
    return list
        .map((e) => IssueModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // R - Get Single Issue
  // ============================================================
  Future<IssueModel> getIssue(int number) async {
    final resp = await http.get(
      Uri.parse('$_apiBase/$number'),
      headers: _headers,
    );
    _checkError(resp);
    final json_ = json.decode(resp.body) as Map<String, dynamic>;
    return IssueModel.fromJson(json_);
  }

  // ============================================================
  // U - Update Issue
  // ============================================================
  Future<IssueModel> updateIssue(int number, UpdateIssueRequest request) async {
    final resp = await http.patch(
      Uri.parse('$_apiBase/$number'),
      headers: _headers,
      body: json.encode(request.toJson()),
    );
    _checkError(resp);
    final json_ = json.decode(resp.body) as Map<String, dynamic>;
    return IssueModel.fromJson(json_);
  }

  // ============================================================
  // D - Close Issue (软删除，GitHub API 不支持硬删除 Issue)
  // ============================================================
  Future<IssueModel> closeIssue(int number) async {
    return updateIssue(number, UpdateIssueRequest(state: 'closed'));
  }

  Future<IssueModel> reopenIssue(int number) async {
    return updateIssue(number, UpdateIssueRequest(state: 'open'));
  }

  // ============================================================
  // Labels 管理
  // ============================================================
  Future<IssueModel> addLabels(int number, List<String> labels) async {
    return updateIssue(number, UpdateIssueRequest(labels: labels));
  }

  // ============================================================
  // 错误处理
  // ============================================================
  void _checkError(http.Response resp) {
    if (resp.statusCode >= 400) {
      String msg = 'HTTP ${resp.statusCode}';
      try {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        msg = body['message'] as String? ?? msg;
      } catch (_) {}
      throw GithubApiException(resp.statusCode, msg);
    }
  }
}

class GithubApiException implements Exception {
  final int statusCode;
  final String message;

  GithubApiException(this.statusCode, this.message);

  @override
  String toString() => 'GithubApiException($statusCode): $message';
}
