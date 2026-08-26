import 'dsl_errors.dart';

/// Token 类型。
enum TokenKind {
  lbrace,    // {
  rbrace,    // }
  lbracket,  // [
  rbracket,  // ]
  lparen,    // (
  rparen,    // )
  eq,        // =
  slash,     // /
  comma,     // ,
  colon,     // :
  at,        // @
  string,    // "..." | '...'
  number,    // 123
  date,      // 2025-01-15 | 20250115
  ident,     // [A-Za-z_][A-Za-z0-9_-]*
  weekday,   // Mon|Tue|...|Sun
  boolLit,   // true | false
  eof,
}

/// 单个 token。
class Token {
  final TokenKind kind;
  final String text;
  final Position pos;
  const Token(this.kind, this.text, this.pos);

  @override
  String toString() => '$kind("$text"@$pos)';
}

/// 词法分析结果：tokens + errors（错误累积，不致命）。
class LexerResult {
  final List<Token> tokens;
  final List<DslError> errors;
  const LexerResult(this.tokens, this.errors);
}

/// 词法分析器入口。
LexerResult tokenize(String input) => _Lexer(input).run();

/// `_advance` 步进的"一格"按 rune（Unicode 码点）算。
/// `String.codeUnits` / `[]` 索引是 UTF-16 code unit；emoji 是 surrogate pair，
/// 不按 rune 走会拆开字符。本文件所有 lexer 偏移都用此函数。
int _runeAt(String s, int i) => s.runes.elementAt(i);

class _Lexer {
  _Lexer(this.input);

  final String input;

  /// `_i` 与 `_runeI` 严格同步：本 lexer 仅按 rune 推进；`_i` 保留为 codunit
  /// 偏移仅用于 `substring` 切片，`_col` 行号按 rune 数累加。
  int _i = 0;
  int _runeI = 0;
  int _line = 1;
  int _col = 1;
  final List<Token> _tokens = [];
  final List<DslError> _errors = [];

  Position get _pos => Position(_line, _col);

  void _advance(int runes) {
    for (var k = 0; k < runes; k++) {
      if (_runeI >= input.runes.length) {
        _i = input.length;
        return;
      }
      final ch = input.runes.elementAt(_runeI);
      if (ch == 0x0A) {
        _line++;
        _col = 1;
      } else {
        _col++;
      }
      // 把 rune 跳过去的 codunit 数累加到 _i。
      _i += _runeToCodUnits(ch);
      _runeI++;
    }
  }

  int _runeToCodUnits(int rune) =>
      (rune >= 0x10000) ? 2 : 1; // surrogate pair 占 2 code units

  bool _hasRunes([int rel = 0]) =>
      _runeI + rel < input.runes.length;
  int _ch([int rel = 0]) => _hasRunes(rel)
      ? input.runes.elementAt(_runeI + rel)
      : -1;

  void _error(String msg) {
    _errors.add(DslError(_pos, msg));
  }

  Position _tokenStart = const Position(1, 1);

  void _skipWhitespaceAndComments() {
    while (_hasRunes()) {
      final c = _ch();
      if (c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A) {
        _advance(1);
      } else if (c == 0x23 /* # */) {
        while (_hasRunes() && _ch() != 0x0A) {
          _advance(1);
        }
      } else {
        break;
      }
    }
  }

  void _emit(TokenKind k, String text) {
    _tokens.add(Token(k, text, _tokenStart));
  }

  void _readString(int quote) {
    // quote is 0x22 " or 0x27 '
    final startLine = _line;
    final startCol = _col;
    _advance(1); // skip opening quote
    final buf = StringBuffer();
    while (_hasRunes() && _ch() != quote) {
      final c = _ch();
      if (c == 0x5C /* \ */) {
        if (!_hasRunes(1)) {
          _error('unterminated escape in string');
          _advance(1);
          break;
        }
        final next = _ch(1);
        switch (next) {
          case 0x22:
            buf.writeCharCode(0x22); _advance(2); break;
          case 0x27:
            buf.writeCharCode(0x27); _advance(2); break;
          case 0x5C:
            buf.writeCharCode(0x5C); _advance(2); break;
          case 0x6E:
            buf.write('\n'); _advance(2); break;
          case 0x74:
            buf.write('\t'); _advance(2); break;
          default:
            _error('unknown escape: \\${String.fromCharCode(next)}');
            buf.writeCharCode(next);
            _advance(2);
        }
      } else if (c == 0x0A) {
        _error('unterminated string literal');
        break;
      } else {
        buf.writeCharCode(c);
        _advance(1);
      }
    }
    if (!_hasRunes()) {
      _errors.add(DslError(Position(startLine, startCol), 'unterminated string literal'));
    } else {
      _advance(1); // skip closing quote
    }
    _emit(TokenKind.string, buf.toString());
  }

  void _readNumberOrDate() {
    final startLine = _line;
    final startCol = _col;
    final start = _i;
    while (_hasRunes() && _ch() >= 0x30 && _ch() <= 0x39) {
      _advance(1);
    }
    var text = input.substring(start, _i);
    // Date: YYYY-MM-DD or YYYYMMDD (8 digits with optional - separation)
    if (text.length == 8) {
      _emit(TokenKind.date, text);
      return;
    }
    if (text.length == 4 && _hasRunes(2) &&
        _ch() == 0x2D /* - */ &&
        _ch(1) >= 0x30 && _ch(1) <= 0x39) {
      // possibly YYYY-MM-DD
      _advance(1); // skip -
      while (_hasRunes() && _ch() >= 0x30 && _ch() <= 0x39) {
        _advance(1);
      }
      if (_hasRunes(1) &&
          _ch() == 0x2D /* - */ &&
          _ch(1) >= 0x30 && _ch(1) <= 0x39) {
        _advance(1);
        while (_hasRunes() && _ch() >= 0x30 && _ch() <= 0x39) {
          _advance(1);
        }
        text = input.substring(start, _i);
        _emit(TokenKind.date, text);
        return;
      }
    }
    // MM-DD pattern (1-2 digits, dash, 1-2 digits) — used by one-liner
    // period forms like `yearly:08-15`. Emit as date.
    if (text.length <= 2 && _hasRunes(1) &&
        _ch() == 0x2D &&
        _ch(1) >= 0x30 && _ch(1) <= 0x39) {
      _advance(1); // skip -
      while (_hasRunes() && _ch() >= 0x30 && _ch() <= 0x39) {
        _advance(1);
      }
      text = input.substring(start, _i);
      _emit(TokenKind.date, text);
      return;
    }
    _emit(TokenKind.number, text);
    // startLine/startCol kept for potential debug use
    assert(startLine >= 0 && startCol >= 0);
  }

  static const _weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};
  static const _bools = {'true', 'false'};

  void _readIdent() {
    final start = _i;
    while (_hasRunes()) {
      final c = _ch();
      // ASCII letter / digit / underscore / dash：结构 idents（`yearly`、`monthly-nth` 等）。
      // 非 ASCII（>= 0x80）：emoji / 中文等值字符也接受为 ident 文本（用于 attribute value）。
      final isAsciiLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isUnderscore = c == 0x5F;
      final isDash = c == 0x2D;
      final isNonAsciiValue = c >= 0x80;
      if (isAsciiLetter || isDigit || isUnderscore || isDash || isNonAsciiValue) {
        _advance(1);
      } else {
        break;
      }
    }
    final text = input.substring(start, _i);
    if (_weekdays.contains(text)) {
      _emit(TokenKind.weekday, text);
    } else if (_bools.contains(text)) {
      _emit(TokenKind.boolLit, text);
    } else {
      _emit(TokenKind.ident, text);
    }
  }

  LexerResult run() {
    while (_hasRunes()) {
      _tokenStart = _pos;
      _skipWhitespaceAndComments();
      if (!_hasRunes()) break;
      _tokenStart = _pos;
      final c = _ch();
      switch (c) {
        case 0x7B: _advance(1); _emit(TokenKind.lbrace, '{'); break;       // {
        case 0x7D: _advance(1); _emit(TokenKind.rbrace, '}'); break;       // }
        case 0x5B: _advance(1); _emit(TokenKind.lbracket, '['); break;     // [
        case 0x5D: _advance(1); _emit(TokenKind.rbracket, ']'); break;     // ]
        case 0x28: _advance(1); _emit(TokenKind.lparen, '('); break;       // (
        case 0x29: _advance(1); _emit(TokenKind.rparen, ')'); break;       // )
        case 0x2C: _advance(1); _emit(TokenKind.comma, ','); break;        // ,
        case 0x3D: _advance(1); _emit(TokenKind.eq, '='); break;           // =
        case 0x2F: _advance(1); _emit(TokenKind.slash, '/'); break;        // /
        case 0x3A: _advance(1); _emit(TokenKind.colon, ':'); break;        // :
        case 0x40: _advance(1); _emit(TokenKind.at, '@'); break;           // @
        case 0x22: _readString(0x22); break;                              // "
        case 0x27: _readString(0x27); break;                              // '
        default:
          if (c >= 0x30 && c <= 0x39) {
            _readNumberOrDate();
          } else if ((c >= 0x41 && c <= 0x5A) ||
                     (c >= 0x61 && c <= 0x7A) ||
                     c == 0x5F ||
                     c >= 0x80) {
            // ASCII letter / underscore / non-ASCII rune 都进 ident（emoji 中文等）。
            _readIdent();
          } else {
            _error('unexpected character: ${String.fromCharCode(c)}');
            _advance(1);
          }
      }
    }
    _emit(TokenKind.eof, '');
    return LexerResult(_tokens, _errors);
  }
}