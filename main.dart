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

      if (currentChar == "+"){
        next = Token("PLUS", currentChar, position);
        position++;
        return;
      }

      if (currentChar == "-"){
        next = Token("MINUS", currentChar, position);
        position++;
        return;
      }
    
      if (currentChar == "^"){
        next = Token("XOR", currentChar, position);
        position++;
        return;
      }
      // * / ( )
      if (currentChar == "*"){
        next = Token("MULT", currentChar, position);
        position++;
        return;
      }
      if (currentChar == "/"){
        next = Token("DIV", currentChar, position);
        position++;
        return;
      }
      if (currentChar == "("){
        next = Token("OPEN_PAR", currentChar, position);
        position++;
        return;
      }
      if (currentChar == ")"){
        next = Token("CLOSE_PAR", currentChar, position);
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
      next = Token("INT", number, start);
      return;
    }

    throw CompilerError(
      sourceTag: "Lexer",
      code: "E_LEX_INVALID_CHAR",
      position: position,
      expression: source,
      message:
          "Invalid character '$currentChar' (ASCII ${currentChar.codeUnitAt(0)}). Expected: digits (0-9), operators (+, -, ^), or spaces",
    );
  }
}

class Parser {
  late Lexer lexer;

  int parseExpression() {
    int value = parseTerm();
    
    while (lexer.next.type == "PLUS" || lexer.next.type == "MINUS" || lexer.next.type == "XOR") {
      final op = lexer.next.value;
      lexer.selectToken();
      final term = parseTerm();
      if (op == "+") value += term;
      if (op == "-") value -= term;
      if (op == "^") value ^= term;

    }
    return value;
  }

  int parseTerm() {
    int value = parseFactor();
    
    while (lexer.next.type == "MULT" || lexer.next.type == "DIV") {
      final op = lexer.next.value;
      final opPos = lexer.next.position;
      lexer.selectToken();
      final term = parseFactor();
      if (op == "*") value *= term;
      if (op == "/") {
        if (term == 0) {
          throw CompilerError(
            sourceTag: "Parser",
            code: "E_PAR_DIVISION_BY_ZERO",
            position: opPos,
            expression: lexer.source,
            message: "Division by zero is not allowed",
          );
        }
        value ~/= term;
      }
    }
    return value;
  }

  int parseFactor() {

      if (lexer.next.type == "MINUS") {
        lexer.selectToken();
        return -parseFactor();
      }

      if (lexer.next.type == "PLUS") {
        lexer.selectToken();
        return parseFactor();
      }

      if (lexer.next.type == "OPEN_PAR") {
        lexer.selectToken();
        final value = parseExpression();
        if (lexer.next.type != "CLOSE_PAR") {
          throw CompilerError(
            sourceTag: "Parser",
            code: "E_PAR_UNMATCHED_OPEN_PAREN",
            position: lexer.next.position,
            expression: lexer.source,
            message:
                "Expected closing parenthesis ')', found '${lexer.next.value}' (${lexer.next.type})",
          );
        }
        lexer.selectToken();
        return value;
      }
      
      final value = int.parse(lexer.next.value);
      lexer.selectToken();
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
  if (code.trim().isEmpty) {
    stderr.writeln(
      "[Parser] E_PAR_EMPTY_EXPRESSION at position 0: Empty expression is not allowed. Expected a number. Expression: '$code'.",
    );
    exit(1);
  }

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
