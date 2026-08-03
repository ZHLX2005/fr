import 'const_recorder.dart';
import 'recording_file.dart';

/// `rec_2026-08-03T14-22-33.aac` → DateTime(2026,8,3,14,22,33)。
/// 解析失败(外部导入 / 手工改名)返回 null。
final _createdAtPattern = RegExp(
  r'^rec_(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})\.aac$',
);

DateTime? parseRecordCreatedAt(String fileName) {
  final m = _createdAtPattern.firstMatch(fileName);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}

/// CBR AAC 时长估算 = sizeBytes * 8 / bitRate。
/// 本 app 固定 128kbps 录音,误差 <1%;O(1) 同步,零 I/O。
Duration estimateAacDuration(int sizeBytes,
    {int bitRate = RecorderDefaults.bitRate}) {
  return Duration(milliseconds: sizeBytes * 8000 ~/ bitRate);
}

/// 列表排序方式。
enum RecordingSort { timeDesc, timeAsc, nameAsc, nameDesc, sizeDesc, sizeAsc }

/// 按 [RecordingSort] 排序,返回新列表(不修改入参)。
List<RecordingFile> sortFiles(List<RecordingFile> files, RecordingSort sort) {
  final result = List<RecordingFile>.of(files);
  switch (sort) {
    case RecordingSort.timeDesc:
      result.sort((a, b) => b.displayTime.compareTo(a.displayTime));
    case RecordingSort.timeAsc:
      result.sort((a, b) => a.displayTime.compareTo(b.displayTime));
    case RecordingSort.nameAsc:
      result.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case RecordingSort.nameDesc:
      result.sort((a, b) =>
          b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    case RecordingSort.sizeDesc:
      result.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    case RecordingSort.sizeAsc:
      result.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
  }
  return result;
}

/// 按 [RecordingFile.displayTime] 分相对日期桶:今天 / 昨天 / 更早。
///
/// 返回有序 [(标签, 文件)] 段,空桶省略。排序与分组都在 UI 层(纯函数),
/// 不动 [RecordingFile] 之外的接口。
List<(String, List<RecordingFile>)> groupFilesByRelativeDay(
    List<RecordingFile> files) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final buckets = <String, List<RecordingFile>>{};
  for (final f in files) {
    final d = f.displayTime;
    final day = DateTime(d.year, d.month, d.day);
    final label = day == today ? '今天' : (day == yesterday ? '昨天' : '更早');
    buckets.putIfAbsent(label, () => []).add(f);
  }
  const order = ['今天', '昨天', '更早'];
  return [
    for (final label in order)
      if (buckets.containsKey(label)) (label, buckets[label]!),
  ];
}
