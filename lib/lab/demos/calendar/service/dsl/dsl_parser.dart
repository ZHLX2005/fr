import 'dsl_ast.dart';
import 'dsl_errors.dart';
import 'dsl_lexer.dart';

/// 解析结果。
class ParseResult {
  final List<AstStmt> stmts;
  final List<DslError> errors;
  const ParseResult(this.stmts, this.errors);
}

/// 顶层入口：先 lex 后 parse。
ParseResult parseCalendarDsl(String input) {
  final lex = tokenize(input);
  final parser = _Parser(lex.tokens, lex.errors);
  return parser.parseFile();
}

/// Recursive-descent parser over a token stream。
///
/// 错误恢复：遇到解析错误时，跳到下一行或下一个顶层关键字（config/people/event）
/// 之前，继续解析后面的语句。错误累积在 `_errors`，不当一处出错就丢弃全部。
class _Parser {
  _Parser(this.tokens, this.errors);

  final List<Token> tokens;
  final List<DslError> errors;
  int _i = 0;
  final List<AstStmt> _stmts = [];

  Token _peek([int rel = 0]) => tokens[_i + rel];
  Token _eat() => tokens[_i++];
  bool _at(TokenKind k, [int rel = 0]) => _peek(rel).kind == k;
  bool _accept(TokenKind k) {
    if (_peek().kind == k) {
      _i++;
      return true;
    }
    return false;
  }

  Token _expect(TokenKind k, String message) {
    if (_peek().kind == k) return _eat();
    final p = _peek().pos;
    errors.add(DslError(p, message));
    return Token(k, '', p); // placeholder, will be re-evaluated
  }

  void _skipToRecovery() {
    // 跳到下一个换行或顶层关键字之前。
    while (_peek().kind != TokenKind.eof) {
      final k = _peek().kind;
      if (k == TokenKind.ident) {
        final t = _peek().text;
        if (t == 'config' || t == 'people' || t == 'event') return;
      }
      if (k == TokenKind.at || k == TokenKind.string) return; // 下一个顶层语句起头
      _i++;
    }
  }

  // ─── 顶层 ───

  ParseResult parseFile() {
    while (_peek().kind != TokenKind.eof) {
      final stmtStart = _peek().pos;
      try {
        final stmt = _parseStmt();
        if (stmt != null) _stmts.add(stmt);
      } catch (_) {
        _skipToRecovery();
        // 跳过本身不报错（已经报过）
        // 但要确保 stmtStart 推进
        if (_peek().pos == stmtStart && _peek().kind != TokenKind.eof) {
          _i++;
        }
      }
    }
    return ParseResult(_stmts, errors);
  }

  AstStmt? _parseStmt() {
    final t = _peek();
    if (t.kind == TokenKind.ident) {
      if (t.text == 'config') return _parseConfig();
      if (t.text == 'people') return _parsePeople();
      if (t.text == 'event') return _parseEventBlock();
    }
    // one-liner event: STRING OR IDENT @ expr
    if (t.kind == TokenKind.string || t.kind == TokenKind.ident) {
      return _parseEventOneline();
    }
    errors.add(DslError(t.pos, 'expected top-level statement, got ${t.text}'));
    _i++;
    return null;
  }

  // ─── config ───

  AstConfig _parseConfig() {
    final start = _eat().pos; // 'config'
    _expect(TokenKind.lbrace, "expected '{' after config");
    final pairs = <String, String>{};
    while (!_accept(TokenKind.rbrace)) {
      if (_peek().kind == TokenKind.eof) {
        errors.add(DslError(_peek().pos, "expected '}' to close config block"));
        break;
      }
      final keyTok = _expect(TokenKind.ident, 'expected config key');
      _expect(TokenKind.eq, "expected '=' after config key '${keyTok.text}'");
      final valTok = _expectAnyValueText('config value');
      pairs[keyTok.text] = valTok;
    }
    return AstConfig(start, pairs);
  }

  String _expectAnyValueText(String what) {
    final t = _eat();
    if (t.kind == TokenKind.string || t.kind == TokenKind.ident ||
        t.kind == TokenKind.number || t.kind == TokenKind.date ||
        t.kind == TokenKind.weekday || t.kind == TokenKind.boolLit) {
      return t.text;
    }
    errors.add(DslError(t.pos, 'expected $what, got ${t.text}'));
    return '';
  }

  // ─── people ───

  AstPeopleBlock _parsePeople() {
    final start = _eat().pos;
    _expect(TokenKind.lbrace, "expected '{' after people");
    final entries = <AstPersonEntry>[];
    while (!_accept(TokenKind.rbrace)) {
      if (_peek().kind == TokenKind.eof) {
        errors.add(DslError(_peek().pos, "expected '}' to close people block"));
        break;
      }
      final nameTok = _eat();
      if (nameTok.kind != TokenKind.string && nameTok.kind != TokenKind.ident) {
        errors.add(DslError(nameTok.pos, 'expected person name as string'));
        _skipToRecovery();
        continue;
      }
      _expect(TokenKind.lbrace, "expected '{' after person name");
      final attrs = <String, String>{};
      while (!_accept(TokenKind.rbrace)) {
        if (_peek().kind == TokenKind.eof) {
          errors.add(DslError(_peek().pos, "expected '}' to close person entry"));
          break;
        }
        final k = _expect(TokenKind.ident, 'expected attribute name');
        _expect(TokenKind.eq, "expected '=' after attribute '${k.text}'");
        final v = _expectAnyValueText('attribute value');
        attrs[k.text] = v;
      }
      entries.add(AstPersonEntry(nameTok.text, attrs, nameTok.pos));
    }
    return AstPeopleBlock(start, entries);
  }

  // ─── event block ───

  AstEventBlock _parseEventBlock() {
    final start = _eat().pos; // 'event'
    final titleTok = _eat();
    if (titleTok.kind != TokenKind.string && titleTok.kind != TokenKind.ident) {
      errors.add(DslError(titleTok.pos, 'expected event title as string'));
      // 尽力恢复
      _expect(TokenKind.lbrace, "expected '{'");
      _skipToRecovery();
      return AstEventBlock(start, titleTok.text, {});
    }
    _expect(TokenKind.lbrace, "expected '{' after event title");
    final fields = <String, AstValue>{};
    while (!_accept(TokenKind.rbrace)) {
      if (_peek().kind == TokenKind.eof) {
        errors.add(DslError(_peek().pos, "expected '}' to close event block"));
        break;
      }
      final keyTok = _expect(TokenKind.ident, 'expected field name');
      _expect(TokenKind.eq, "expected '=' after field '${keyTok.text}'");
      final v = _parseValue();
      fields[keyTok.text] = v;
    }
    return AstEventBlock(start, titleTok.text, fields);
  }

  AstValue _parseValue() {
    final t = _peek();
    if (t.kind == TokenKind.string) return AstString(_eat().pos, t.text);
    if (t.kind == TokenKind.number) {
      _eat();
      return AstNumber(t.pos, int.parse(t.text));
    }
    if (t.kind == TokenKind.boolLit) {
      _eat();
      return AstBool(t.pos, t.text == 'true');
    }
    if (t.kind == TokenKind.weekday) {
      _eat();
      return AstString(t.pos, t.text);
    }
    if (t.kind == TokenKind.date) {
      _eat();
      return AstString(t.pos, t.text);
    }
    if (t.kind == TokenKind.ident) {
      // Plain identifier as value (e.g. `type=birthday`, `color=red`).
      // Period kinds go through `_parsePeriod` separately below.
      if (_isPeriodKind(t.text)) return _parsePeriod();
      _eat();
      return AstString(t.pos, t.text);
    }
    if (t.kind == TokenKind.lbracket) {
      return _parseList();
    }
    errors.add(DslError(t.pos, 'unexpected value token: ${t.text}'));
    _i++;
    return AstString(t.pos, '');
  }

  static const _periodKinds = {
    'once',
    'yearly',
    'monthly-day',
    'monthly-nth',
    'every-days',
    'every-weeks',
  };

  bool _isPeriodKind(String s) => _periodKinds.contains(s);

  AstPeriod _parsePeriod() {
    final start = _eat().pos; // period kind
    final kind = _peek(-1).text;
    final tail = <String, AstValue>{};
    while (_accept(TokenKind.slash)) {
      if (_peek().kind != TokenKind.ident) {
        errors.add(DslError(_peek().pos, 'expected period path key after /'));
        break;
      }
      final key = _eat();
      _expect(TokenKind.eq, "expected '=' after period key '${key.text}'");
      // value 部分：可能多个值（逗号分隔） / 列表（[]） / 单值
      if (_peek().kind == TokenKind.lbracket) {
        _eat(); // skip [
        final items = <AstValue>[];
        while (!_accept(TokenKind.rbracket)) {
          if (_peek().kind == TokenKind.eof) break;
          items.add(_parseSimpleValueForPeriod());
          _accept(TokenKind.comma);
        }
        tail[key.text] = AstList(_peek().pos, [for (final v in items) {'v': v}]);
      } else if (_isAtWeekdayList()) {
        // /weekdays=Mon,Wed,Fri  —— 多个 weekday 由逗号分隔
        final items = <AstValue>[];
        items.add(_parseSimpleValueForPeriod());
        while (_accept(TokenKind.comma)) {
          items.add(_parseSimpleValueForPeriod());
        }
        tail[key.text] = AstList(_peek().pos, [for (final v in items) {'v': v}]);
      } else {
        tail[key.text] = _parseSimpleValueForPeriod();
      }
    }
    return AstPeriod(start, kind, tail);
  }

  bool _isAtWeekdayList() {
    // 当前 + 后一个 token 都是 weekday 或 weekday + COMMA + weekday
    if (_peek().kind != TokenKind.weekday) return false;
    if (_peek(1).kind == TokenKind.comma) return true;
    return false;
  }

  AstValue _parseSimpleValueForPeriod() {
    final t = _peek();
    if (t.kind == TokenKind.number) {
      _eat();
      return AstNumber(t.pos, int.parse(t.text));
    }
    if (t.kind == TokenKind.string) {
      _eat();
      return AstString(t.pos, t.text);
    }
    if (t.kind == TokenKind.ident) {
      _eat();
      return AstString(t.pos, t.text);
    }
    if (t.kind == TokenKind.boolLit) {
      _eat();
      return AstBool(t.pos, t.text == 'true');
    }
    if (t.kind == TokenKind.date) {
      _eat();
      return AstString(t.pos, t.text);
    }
    if (t.kind == TokenKind.weekday) {
      _eat();
      return AstString(t.pos, t.text);
    }
    errors.add(DslError(t.pos, 'unexpected value in period path: ${t.text}'));
    _i++;
    return AstString(t.pos, '');
  }

  AstList _parseList() {
    final start = _eat().pos; // skip [
    final items = <Map<String, AstValue>>[];
    while (!_accept(TokenKind.rbracket)) {
      if (_peek().kind == TokenKind.eof) break;
      _expect(TokenKind.lbrace, "expected '{' inside list");
      final entry = <String, AstValue>{};
      while (!_accept(TokenKind.rbrace)) {
        if (_peek().kind == TokenKind.eof) break;
        // 多个 key=value 间用逗号分隔
        if (entry.isNotEmpty) _accept(TokenKind.comma);
        final k = _expect(TokenKind.ident, 'expected key in list entry');
        _expect(TokenKind.eq, "expected '=' in list entry");
        entry[k.text] = _parseSimpleValueForPeriod();
      }
      items.add(entry);
      _accept(TokenKind.comma);
    }
    return AstList(start, items);
  }

  // ─── one-liner ───

  /// One-liner date-expr 终结条件：
  /// - EOF / `@` (next event)
  /// - 看到 `ident EQ` 序列（属性的开头）
  bool _isAttrStart() {
    return _peek().kind == TokenKind.ident && _peek(1).kind == TokenKind.eq;
  }

  AstEventOneline _parseEventOneline() {
    final titleTok = _eat();
    _expect(TokenKind.at, "expected '@' after event title");
    // 收集 date-expr：先吞第一个 token（date/number/period-kind/ident），
    // 然后扩展到 `/key=value` 路径或逗号列表，直到看到 attr 边界。
    final exprStart = _peek().pos;
    final buf = StringBuffer();
    if (_peek().kind == TokenKind.eof) {
      errors.add(DslError(_peek().pos, 'expected date expression after @'));
      return AstEventOneline(titleTok.pos, titleTok.text, '', {});
    }
    // 第一个 token 必须是 date/number 或 period-kind ident。
    final first = _peek();
    if (first.kind == TokenKind.date) {
      buf.write(first.text); _i++;
    } else if (first.kind == TokenKind.number) {
      buf.write(first.text); _i++;
    } else if (first.kind == TokenKind.ident && _isPeriodKind(first.text)) {
      buf.write(first.text); _i++;
    } else {
      errors.add(DslError(first.pos, 'expected date or period kind after @'));
    }
    // 扩展到 `/key=value...` 路径 + 单值后缀（如 `yearly:08-15` 的 `-15` 部分）。
    while (_peek().kind != TokenKind.eof) {
      final k = _peek().kind;
      if (_isAttrStart()) break;
      if (k == TokenKind.slash ||
          k == TokenKind.eq ||
          k == TokenKind.comma ||
          k == TokenKind.colon) {
        buf.write(_peek().text); _i++;
        continue;
      }
      if (k == TokenKind.ident && _isPeriodKind(_peek().text)) {
        buf.write(_peek().text); _i++; continue;
      }
      if (k == TokenKind.number || k == TokenKind.date || k == TokenKind.ident) {
        buf.write(_peek().text); _i++; continue;
      }
      if (k == TokenKind.weekday || k == TokenKind.boolLit) {
        buf.write(_peek().text); _i++; continue;
      }
      if (k == TokenKind.at) break; // next event
      break; // 未知字符 ——报错但不致死（已 lex 过；parser 这层不会 reject 字符）
    }
    final exprText = buf.toString().trim();
    final attrs = _parseAttrsTail();
    return AstEventOneline(titleTok.pos, titleTok.text, exprText, attrs);
  }

  Map<String, String> _parseAttrsTail() {
    final out = <String, String>{};
    while (_peek().kind != TokenKind.eof && _peek().kind != TokenKind.at) {
      final t = _peek();
      if (t.kind != TokenKind.ident) break;
      // 期望 key=value
      _i++;
      if (!_accept(TokenKind.eq)) {
        errors.add(DslError(t.pos, "expected '=' after attribute key '${t.text}'"));
        continue;
      }
      final v = _expectAnyValueText('attribute value');
      out[t.text] = v;
    }
    return out;
  }
}