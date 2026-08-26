import 'dsl_errors.dart';

/// AST 基类。
sealed class AstNode {
  final Position pos;
  const AstNode(this.pos);
}

/// 顶层语句。
sealed class AstStmt extends AstNode {
  const AstStmt(super.pos);
}

class AstConfig extends AstStmt {
  final Map<String, String> pairs;
  const AstConfig(super.pos, this.pairs);
}

class AstPersonEntry {
  final String name;
  final Map<String, String> attrs;
  final Position pos;
  const AstPersonEntry(this.name, this.attrs, this.pos);
}

class AstPeopleBlock extends AstStmt {
  final List<AstPersonEntry> entries;
  const AstPeopleBlock(super.pos, this.entries);
}

class AstEventBlock extends AstStmt {
  final String title;
  final Map<String, AstValue> fields;
  const AstEventBlock(super.pos, this.title, this.fields);
}

/// One-liner event expression: `title @ YYYY-MM-DD [attr=...]` 或 `title @ yearly-MM-DD` 等。
class AstEventOneline extends AstStmt {
  final String title;
  final String dateExprText; // raw date-expr text, 包括 period 关键字
  final Map<String, String> attrs;
  const AstEventOneline(super.pos, this.title, this.dateExprText, this.attrs);
}

/// 值表达式：string / number / bool / list / period
sealed class AstValue {
  final Position pos;
  const AstValue(this.pos);
}

class AstString extends AstValue {
  final String text;
  const AstString(super.pos, this.text);
}

class AstNumber extends AstValue {
  final int n;
  const AstNumber(super.pos, this.n);
}

class AstBool extends AstValue {
  final bool b;
  const AstBool(super.pos, this.b);
}

/// List value, e.g. `people = [{name:"x"}]` —— 每项是一个 key→value map。
class AstList extends AstValue {
  final List<Map<String, AstValue>> items;
  const AstList(super.pos, this.items);
}

/// Period value, e.g. `yearly /month=04 /day=15`.
class AstPeriod extends AstValue {
  final String kind; // 'yearly' / 'monthly-day' / ...
  final Map<String, AstValue> tail; // 关键字路径
  const AstPeriod(super.pos, this.kind, this.tail);
}