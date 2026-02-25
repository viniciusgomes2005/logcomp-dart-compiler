import 'dart:io';

class Token {
  String type;
  String value;
  int position;
  Token(this.type, this.value, this.position);
}

class CompilerError implements Exception {
  final String sourceTag;
  final String code;
  final String message;
  final int position;
  final String expression;

  CompilerError({
    required this.sourceTag,
    required this.code,
    required this.message,
    required this.position,
    required this.expression,
  });

  @override
  String toString() {
    return "[$sourceTag] $code at position $position: $message. Expression: '$expression'.";
  }
}

class Lexer {
  final String source;
  int position = 0;
  late Token next;

  Lexer(this.source) {
    selectToken();
  }

  void _skipSpaces() {
    while (position < source.length && source[position] == " ") {
      position++;
    }
  }

  void selectToken() {
    _skipSpaces();

    if (position >= source.length) {
      next = Token("EOF", "", position);
      return;
    }

    final currentChar = source[position];

    if (currentChar == "+" || currentChar == "-") {
      next = Token("OPERATOR", currentChar, position);
      position++;
      return;
    }

    if (int.tryParse(currentChar) != null) {
      final start = position;
      var number = "";
      while (position < source.length &&
          int.tryParse(source[position]) != null) {
        number += source[position];
        position++;
      }
      next = Token("NUMBER", number, start);
      return;
    }

    throw CompilerError(
      sourceTag: "Lexer",
      code: "E_LEX_INVALID_CHAR",
      position: position,
      expression: source,
      message:
          "Invalid character '$currentChar' (ASCII ${currentChar.codeUnitAt(0)}). Expected: digits (0-9), operators (+, -), or spaces",
    );
  }
}

class Parser {
  late Lexer lexer;

  int parseExpression() {
    if (lexer.next.type == "OPERATOR") {
      throw CompilerError(
        sourceTag: "Parser",
        code: "E_PAR_STARTS_WITH_OPERATOR",
        position: lexer.next.position,
        expression: lexer.source,
        message: "Expression cannot start with operator '${lexer.next.value}'",
      );
    }

    int value = 0;

    if (lexer.next.type == "EOF") {
      return value;
    }

    if (lexer.next.type != "NUMBER") {
      throw CompilerError(
        sourceTag: "Parser",
        code: "E_PAR_EXPECTED_NUMBER",
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected a number, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }

    value = int.parse(lexer.next.value);
    lexer.selectToken();

    while (lexer.next.type != "EOF") {
      if (lexer.next.type != "OPERATOR") {
        throw CompilerError(
          sourceTag: "Parser",
          code: "E_PAR_EXPECTED_OPERATOR",
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected operator (+ or -), found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      final op = lexer.next.value;
      final opPos = lexer.next.position;
      lexer.selectToken();

      if (lexer.next.type != "NUMBER") {
        final found = lexer.next.type == "EOF"
            ? "end of expression"
            : "'${lexer.next.value}' (${lexer.next.type})";

        throw CompilerError(
          sourceTag: "Parser",
          code: "E_PAR_EXPECTED_NUMBER_AFTER_OPERATOR",
          position: opPos,
          expression: lexer.source,
          message: "Expected number after operator '$op', found $found",
        );
      }

      final term = int.parse(lexer.next.value);
      if (op == "+") value += term;
      if (op == "-") value -= term;

      lexer.selectToken();
    }

    return value;
  }

  int run(String code) {
    lexer = Lexer(code);
    return parseExpression();
  }
}

void main(List<String> args) {
  if (args.isEmpty) {
    stdout.writeln("Use: dart run main.dart 10 + 5 - 3");
    exit(64);
  }

  final code = args.join(" ");
  final parser = Parser();

  try {
    final result = parser.run(code);
    stdout.writeln(result);
  } on CompilerError catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } catch (e) {
    stderr.writeln("[Internal] E_INTERNAL: ${e.toString()}");
    exit(1);
  }
}
