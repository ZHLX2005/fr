import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_chat_message.dart';
import '../services/api_client.dart';

/// Agent 聊天 Provider - 管理事件记录 Agent 的状态
class AgentChatProvider with ChangeNotifier {
  static const String _messagesKey = 'agent_chat_messages';
  static const String _settingsKey = 'ai_chat_settings'; // 复用 AI Chat 的设置

  List<AIChatMessage> _messages = [];
  AISettings _settings = AISettings();
  bool _isLoading = false;
  String? _error;

  List<AIChatMessage> get messages => _messages;
  AISettings get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConfigured => _settings.isConfigured;

  AgentChatProvider() {
    _loadSettings();
    _loadMessages();
  }

  // 加载设置（复用 AIChatProvider 的设置）
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_settingsKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _settings = AISettings.decode(jsonString);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载 Agent 设置失败: $e');
    }
  }

  // 加载保存的消息
  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_messagesKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _messages = AIChatMessage.decodeList(jsonString);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载 Agent 聊天消息失败: $e');
    }
  }

  // 保存消息到本地
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_messagesKey, AIChatMessage.encodeList(_messages));
    } catch (e) {
      debugPrint('保存 Agent 聊天消息失败: $e');
    }
  }

  // 发送事件并获取 Agent 响应
  Future<void> sendEvent(String eventDescription) async {
    if (!_settings.isConfigured) {
      _error = '请先配置 API Key';
      notifyListeners();
      return;
    }

    // 添加用户消息
    final userMessage = AIChatMessage.user(eventDescription);
    _messages.add(userMessage);

    // 添加 loading 消息
    final loadingMessage = AIChatMessage.loading();
    _messages.add(loadingMessage);

    _isLoading = true;
    _error = null;
    notifyListeners();

    await _saveMessages();

    try {
      // 调用后端 Event Record API
      final response = await _callEventRecordAPI(eventDescription);

      // 移除 loading 消息
      _messages.remove(loadingMessage);

      if (response != null) {
        // 添加 Agent 响应消息
        final assistantMessage = AIChatMessage.assistant(response);
        _messages.add(assistantMessage);
      } else {
        // 添加错误消息
        final errorMessage = AIChatMessage.assistant(
          '抱歉，请求失败，请检查 API Key 或网络设置',
        );
        _messages.add(errorMessage);
      }
    } catch (e) {
      // 移除 loading 消息
      _messages.remove(loadingMessage);

      final errorMessage = AIChatMessage.assistant('请求出错: $e');
      _messages.add(errorMessage);
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
    await _saveMessages();
  }

  // 调用后端 Event Record API
  Future<String?> _callEventRecordAPI(String eventDescription) async {
    try {
      final url = Uri.parse('${ApiService.baseUrl}/api/v1/ai/event/record');

      final body = {
        'apiKey': _settings.apiKey,
        'eventDescription': eventDescription,
        'db': {
          'host': _settings.dbHost,
          'port': _settings.dbPort,
          'database': _settings.dbName,
          'user': _settings.dbUser,
          'password': _settings.dbPassword,
          'type': _settings.dbType,
        },
      };

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return json['data']['content'] as String?;
        }
      }

      debugPrint(
        'Event Record API 响应: ${response.statusCode} - ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Event Record API 调用失败: $e');
      return null;
    }
  }

  // 清空聊天记录
  Future<void> clearMessages() async {
    _messages.clear();
    await _saveMessages();
    notifyListeners();
  }

  // 删除单条消息
  Future<void> deleteMessage(String id) async {
    _messages.removeWhere((m) => m.id == id);
    await _saveMessages();
    notifyListeners();
  }

  // 刷新设置（当 AIChatProvider 设置更新时调用）
  Future<void> refreshSettings() async {
    await _loadSettings();
  }
}
