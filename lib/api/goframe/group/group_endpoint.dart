import '../../api_client.dart';
import '../../api_response.dart';

/// 工作空间（group）端点 —— 查询我的工作空间。
class GroupEndpoint {
  final ApiClient _client;

  GroupEndpoint(this._client);

  /// 我的工作空间列表（我创建 + 我加入）。返回 ApiResponse，调用方判 isSuccess。
  Future<ApiResponse<List<KvGroup>>> list() => _client.request<List<KvGroup>>(
        method: 'GET',
        path: '/api/v1/groups',
        fromJson: (json) => (json['groups'] as List<dynamic>? ?? const [])
            .map((e) => KvGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 工作空间模型。
class KvGroup {
  final int id;
  final String name;
  final String description;
  final String myRole;
  final int memberCount;

  const KvGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.myRole = '',
    this.memberCount = 0,
  });

  factory KvGroup.fromJson(Map<String, dynamic> json) => KvGroup(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        myRole: json['myRole'] as String? ?? '',
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      );
}
