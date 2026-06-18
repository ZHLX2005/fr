/// State serialization interface
abstract class StateSerializer<StateT> {
  /// Serialize state to Map for network transmission
  Map<String, dynamic> serialize(StateT state);

  /// Deserialize Map and apply to target state
  StateT deserialize(Map<String, dynamic> data, StateT target);
}

/// JSON-based serializer with custom conversion functions.
///
/// **In-place contract:** `fromJson` MUST update the [target] argument in place
/// and return it. The [Session] layer relies on this — it ignores the return
/// value of [deserialize] and expects the existing state object to be mutated,
/// not replaced. This keeps the live `state` reference (and its `ChangeNotifier`
/// listeners) stable across remote updates.
class JsonStateSerializer<StateT> implements StateSerializer<StateT> {
  JsonStateSerializer({
    required this.toJson,
    required this.fromJson,
  });

  final Map<String, dynamic> Function(StateT) toJson;
  final StateT Function(Map<String, dynamic>, StateT target) fromJson;

  @override
  Map<String, dynamic> serialize(StateT state) => toJson(state);

  @override
  StateT deserialize(Map<String, dynamic> data, StateT target) => fromJson(data, target);
}
