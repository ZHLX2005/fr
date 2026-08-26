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

class _Lexer {
  _Lexer(this.input);

  final String input;
  int _i = 0;
  int _line = 1;
  int _col = 1;
  final List<Token> _tokens = [];
  final List<DslError> _errors = [];

  Position get _pos => Position(_line, _col);

  void _advance(int n) {
    for (var k = 0; k < n; k++) {
      final ch = input.codeUnitAt(_i);
      if (ch == 0x0A) {
        _line++;
        _col = 1;
      } else {
        _col++;
      }
      _i++;
    }
  }

  bool _at(int rel) => _i + rel < input.length;
  int _ch([int rel = 0]) => input.codeUnitAt(_i + rel);

  void _error(String msg) {
    _errors.add(DslError(_pos, msg));
  }

  Position _tokenStart = const Position(1, 1);

  void _skipWhitespaceAndComments() {
    while (_i < input.length) {
      final c = _ch();
      if (c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A) {
        _advance(1);
      } else if (c == 0x23 /* # */) {
        while (_i < input.length && _ch() != 0x0A) {
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
    while (_i < input.length && _ch() != quote) {
      final c = _ch();
      if (c == 0x5C /* \ */) {
        if (!_at(1)) {
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
    if (_i >= input.length) {
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
    while (_i < input.length && _ch() >= 0x30 && _ch() <= 0x39) {
      _advance(1);
    }
    var text = input.substring(start, _i);
    // Date: YYYY-MM-DD or YYYYMMDD (8 digits with optional -/ separation)
    if (text.length == 8) {
      _emit(TokenKind.date, text);
      return;
    }
    if (text.length == 4 && _i + 2 < input.length &&
        _ch() == 0x2D /* - */ &&
        _ch(1) >= 0x30 && _ch(1) <= 0x39) {
      // possibly YYYY-MM-DD
      _advance(1); // skip -
      while (_i < input.length && _ch() >= 0x30 && _ch() <= 0x39) {
        _advance(1);
      }
      if (_i + 1 < input.length &&
          _ch() == 0x2D /* - */ &&
          _ch(1) >= 0x30 && _ch(1) <= 0x39) {
        _advance(1);
        while (_i < input.length && _ch() >= 0x30 && _ch() <= 0x39) {
          _advance(1);
        }
        text = input.substring(start, _i);
        _emit(TokenKind.date, text);
        return;
      }
    }
    _emit(TokenKind.number, text);
    // startLine/startCol kept for potential debug use
    assert(startLine >= 0 && startCol >= 0);
  }

  static const _weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};
  static const _bools = {'true', 'false'};

  void _readIdent() {
    final start = _i;
    while (_i < input.length) {
      final c = _ch();
      final isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isUnderscore = c == 0x5F;
      final isDash = c == 0x2D;
      if (isLetter || isDigit || isUnderscore || isDash) {
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
    while (_i < input.length) {
      _tokenStart = _pos;
      _skipWhitespaceAndComments();
      if (_i >= input.length) break;
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
                     c == 0x5F) {
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