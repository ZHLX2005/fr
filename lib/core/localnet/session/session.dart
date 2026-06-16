import 'dart:async';
import 'package:flutter/foundation.dart';
import '../channel/channel_manager.dart';
import '../channel/channel_message.dart';
import 'state_serializer.dart';

/// A Session manages automatic state synchronization between two paired devices.
///
/// Use [LanFramework.createSession] to create a session. Once created,
/// any changes to the [state] object (which must extend [Listenable]) will
/// automatically be serialized and sent to the peer device. Incoming updates
/// from the peer are automatically deserialized and applied to the local state.
///
/// Example usage for a chess game:
/// ```dart
/// final game = ChessGame();
/// final session = framework.createSession(
///   peerId: opponentDeviceId,
///   state: game,
///   serializer: ChessGameSerializer(),
/// );
///
/// // Set up UI refresh callback
/// session.onChanged = () => renderBoard(game.board);
///
/// // Make a move - automatically synced to opponent
/// game.move('e2', 'e4');
/// ```
///
/// The session handles:
/// - Monitoring state changes via [Listenable.addListener]
/// - Batching rapid changes into a single sync (microtask scheduling)
/// - Serializing state changes using the provided [StateSerializer]
/// - Sending updates via [ChannelManager.sendTo]
/// - Receiving and deserializing incoming updates
/// - Preventing sync loops (remote updates don't trigger re-send)
///
/// When done, call [dispose] to clean up resources.
///
/// **State Requirements:**
/// - Must extend [Listenable] (e.g., [ChangeNotifier])
/// - Must be serializable by the provided serializer
/// - For V1: Deserializer should update state in place (target parameter)
///
/// **Thread Safety:**
/// This class is not thread-safe. Use from the main isolate only.
///
/// See also:
/// - [StateSerializer] for serialization interface
/// - [JsonStateSerializer] for default JSON implementation
/// - [SessionManager] for lifecycle management
class Session<StateT extends Listenable> {
  Session({
    required this.peerId,
    required this.state,
    required ChannelManager channelManager,
    required StateSerializer<StateT> serializer,
    this.channelName,
  })  : _channelManager = channelManager,
        _serializer = serializer {
    _startMonitoring();
  }

  final String peerId;
  final StateT state;
  final ChannelManager _channelManager;
  final StateSerializer<StateT> _serializer;

  /// 自定义 channel 名（双端 Session 同步时使用固定 channel）
  final String? channelName;

  /// Callback for UI refresh when state changes
  void Function()? onChanged;

  /// Loop suppression flag to prevent re-triggering sync when applying remote updates
  bool _suppressSync = false;

  /// Unique channel ID for this session
  String get _sessionChannel =>
      channelName ?? 'session/${peerId}_${state.hashCode}';

  StreamSubscription<ChannelMessage>? _channelSub;
  Timer? _syncTimer;

  void _startMonitoring() {
    // Monitor state changes
    state.addListener(_onStateChanged);

    // Subscribe to incoming messages
    _channelSub = _channelManager.watchChannel(_sessionChannel).listen(_onMessage);
  }

  void _onStateChanged() {
    if (_suppressSync) return;

    // Cancel existing timer to batch rapid changes
    _syncTimer?.cancel();
    _syncTimer = Timer(Duration.zero, () async {
      final data = _serializer.serialize(state);
      await _channelManager.sendTo(peerId, _sessionChannel, data);
    });
  }

  void _onMessage(ChannelMessage msg) {
    _suppressSync = true;
    try {
      // Serializer updates `state` in place (target parameter)
      _serializer.deserialize(msg.payload, state);
      onChanged?.call();
    } finally {
      _suppressSync = false;
    }
  }

  /// Manually trigger full sync
  Future<void> syncFull() async {
    final data = _serializer.serialize(state);
    await _channelManager.sendTo(peerId, _sessionChannel, data);
  }

  /// Destroy session
  Future<void> dispose() async {
    await _channelSub?.cancel();
    _syncTimer?.cancel();
    state.removeListener(_onStateChanged);
  }
}
