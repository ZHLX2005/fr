import 'package:hive_flutter/hive_flutter.dart';
import 'body_record.dart';

class BodyRecordRepo {
  static const String _boxName = 'body_records';
  late Box<BodyRecord> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(BodyRecordAdapter());
    }
    _box = await Hive.openBox<BodyRecord>(_boxName);
    _initialized = true;
  }

  List<BodyRecord> getRecords(String partId) {
    return _box.values
        .where((r) => r.bodyPartId == partId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<BodyRecord> getAll() => _box.values.toList();

  Future<void> add(String partId, String content, int? pain) async {
    await _box.add(BodyRecord(
      bodyPartId: partId,
      content: content,
      painLevel: pain,
    ));
  }

  Future<void> remove(BodyRecord record) async {
    await record.delete();
  }

  Future<void> clear() async => await _box.clear();
}

final bodyRecordRepo = BodyRecordRepo();
