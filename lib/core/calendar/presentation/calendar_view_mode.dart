enum CalendarViewMode {
  list('列表'),
  year('年'),
  month('月'),
  week('周'),
  threeDay('3日'),
  day('日');

  const CalendarViewMode(this.label);
  final String label;
}
