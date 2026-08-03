import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../domain/models.dart';
import '../../presentation/timetable_store.dart';
import 'timetable_dsl_parser.dart';
import '../../presentation/timetable_colors.dart';
import '../../../design/emphasis_button.dart';
import 'timetable_prefs.dart';

/// SICAU 教务系统课表导入对话框
///
/// 学号/密码/学期 通过 [TimetablePrefs] 持久化到 SharedPreferences，
/// 下次打开 dialog 自动填入，避免重复编辑。
class SicauImportDialog extends ConsumerStatefulWidget {
  const SicauImportDialog({super.key});

  @override
  ConsumerState<SicauImportDialog> createState() => _SicauImportDialogState();
}

class _SicauImportDialogState extends ConsumerState<SicauImportDialog> {
  final _userIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _semesterCtrl = TextEditingController();
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 首次 build 前预填（异步），填好就 _loaded=true
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final c = await TimetablePrefs.loadSicauCreds();
    if (!mounted) return;
    setState(() {
      _userIdCtrl.text = c.userId;
      _passwordCtrl.text = c.password;
      _semesterCtrl.text = c.semester;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    _semesterCtrl.dispose();
    super.dispose();
  }

  Future<void> _doImport() async {
    final userId = _userIdCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final semester = _semesterCtrl.text.trim();

    if (userId.isEmpty || password.isEmpty) {
      setState(() => _error = '学号和密码不能为空');
      return;
    }

    // 持久化：学号 + 学期 + 密码（密码非空才存，避免误清空）
    await TimetablePrefs.saveSicauCreds(
      userId: userId,
      password: password,
      semester: semester.isNotEmpty ? semester : TimetablePrefs.defaultSemester,
    );

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('http://47.110.80.47:81/api/sicau/timetable'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'password': password,
          if (semester.isNotEmpty) 'semester': semester,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dsl = data['dsl'] as String? ?? '';

        if (dsl.isEmpty) {
          setState(() => _error = '返回的课表为空');
          return;
        }

        final config = ref.read(TimetableStore.configProvider);
        final result = parseDsl(dsl, defaultSlotCount: config.slotsPerDay);

        if (result.courses.isEmpty) {
          setState(() => _error = '解析课程为空');
          return;
        }

        final store = ref.read(TimetableStore.provider.notifier);
        final grouped = <String, List<CourseItem>>{};
        for (final course in result.courses) {
          grouped.putIfAbsent(course.cellKey, () => []).add(course);
        }
        for (final entry in grouped.entries) {
          await store.upsertItems(entry.key, entry.value);
        }

        if (mounted) {
          Navigator.pop(context, result.courses.length);
        }
      } else if (response.statusCode == 401) {
        setState(() => _error = '学号或密码错误');
      } else {
        setState(() => _error = '导入失败 (HTTP ${response.statusCode})');
      }
    } catch (e) {
      setState(() => _error = '网络错误: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(color: Colors.black26),
        ),
        Center(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surface,
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TimetableColors.border, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outline,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.school,
                                size: 16,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'SICAU 导入',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: TimetableColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _userIdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '学号',
                            hintText: '如 202300000',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: '密码',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _semesterCtrl,
                          decoration: InputDecoration(
                            labelText: '学期（可选）',
                            hintText: '2025-2026-2',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _doImport,
                            style: EmphasisButton.borderEmphasis(
                              context,
                              color: TimetableColors.accent,
                            ),
                            icon: _loading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: TimetableColors.accent,
                                    ),
                                  )
                                : Icon(Icons.download, color: TimetableColors.accent),
                            label: Text(
                              _loading ? '导入中...' : '从教务系统导入',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: TimetableColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
