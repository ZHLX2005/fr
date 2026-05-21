/// 音符类型
enum NoteType { tap, hold, slide }

/// 滑动方向
enum SlideDirection { up, down, left, right }

/// 谱面音符事件（不可变）
class NoteEvent {
  final int time; // ms，音符到达判定线的时间
  final int column; // 0/1/2
  final NoteType type;
  final SlideDirection? direction; // 仅 slide
  final int? holdDuration; // 仅 hold，ms

  const NoteEvent({
    required this.time,
    required this.column,
    required this.type,
    this.direction,
    this.holdDuration,
  });

  factory NoteEvent.fromJson(Map<String, dynamic> json) {
    return NoteEvent(
      time: json['time'] as int,
      column: json['column'] as int,
      type: NoteType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NoteType.tap,
      ),
      direction: json['direction'] != null
          ? SlideDirection.values.firstWhere(
              (e) => e.name == json['direction'],
              orElse: () => SlideDirection.up,
            )
          : null,
      holdDuration: json['holdDuration'] as int?,
    );
  }
}
