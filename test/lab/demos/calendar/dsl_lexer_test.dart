import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_lexer.dart';

void main() {
  List<TokenKind> kinds(String input) => tokenize(input)
      .tokens
      .where((t) => t.kind != TokenKind.eof)
      .map((t) => t.kind)
      .toList();

  test('empty input → only EOF, no errors', () {
    final r = tokenize('');
    expect(r.errors, isEmpty);
    expect(r.tokens, hasLength(1));
    expect(r.tokens.single.kind, TokenKind.eof);
  });

  test('comment lines and blank lines are skipped', () {
    final r = tokenize('# hi\n\n   \n# bye\n');
    expect(r.errors, isEmpty);
    expect(r.tokens, hasLength(1));
    expect(r.tokens.single.kind, TokenKind.eof);
  });

  test('structural symbols', () {
    expect(
      kinds('{}[](),=:/@'),
      [
        TokenKind.lbrace, TokenKind.rbrace,
        TokenKind.lbracket, TokenKind.rbracket,
        TokenKind.lparen, TokenKind.rparen,
        TokenKind.comma, TokenKind.eq, TokenKind.colon, TokenKind.slash, TokenKind.at,
      ],
    );
  });

  test('string with escapes', () {
    final r = tokenize(r'"a\"b"');
    expect(r.errors, isEmpty);
    expect(r.tokens.first.kind, TokenKind.string);
    expect(r.tokens.first.text, 'a"b');
  });

  test('YYYY-MM-DD and YYYYMMDD become date tokens', () {
    final r1 = tokenize('2025-01-15');
    expect(r1.tokens.first.kind, TokenKind.date);
    expect(r1.tokens.first.text, '2025-01-15');
    final r2 = tokenize('20250115');
    expect(r2.tokens.first.kind, TokenKind.date);
    expect(r2.tokens.first.text, '20250115');
  });

  test('weekday + bool literals classified specially', () {
    final r = tokenize('Mon Tue true false');
    final kinds0 = r.tokens.where((t) => t.kind != TokenKind.eof).map((t) => t.kind).toList();
    expect(kinds0, [TokenKind.weekday, TokenKind.weekday, TokenKind.boolLit, TokenKind.boolLit]);
  });

  test('identifiers preserve dash', () {
    final r = tokenize('monthly-nth every-days');
    expect(r.tokens.map((t) => t.text).take(2), ['monthly-nth', 'every-days']);
  });

  test('unterminated string reports error but continues', () {
    final r = tokenize('"abc');
    expect(r.errors, isNotEmpty);
    expect(r.tokens.last.kind, TokenKind.eof);
  });

  test('unknown char emits error and skips one char', () {
    final r = tokenize('!');
    expect(r.errors, isNotEmpty);
    expect(r.tokens.last.kind, TokenKind.eof);
  });

  test('line/column tracking', () {
    final r = tokenize('a\nb');
    // 'a' starts at line 1 col 1; 'b' starts at line 2 col 1
    final identTokens = r.tokens.where((t) => t.kind == TokenKind.ident).toList();
    expect(identTokens[0].pos.line, 1);
    expect(identTokens[0].pos.column, 1);
    expect(identTokens[1].pos.line, 2);
    expect(identTokens[1].pos.column, 1);
  });
}