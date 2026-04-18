import 'dart:math' as math;

import 'doubletime_models.dart';

DateTime floorToHour(DateTime dt) =>
    DateTime(dt.year, dt.month, dt.day, dt.hour);

DateTime ceilToHour(DateTime dt) {
  final floored = floorToHour(dt);
  if (floored.isAtSameMomentAs(dt)) {
    return dt;
  }
  return floored.add(const Duration(hours: 1));
}

int _overlapMinutes(DateTime start, DateTime end, DateTime cellStart) {
  final cellEnd = cellStart.add(const Duration(hours: 1));
  final overlapStart = start.isAfter(cellStart) ? start : cellStart;
  final overlapEnd = end.isBefore(cellEnd) ? end : cellEnd;
  return math.max(0, overlapEnd.difference(overlapStart).inMinutes);
}

List<DoubleTimeHourAllocation> mapEventToHourCells(DoubleTimeEvent event) {
  final begin = floorToHour(event.start);
  final endCeil = ceilToHour(event.end);
  final result = <DoubleTimeHourAllocation>[];

  for (
    var cell = begin;
    cell.isBefore(endCeil);
    cell = cell.add(const Duration(hours: 1))
  ) {
    final minutes = _overlapMinutes(event.start, event.end, cell);
    if (minutes == 0) {
      continue;
    }
    result.add(
      DoubleTimeHourAllocation(
        cellStart: cell,
        ratio: minutes / 60.0,
        eventId: event.id,
        colorArgb: event.colorArgb,
        title: event.title,
      ),
    );
  }

  return result;
}

Map<DoubleTimeLane, Map<DateTime, List<DoubleTimeHourAllocation>>> mapAllEvents(
  List<DoubleTimeEvent> events,
) {
  final result =
      <DoubleTimeLane, Map<DateTime, List<DoubleTimeHourAllocation>>>{
        DoubleTimeLane.plan: <DateTime, List<DoubleTimeHourAllocation>>{},
        DoubleTimeLane.actual: <DateTime, List<DoubleTimeHourAllocation>>{},
      };

  for (final event in events) {
    final mapped = mapEventToHourCells(event);
    final laneMap = result[event.lane]!;
    for (final allocation in mapped) {
      laneMap.putIfAbsent(
        allocation.cellStart,
        () => <DoubleTimeHourAllocation>[],
      );
      laneMap[allocation.cellStart]!.add(allocation);
    }
  }

  return result;
}

List<DoubleTimeStackedSlice> stackCell(
  List<DoubleTimeHourAllocation> allocations,
) {
  var cursor = 0.0;
  final slices = <DoubleTimeStackedSlice>[];

  for (final allocation in allocations) {
    if (cursor >= 1) {
      break;
    }
    final next = math.min(1.0, cursor + allocation.ratio);
    slices.add(
      DoubleTimeStackedSlice(
        start: cursor,
        end: next,
        colorArgb: allocation.colorArgb,
        title: allocation.title,
        eventId: allocation.eventId,
      ),
    );
    cursor = next;
  }

  return slices;
}
