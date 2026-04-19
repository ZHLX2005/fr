class GithubApiException implements Exception {
  final int statusCode;
  final String message;

  GithubApiException(this.statusCode, this.message);

  @override
  String toString() => 'GithubApiException($statusCode): $message';
}
