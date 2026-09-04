// lib/core/game_kit/emoji/lua_script_assembler.dart
//
// Tiny LuaScriptAssembler — concatenates lifecycle + actions + optional
// extra segments (e.g. emoji) and synthesizes the export `return {…}` table
// so callers never hand-edit `definition.functions` or the on_* bindings.
//
// Design constraints:
// - No Lua parser. String concat + marker substitution only.
// - The last segment (actions or the trailing `return {…}` inside it) is
//   replaced by a freshly generated export table that includes `on_action_EMOJI`
//   when the emoji segment is among extraSegments (detected by substring
//   "on_action_EMOJI").
// - Lifecycle is emitted verbatim first; then actions with its trailing
//   `return {…}` stripped (if present); then each extra segment stripped the
//   same way; then a single canonical `return { definition = …, on_init = … }`.
//
// Caller contract (mirrors chess_script.dart v5 order):
//   assembleLuaScript(lifecycle: kChessScriptLifecycle, actions: kChessScriptActions)
//   assembleLuaScript(lifecycle: ..., actions: ..., extraSegments: [kEmojiScriptSegment])

/// Assemble a net_p2p v3 Lua script from lifecycle + actions + optional
/// extra segments (e.g. [kEmojiScriptSegment]).
///
/// Concatenation order: `lifecycle` → `actions` → `extraSegments` → single
/// generated `return { definition, on_init, ... }` export table.
///
/// Export table always exposes the canonical lifecycle handlers
/// (`on_init`, `on_join`, `on_leave`) plus every `on_action_*` discovered
/// (string scan) in the assembled body — so opting into the emoji segment
/// automatically adds `on_action_EMOJI` without caller-side edits.
String assembleLuaScript({
  required String lifecycle,
  required String actions,
  List<String> extraSegments = const [],
}) {
  final hasEmoji = extraSegments.any((s) => s.contains('on_action_EMOJI'));

  final strippedActions = _stripTrailingReturn(actions);
  final strippedExtras = extraSegments.map(_stripTrailingReturn).toList();

  final buf = StringBuffer();
  buf.write(lifecycle);
  if (!lifecycle.endsWith('\n')) buf.write('\n');
  buf.write(strippedActions);
  if (!strippedActions.endsWith('\n')) buf.write('\n');
  for (final seg in strippedExtras) {
    buf.write(seg);
    if (!seg.endsWith('\n')) buf.write('\n');
  }

  final body = buf.toString();
  final actionNames = _collectActionNames(body);
  if (hasEmoji && !actionNames.contains('on_action_EMOJI')) {
    actionNames.add('on_action_EMOJI');
  }

  buf.write(_buildReturnTable(actionNames));
  return buf.toString();
}

/// Strip trailing return table if present (the conventional
/// last block of an actions segment). Leaves handler definitions intact.
String _stripTrailingReturn(String src) {
  final idx = src.lastIndexOf('return {');
  if (idx == -1) return src;
  final tail = src.substring(idx);
  if (!tail.contains('definition')) return src;
  return '${src.substring(0, idx).trimRight()}\n';
}

/// Collect on_action_* handler names defined as on_action_X = function
/// in the assembled Lua body (string scan, no parser).
List<String> _collectActionNames(String luaBody) {
  final re = RegExp(r'on_action_(\w+)\s*=\s*function');
  final names = <String>{};
  for (final m in re.allMatches(luaBody)) {
    names.add('on_action_${m.group(1)}');
  }
  return names.toList();
}

String _buildReturnTable(List<String> actionNames) {
  final funcs = <String>[
    '"on_init"',
    '"on_join"',
    '"on_leave"',
    for (final a in actionNames) '"$a"',
  ];
  final bindings = <String>[
    '  on_init = on_init,',
    '  on_join = on_join,',
    '  on_leave = on_leave,',
    for (final a in actionNames) '  $a = $a,',
  ];
  return 'return {\n'
      '  definition = {\n'
      '    functions = {\n'
      '      ${funcs.join(', ')},\n'
      '    },\n'
      '  },\n'
      '${bindings.join('\n')}\n'
      '}\n';
}
