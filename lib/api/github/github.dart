/// GitHub REST API — Actions、Issues。
///
/// 使用方式：
/// ```dart
/// final gh = GithubEndpoint(apiClient, token: 'ghp_xxx');
/// final run = await gh.actions.listRuns(owner: '...', repo: '...');
/// ```
library;

export 'github_config.dart';
export 'github_exception.dart';
export 'actions/actions.dart';
export 'issues/issues.dart';
