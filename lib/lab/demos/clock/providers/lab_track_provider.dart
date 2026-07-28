import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track_record.dart';
import 'beat_coordinator.dart';

class LabTrackProvider with ChangeNotifier {
  List<LabTrack> _tracks = [];
  List<LabTrackRecord> _records = [];
  static const String _tracksKey = 'lab_tracks';
  static const String _recordsKey = 'lab_track_records';

  // Runtime state
  String? _activeTrackId;
  int _currentSegmentIndex = 0;
  DateTime? _segmentStartTime;
  int _segmentStartRemaining = 0;
  Timer? _timer;

  // Public getters
  List<LabTrack> get tracks => _tracks;
  List<LabTrackRecord> get records => _records;
  String? get activeTrackId => _activeTrackId;
  int get currentSegmentIndex => _currentSegmentIndex;

  /// Remaining seconds for the current segment, computed from startTime.
  /// Returns 0 if no track is active.
  int get currentSegmentRemaining {
    if (_activeTrackId == null || _segmentStartTime == null) return 0;
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    if (i == -1) return 0;
    final t = _tracks[i];
    if (_currentSegmentIndex >= t.segments.length) return 0;
    final elapsed = DateTime.now().difference(_segmentStartTime!).inSeconds;
    return _segmentStartRemaining - elapsed;
  }

  /// Returns the active track, or null.
  LabTrack? get activeTrack {
    if (_activeTrackId == null) return null;
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    return i == -1 ? null : _tracks[i];
  }

  /// Total remaining seconds across all segments from the current segment onwards.
  int get totalRemaining {
    final t = activeTrack;
    if (t == null) return 0;
    int sum = 0;
    for (var i = _currentSegmentIndex; i < t.segments.length; i++) {
      sum += t.segments[i].snapshotDurationSeconds;
    }
    // subtract the elapsed time of the current segment
    sum -= (t.segments[_currentSegmentIndex].snapshotDurationSeconds -
        currentSegmentRemaining);
    return sum < 0 ? 0 : sum;
  }

  LabTrackProvider() {
    BeatCoordinator.registerBeatenOutCallback((id) {
      if (id.startsWith('track:')) {
        // Mark this track as beat-silent; the per-second tick still updates UI.
        // For now, we just notify listeners so the runner dot can grey out.
        notifyListeners();
      }
    });
  }

  Future<void> loadTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final tracksJson = prefs.getString(_tracksKey);
    if (tracksJson != null) {
      _tracks = (json.decode(tracksJson) as List)
          .map((e) => LabTrack.fromJson(e))
          .toList();
    }
    final recordsJson = prefs.getString(_recordsKey);
    if (recordsJson != null) {
      _records = (json.decode(recordsJson) as List)
          .map((e) => LabTrackRecord.fromJson(e))
          .toList();
      _records.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
    notifyListeners();
  }

  Future<void> _saveTracks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tracksKey, json.encode(_tracks.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, json.encode(_records.map((e) => e.toJson()).toList()));
  }

  Future<LabTrack> createTrack(LabTrack t) async {
    _tracks.insert(0, t);
    await _saveTracks();
    notifyListeners();
    return t;
  }

  Future<void> updateTrack(LabTrack t) async {
    final i = _tracks.indexWhere((x) => x.id == t.id);
    if (i == -1) return;
    _tracks[i] = t;
    await _saveTracks();
    notifyListeners();
  }

  Future<void> deleteTrack(String id) async {
    _tracks.removeWhere((t) => t.id == id);
    _records.removeWhere((r) => r.trackId == id);
    await _saveTracks();
    await _saveRecords();
    notifyListeners();
  }

  Future<void> startTrack(String trackId) async {
    final i = _tracks.indexWhere((t) => t.id == trackId);
    if (i == -1) return;
    final t = _tracks[i];
    if (t.segments.isEmpty) return;

    _activeTrackId = trackId;
    _currentSegmentIndex = 0;
    _segmentStartTime = DateTime.now();
    _segmentStartRemaining = t.segments[0].snapshotDurationSeconds;

    // Create the record (only if not already active).
    if (!_records.any((r) => r.trackId == trackId && r.endTime == null)) {
      final rec = LabTrackRecord(
        id: const Uuid().v4(),
        trackId: t.id,
        trackTitle: t.title,
        startTime: _segmentStartTime!,
        totalDurationSeconds: t.segments.fold(0, (s, seg) => s + seg.snapshotDurationSeconds),
        segmentIndex: 0,
        perSegmentSeconds: List.filled(t.segments.length, 0),
      );
      _records.insert(0, rec);
      await _saveRecords();
    }

    // Request beat ownership for the first segment.
    final seg = t.segments[0];
    if (seg.snapshotBpm != null) {
      BeatCoordinator.requestOwnership(
        providerId: 'track:$trackId',
        bpm: seg.snapshotBpm,
        beatPattern: seg.snapshotBeatPattern,
      );
    }

    _startTimer();
    await _saveTracks();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeTrackId == null) return;
      final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
      if (i == -1) return;
      final t = _tracks[i];
      if (_currentSegmentIndex >= t.segments.length) return;
      final elapsed = DateTime.now().difference(_segmentStartTime!).inSeconds;
      final newRemaining = _segmentStartRemaining - elapsed;
      if (newRemaining <= 0) {
        _advanceSegment();
      }
      notifyListeners();
    });
  }

  void _advanceSegment() {
    if (_activeTrackId == null) return;
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    if (i == -1) return;
    final t = _tracks[i];

    // Update the in-flight record with elapsed seconds for this segment.
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      final r = _records[recIdx];
      final newSeg = List<int>.from(r.perSegmentSeconds);
      newSeg[_currentSegmentIndex] = _segmentStartRemaining;
      _records[recIdx] = r.copyWith(segmentIndex: _currentSegmentIndex, perSegmentSeconds: newSeg);
    }

    _currentSegmentIndex += 1;
    if (_currentSegmentIndex >= t.segments.length) {
      _completeTrack();
      return;
    }
    final next = t.segments[_currentSegmentIndex];
    _segmentStartTime = DateTime.now();
    _segmentStartRemaining = next.snapshotDurationSeconds;
    if (next.snapshotBpm != null) {
      BeatCoordinator.requestOwnership(
        providerId: 'track:$_activeTrackId',
        bpm: next.snapshotBpm,
        beatPattern: next.snapshotBeatPattern,
      );
    } else {
      BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    }
  }

  Future<void> _completeTrack() async {
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    if (i == -1) return;
    final t = _tracks[i];
    final totalConsumed = t.segments.fold<int>(0, (s, seg) => s + seg.snapshotDurationSeconds);
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      _records[recIdx] = _records[recIdx].copyWith(
        endTime: DateTime.now(),
        completed: true,
        accumulatedSeconds: totalConsumed,
      );
      await _saveRecords();
    }
    _activeTrackId = null;
    _timer?.cancel();
    notifyListeners();
  }

  Future<void> pauseTrack() async {
    _timer?.cancel();
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    notifyListeners();
  }

  Future<void> skipSegment() async {
    _advanceSegment();
    notifyListeners();
  }

  Future<void> stopTrack() async {
    _timer?.cancel();
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    // Mark record as stopped (not completed) so the user can see partial progress.
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      _records[recIdx] = _records[recIdx].copyWith(
        endTime: DateTime.now(),
        completed: false,
        accumulatedSeconds: 0,
      );
      await _saveRecords();
    }
    _activeTrackId = null;
    notifyListeners();
  }

  int getRecordLiveDuration(LabTrackRecord r) {
    if (r.completed) return r.accumulatedSeconds ?? 0;
    if (_activeTrackId == r.trackId && r.endTime == null) {
      // Approximate: sum of consumed segments so far.
      return r.perSegmentSeconds.take(r.segmentIndex + 1).fold(0, (a, b) => a + b);
    }
    return r.accumulatedSeconds ?? 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
