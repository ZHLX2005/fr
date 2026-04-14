import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/lab_note.dart';

class LabNoteProvider with ChangeNotifier {
  List<LabNote> _notes = [];
  static const String _storageKey = 'lab_notes';

  List<LabNote> get notes => _notes;

  Future<void> loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = prefs.getString(_storageKey);
      if (notesJson != null) {
        final List<dynamic> notesList = json.decode(notesJson);
        _notes = notesList.map((e) => LabNote.fromJson(e)).toList();
        _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载笔记失败: $e');
    }
  }

  Future<void> _saveNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = json.encode(_notes.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, notesJson);
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  Future<LabNote> createNote({
    String title = '',
    String content = '',
    String? color,
  }) async {
    final now = DateTime.now();
    final note = LabNote(
      id: const Uuid().v4(),
      title: title.isEmpty ? '新笔记' : title,
      content: content,
      createdAt: now,
      updatedAt: now,
      color: color ?? '#FFFFFF',
    );

    _notes.insert(0, note);
    await _saveNotes();
    notifyListeners();
    return note;
  }

  Future<void> updateNote({
    required String id,
    String? title,
    String? content,
    String? color,
  }) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      final note = _notes[index];
      _notes[index] = note.copyWith(
        title: title ?? note.title,
        content: content ?? note.content,
        color: color ?? note.color,
        updatedAt: DateTime.now(),
      );
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _saveNotes();
      notifyListeners();
    }
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _saveNotes();
    notifyListeners();
  }

  LabNote? getNoteById(String id) {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }
}
