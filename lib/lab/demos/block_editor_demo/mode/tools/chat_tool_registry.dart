import 'chat_tool.dart';

class ChatToolRegistry {
  final List<ChatTool> _tools = [];

  void register(ChatTool tool) => _tools.add(tool);

  List<ChatTool> get all => List.unmodifiable(_tools);

  List<ChatTool> filter(String query) {
    if (query.isEmpty) return all;
    final lower = query.toLowerCase();
    return _tools.where((t) =>
        t.id.contains(lower) ||
        t.label.contains(query) ||
        (t.description?.contains(query) ?? false),
    ).toList();
  }
}
