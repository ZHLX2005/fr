import 'dart:async';
import 'package:flutter/foundation.dart';

import '../channel/channel_manager.dart';
import 'session.dart';
import 'state_serializer.dart';

/// Manages Session lifecycle
class SessionManager {
  SessionManager({
    required ChannelManager channelManager,
  }) : _channelManager = channelManager;

  final ChannelManager _channelManager;
  final Map<String, Session> _sessions = {};

  /// Create a new Session
  Session<S> create<S extends Listenable>({
    required String peerId,
    required S state,
    required StateSerializer<S> serializer,
    String? channelName,
  }) {
    final session = Session<S>(
      peerId: peerId,
      state: state,
      channelManager: _channelManager,
      serializer: serializer,
      channelName: channelName,
    );

    final key = _sessionKey(peerId, state);
    _sessions[key] = session;

    return session;
  }

  /// Get current session count
  int get sessionCount => _sessions.length;

  /// Dispose all sessions
  Future<void> disposeAll() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();

    for (final session in sessions) {
      await session.dispose();
    }
  }

  /// Dispose this manager
  Future<void> dispose() async {
    await disposeAll();
  }

  String _sessionKey(String peerId, dynamic state) {
    return '$peerId:${state.hashCode}';
  }
}
