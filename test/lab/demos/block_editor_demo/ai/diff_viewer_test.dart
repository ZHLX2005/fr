import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/diff_viewer.dart';

void main() {
  testWidgets('renders added/removed/context lines with distinct colors',
      (tester) async {
    const diff = '@@ -1,2 +1,2 @@\n context line\n-old\n+new';

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DiffViewer(diff: diff)),
    ));

    expect(find.textContaining('old'), findsOneWidget);
    expect(find.textContaining('new'), findsOneWidget);
    expect(find.textContaining('context'), findsOneWidget);
  });

  testWidgets('renders nothing visible when diff is empty', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DiffViewer(diff: '')),
    ));
    expect(find.byType(ListView), findsNothing);
  });
}
