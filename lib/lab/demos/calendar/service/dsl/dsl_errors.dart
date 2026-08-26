/// 源码中的 1-based 行/列位置。
class Position {
  final int line;
  final int column;
  const Position(this.line, this.column);

  @override
  String toString() => 'line $line, col $column';

  @override
  bool operator ==(Object o) =>
      o is Position && o.line == line && o.column == column;

  @override
  int get hashCode => Object.hash(line, column);
}

/// DSL 解析/解释过程中产生的错误。
///
/// `pos` 是出错位置（lexer 在该处触发错误，或 parser 期望之外的 token 位置）。
/// `hint` 可选，提示用户可能的修正（如 "did you mean /weekday=Fri?"）。
class DslError {
  final Position pos;
  final String message;
  final String? hint;

  const DslError(this.pos, this.message, [this.hint]);

  @override
  String toString() =>
      '$pos: $message${hint != null ? ' ($hint)' : ''}';

  @override
  bool operator ==(Object o) =>
      o is DslError && o.pos == pos && o.message == message && o.hint == hint;

  @override
  int get hashCode => Object.hash(pos, message, hint);
}