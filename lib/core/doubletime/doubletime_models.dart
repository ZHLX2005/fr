enum DoubleTimeLane { plan, actual }

class DoubleTimeEvent {
  final String id;
  final DoubleTimeLane lane;
  final DateTime start;
  final DateTime end;
  final int colorArgb;
  final String title;

  DoubleTimeEvent({
    required this.id,
    required this.lane,
    required this.start,
    required this.end,
    required this.colorArgb,
    required this.title,
  }) {
    if (!end.isAfter(start)) {
      throw ArgumentError('end must be after start');
    }
  }
}

class DoubleTimeHourAllocation {
  final DateTime cellStart;
  final double ratio;
  final String eventId;
  final int colorArgb;
  final String title;

  DoubleTimeHourAllocation({
    required this.cellStart,
    required this.ratio,
    required this.eventId,
    required this.colorArgb,
    required this.title,
  }) {
    if (ratio < 0 || ratio > 1) {
      throw ArgumentError('ratio must be 0..1');
    }
  }
}

class DoubleTimeStackedSlice {
  final double start;
  final double end;
  final int colorArgb;
  final String title;
  final String eventId;

  DoubleTimeStackedSlice({
    required this.start,
    required this.end,
    required this.colorArgb,
    required this.title,
    required this.eventId,
  });
}
