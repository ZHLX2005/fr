/// GitHub API 异常。
///
/// 从旧 `lib/core/github/github_api_exception.dart` 迁移。
class GithubApiException implements Exception {
  final int statusCode;
  final String message;

  const GithubApiException(this.statusCode, this.message);

  @override
  String toString() => 'GithubApiException($statusCode): $message';
}
