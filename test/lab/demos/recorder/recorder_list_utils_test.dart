import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_list_utils.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recording_file.dart';

RecordingFile _f(
  String name,
  DateTime modified, {
  int size = 1024,
  DateTime? createdAt,
  Duration? duration,
  bool exact = false,
}) {
  return RecordingFile(
    path: '/x/$name',
    name: name,
    sizeBytes: size,
    lastModified: modified,
    createdAt: createdAt,
    duration: duration,
    durationExact: exact,
  );
}

void main() {
  group('parseRecordCreatedAt', () {
    test('标准文件名解析出创建时间', () {
      expect(
        parseRecordCreatedAt('rec_2026-08-03T14-22-33.aac'),
        DateTime(2026, 8, 3, 14, 22, 33),
      );
    });

    test('非标准文件名返回 null(外部导入/手工改名)', () {
      expect(parseRecordCreatedAt('我的录音.aac'), isNull);
      expect(parseRecordCreatedAt('rec_2026-08-03T14-22-33'), isNull);
      expect(parseRecordCreatedAt('rec_x.aac'), isNull);
    });
  });

  group('estimateAacDuration', () {
    test('固定 128kbps:1MB ≈ 65s', () {
      final d = estimateAacDuration(1048576);
      expect(d.inSeconds, greaterThan(60));
      expect(d.inSeconds, lessThan(70));
    });

    test('bitRate 参数可覆盖', () {
      // 1s 的数据量 = 16000 bytes @ 128000bps
      final d = estimateAacDuration(16000, bitRate: 128000);
      expect(d.inMilliseconds, closeTo(1000, 50));
    });

    test('0 字节 → 0 时长', () {
      expect(estimateAacDuration(0), Duration.zero);
    });
  });

  group('sortFiles', () {
    final base = DateTime(2026, 8, 3, 12);
    final files = [
      _f('b.aac', base.subtract(const Duration(hours: 2)), size: 3000),
      _f('A.aac', base, size: 1000),
      _f('c.aac', base.subtract(const Duration(hours: 1)), size: 2000),
    ];

    test('timeDesc:最新在前(默认)', () {
      final r = sortFiles(files, RecordingSort.timeDesc);
      expect(r.map((e) => e.name).toList(), ['A.aac', 'c.aac', 'b.aac']);
    });

    test('timeAsc:最老在前', () {
      final r = sortFiles(files, RecordingSort.timeAsc);
      expect(r.map((e) => e.name).toList(), ['b.aac', 'c.aac', 'A.aac']);
    });

    test('nameAsc:大小写不敏感', () {
      final r = sortFiles(files, RecordingSort.nameAsc);
      expect(r.map((e) => e.name).toList(), ['A.aac', 'b.aac', 'c.aac']);
    });

    test('nameDesc', () {
      final r = sortFiles(files, RecordingSort.nameDesc);
      expect(r.map((e) => e.name).toList(), ['c.aac', 'b.aac', 'A.aac']);
    });

    test('sizeDesc / sizeAsc', () {
      expect(sortFiles(files, RecordingSort.sizeDesc).first.sizeBytes, 3000);
      expect(sortFiles(files, RecordingSort.sizeAsc).first.sizeBytes, 1000);
    });

    test('不修改入参列表', () {
      final copy = List.of(files);
      sortFiles(files, RecordingSort.nameAsc);
      expect(files.map((e) => e.name).toList(),
          copy.map((e) => e.name).toList());
    });
  });

  group('groupFilesByRelativeDay', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final older = today.subtract(const Duration(days: 3));

    test('今天/昨天/更早分桶且有序', () {
      final files = [
        _f('old.aac', older),
        _f('yesterday.aac', yesterday),
        _f('today.aac', today),
      ];
      final groups = groupFilesByRelativeDay(files);
      expect(groups.map((g) => g.$1).toList(), ['今天', '昨天', '更早']);
      expect(groups[0].$2.single.name, 'today.aac');
      expect(groups[1].$2.single.name, 'yesterday.aac');
      expect(groups[2].$2.single.name, 'old.aac');
    });

    test('displayTime 优先 createdAt', () {
      final files = [
        _f('created-today.aac', older,
            createdAt: today, size: 0),
        _f('no-created.aac', older, size: 0),
      ];
      final groups = groupFilesByRelativeDay(files);
      // created-today 有 createdAt=today → 归今天;no-created 无 createdAt → 归更早
      expect(groups.first.$1, '今天');
      expect(groups.first.$2.single.name, 'created-today.aac');
      expect(groups.last.$2.single.name, 'no-created.aac');
    });

    test('空桶省略', () {
      final groups = groupFilesByRelativeDay([_f('a.aac', today, size: 0)]);
      expect(groups.map((g) => g.$1).toList(), ['今天']);
    });
  });
}
