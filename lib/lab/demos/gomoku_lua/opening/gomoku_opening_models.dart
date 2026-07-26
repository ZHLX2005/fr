import '../engine.dart' show GomokuMove;

class GomokuOpeningCase {
  const GomokuOpeningCase({
    required this.id,
    required this.title,
    required this.tagline,
    required this.moves,
    required this.stepNotes,
  });

  final String id;
  final String title;
  final String tagline;
  final List<GomokuMove> moves;
  final List<String> stepNotes;

  String noteAt(int step) => step <= 0 ? tagline : stepNotes[step - 1];
}

class GomokuOpeningPlayerState {
  const GomokuOpeningPlayerState({this.step = 0, this.autoPlaying = false});
  final int step;
  final bool autoPlaying;

  GomokuOpeningPlayerState copyWith({int? step, bool? autoPlaying}) =>
      GomokuOpeningPlayerState(
        step: step ?? this.step,
        autoPlaying: autoPlaying ?? this.autoPlaying,
      );
}
