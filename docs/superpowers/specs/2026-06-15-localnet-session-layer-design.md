# Localnet Session Layer Design

**Date:** 2026-06-15
**Status:** Draft
**Context:** Adding universal session abstraction to localnet framework

## Problem Statement

Currently, localnet provides message passing primitives (`sendTo()` / `watchChannel()`) but requires business code to manually handle state synchronization. For each application (chess, whiteboard, collaborative editor), developers must:

1. Manually call `sendTo()` when state changes
2. Manually deserialize received messages
3. Manually apply updates to local state
4. Manually trigger UI refresh

This repetitive pattern couples business logic with network communication details.

## Proposed Solution

Introduce a **Session layer** that automatically synchronizes state between paired devices. Business code only needs to modify the local state object; synchronization happens transparently.

### Architecture Position

```
┌─────────────────────────────────────┐
│          Business Layer            │
│  session.state.move('e2', 'e4')   │
├─────────────────────────────────────┤
│          Session Layer (NEW)        │
│  - Monitors state changes           │
│  - Serializes + sends automatically  │
│  - Deserializes + applies on receive │
├─────────────────────────────────────┤
│        ChannelManager (unchanged)   │
│    sendTo() / watchChannel()        │
├─────────────────────────────────────┤
│        Transport Layer (unchanged)   │
└─────────────────────────────────────┘
```

**Key Principle:** ChannelManager and Transport layers remain unchanged. Session is purely an upper-layer consumer.

## API Design

### Public API

```dart
class LanFramework {
  /// Create a session for automatic state synchronization
  Session<S> createSession<S extends Listenable>({
    required String peerId,
    required S state,
    StateSerializer<S>? serializer,
  });
}

class Session<StateT extends Listenable> {
  final String peerId;
  final StateT state;

  /// Callback for UI refresh when state changes
  void Function()? onChanged;

  /// Manually trigger full sync
  Future<void> syncFull();

  /// Destroy session
  Future<void> dispose();
}
```

### Usage Example (Chess)

```dart
// Before: Manual synchronization
game.move('e2', 'e4');
framework.sendTo(B_id, 'chess', game.toJson());

framework.watchChannel('chess').listen((msg) {
  game.applyMove(msg.payload['from'], msg.payload['to']);
  renderBoard();
});

// After: Automatic synchronization
final session = framework.createSession(
  peerId: B_id,
  state: ChessGame(),  // extends ChangeNotifier
);

session.onChanged = () => renderBoard(session.state.board);

// That's it - state modifications auto-sync
game.move('e2', 'e4');
```

## Internal Flow

### Write Path (Local Change → Remote)

```
state.move('e2', 'e4')
  │
  ├─ ChangeNotifier triggered
  │
  ├─ [Microtask aggregation]
  │     (Multiple changes in same frame batched)
  │
  ├─ session._onStateChanged()
  │     │
  │     ├─ serializer.serialize(state) → Map
  │     │
  │     └─ channelManager.sendTo(peerId, sessionChannel, serializedData)
  │              │
  │           ┌──┴──┐
  │        HttpTransport
  │        POST /channel/<sessionId>
  │           └─────┘
```

### Read Path (Remote Message → Local Update)

```
ChannelManager receives message
  │
  ├─ ChannelMessageEvent emitted
  │     │
  │     ├─ session._onMessage()
  │          │
  │          ├─ serializer.deserialize(data, state)
  │          │     │
  │          │     └─ Local state updated (with loop suppression flag)
  │          │
  │          └─ ChangeNotifier triggered → onChanged callback → UI refresh
```

### Loop Prevention

When applying remote updates to local state, a `_suppressSync` flag prevents re-triggering synchronization:

```dart
void _onMessage(ChannelMessage msg) {
  _suppressSync = true;
  try {
    final newData = _serializer.deserialize(msg.payload, state);
    _updateState(newData);
  } finally {
    _suppressSync = false;
  }
}
```

## Serialization Strategy

### Pluggable Serializer Interface

```dart
abstract class StateSerializer<StateT> {
  Map<String, dynamic> serialize(StateT state);
  StateT deserialize(Map<String, dynamic> data, StateT target);
}
```

### Default Implementation

Framework provides JSON-based default serializer. Users can inject custom serializers:

```dart
// Use default
framework.createSession(peerId: B, state: game);

// Custom binary serializer
framework.createSession(
  peerId: B,
  state: game,
  serializer: MyBinarySerializer(),
);
```

### Serialization Format

**V1 (MVP):** Full state serialization on every change

- Simple: serialize entire state
- Sufficient for small states (chess board = 64 squares)
- Easy debugging: inspect JSON payload

**Future V2:** Delta transmission (extension point预留)

- Track changed fields via ChangeNotifier
- Send only modified fields
- Transparent to business code

## Implementation Changes

### New Files

```
lib/core/localnet/session/
├── session.dart              (~100 lines)
│   - Session class
│   - State monitoring, send/receive logic
│
├── session_manager.dart      (~50 lines)
│   - Session lifecycle management
│   - Channel assignment and cleanup
│
└── state_serializer.dart     (~30 lines)
    - StateSerializer interface
    - Default JSON implementation
```

### Modified Files

**`framework_core.dart`** (+5 lines)

```dart
class FrameworkCore {
  late final SessionManager sessionManager;

  Future<void> start() async {
    // ... existing initialization ...

    sessionManager = SessionManager(
      channelManager: channelManager,
      eventBus: eventBus,
    );
  }

  Future<void> stop() async {
    await sessionManager.dispose();
    // ... existing cleanup ...
  }
}
```

**`lan_framework.dart`** (+8 lines)

```dart
class LanFramework {
  Session<S> createSession<S extends Listenable>({
    required String peerId,
    required S state,
    StateSerializer<S>? serializer,
  }) {
    _assertRunning();
    return _core!.sessionManager.create(
      peerId: peerId,
      state: state,
      serializer: serializer ?? _defaultSerializer(state),
    );
  }
}
```

**Unchanged Files:**
- `ChannelManager` - No changes
- `DeviceManager` - No changes
- `ConnectionManager` - No changes
- All `Transport` classes - No changes
- All event types - No changes

## Session Lifecycle

```
framework.createSession(...)
  │
  ├─ SessionManager registers session
  ├─ Session starts monitoring state (ChangeNotifier subscription)
  └─ Session subscribes to channel for incoming messages
      │
      ├── session.dispose()
      │     │
      │     ├─ Cancel state monitoring subscription
      │     ├─ Cancel channel message subscription
      │     ├─ Optional: send "session closed" notification
      │     └─ SessionManager unregisters session
      │
      └── framework.dispose()
            │
            └─ SessionManager.disposeAll() ← Batch cleanup
```

## Design Decisions

### 1. ChangeNotifier over Command Dispatch

**Choice:** Use `ChangeNotifier` for state observation

**Rationale:**
- Minimal API surface change for existing code
- Most Dart UI frameworks already use ChangeNotifier
- Direct state manipulation feels more natural than dispatching commands

**Trade-off:**
- Current implementation sends full state (not deltas)
- Mitigation: Microtask batching reduces redundant sends

### 2. sendTo() Remains Public

**Decision:** Keep `sendTo()` / `watchChannel()` as public framework APIs alongside Session

**Rationale:**
- `sendTo()` is a communication primitive (like HTTP POST), not business logic
- Some scenarios (chat, one-off notifications) don't fit state sync model
- Users can choose: Session for state, sendTo for messages

### 3. Conflict Resolution: Deferred

**Scope:** Initial version does NOT include conflict resolution

**Rationale:**
- Chess/gaming scenarios are naturally turn-based (no concurrent conflicts)
- Defers complexity (CRDT, operational transform) to future iterations
- Interface will预留 ConflictResolver hook for advanced users

## Testing Strategy

1. **Unit Tests**
   - Session state monitoring
   - Serialize/deserialize round-trip
   - Loop prevention flag behavior

2. **Integration Tests**
   - Full send/receive cycle with mock transport
   - Multiple sessions with different peers
   - Session cleanup on dispose

3. **Scenario Tests**
   - Chess game state sync
   - Rapid state changes (batching verification)

## Open Questions

1. **Session Channel Naming:** Auto-generated vs user-specified?
   - **Current:** SessionManager auto-assigns unique channel ID
   - **Rationale:** Prevents collision, simpler API

2. **Reconnection Behavior:** Session auto-recovery vs manual?
   - **Decision:** Session automatically resyncs full state when peer reconnects
   - **Framework provides:** `Session.onReconnected` callback for user hooks

3. **State Validation:** Trust remote updates or validate?
   - **Current:** Trust (no validation)
   - **Future:** Optional validator callback parameter

## Success Criteria

- [ ] Business code can sync state with single `createSession()` call
- [ ] No changes required to ChannelManager/Transport layers
- [ ] Tests cover full round-trip synchronization
- [ ] Documentation includes migration guide from manual sendTo/watchChannel
- [ ] Performance: sync completes within 50ms for chess-sized state

## Future Extensions

### V2: Delta Transmission
- Track changed fields automatically
- Send only modified fields
- Transparent to existing Session API

### V3: Conflict Resolution
- Pluggable ConflictResolver interface
- Built-in strategies: LWW, Token-passing
- Optional CRDT support

### V4: Multi-party Sessions
- Extend Session from 1:1 to 1:N
- Room/conference abstractions
- Membership change events

---

## Appendix: Code Sketch

```dart
// lib/core/localnet/session/session.dart

class Session<StateT extends Listenable> {
  Session._({
    required this.peerId,
    required this.state,
    required ChannelManager channelManager,
    required StateSerializer<StateT> serializer,
  }) : _channelManager = channelManager,
       _serializer = serializer {
    _startMonitoring();
  }

  final String peerId;
  final StateT state;
  final ChannelManager _channelManager;
  final StateSerializer<StateT> _serializer;

  void Function()? onChanged;
  bool _suppressSync = false;
  StreamSubscription? _stateSub;
  StreamSubscription? _channelSub;

  void _startMonitoring() {
    // Monitor state changes
    state.addListener(_onStateChanged);

    // Subscribe to incoming messages
    _channelSub = _channelManager
        .watchChannel(_sessionChannel)
        .listen(_onMessage);
  }

  void _onStateChanged() {
    if (_suppressSync) return;

    // Schedule for next microtask (batching)
    Future.microtask(() async {
      final data = _serializer.serialize(state);
      await _channelManager.sendTo(peerId, _sessionChannel, data);
    });
  }

  void _onMessage(ChannelMessage msg) {
    _suppressSync = true;
    try {
      final newData = _serializer.deserialize(msg.payload, state);
      _updateState(newData);
      onChanged?.call();
    } finally {
      _suppressSync = false;
    }
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _channelSub?.cancel();
    state.removeListener(_onStateChanged);
  }
}
```
