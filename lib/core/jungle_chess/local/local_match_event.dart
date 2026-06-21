// lib/core/jungle_chess/local/local_match_event.dart
import '../models/piece.dart';

sealed class LocalMatchEvent {
  const LocalMatchEvent();
}

final class LocalStartPressed extends LocalMatchEvent {
  const LocalStartPressed();
}

final class LocalMoveCommitted extends LocalMatchEvent {
  final Coord from;
  final Coord to;
  const LocalMoveCommitted({required this.from, required this.to});
}

final class LocalUndoRequested extends LocalMatchEvent {
  const LocalUndoRequested();
}

final class LocalResetRequested extends LocalMatchEvent {
  const LocalResetRequested();
}

final class LocalExitRequested extends LocalMatchEvent {
  const LocalExitRequested();
}
