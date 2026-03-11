import 'dart:io';

class Token {
  String type;
  String value;
  int position;
  Token(this.type, this.value, this.position);
}

class Node {
  void evaluate() {}
}

class IntVal extends Node {
  int value;
  IntVal(this.value);

  @override
  void evaluate() => value;
}

class UnOp extends Node {
  String op;
  dynamic operand;
  UnOp(this.op, this.operand);

  @override
  void evaluate() {
    final operandValue = operand.evaluate();
    switch (op) {
      case "-":
        return -operandValue;
      default:
        throw CompilerError(
          sourceTag: "UnOp",
          code: "E_UNOP_INVALID_OPERATOR",
          position: 0,
          expression: "",
          message: "Invalid unary operator '$op'",
        );
    }
  }
}

class BinOp extends Node {
  String op;
  dynamic left;
  dynamic right;
  BinOp(this.op, this.left, this.right);

  @override
  void evaluate() {
    final leftValue = left.evaluate();
    final rightValue = right.evaluate();
    switch (op) {
      case "+":
        return leftValue + rightValue;
      case "-":
        return leftValue - rightValue;
      case "*":
        return leftValue * rightValue;
      case "/":
        return leftValue ~/ rightValue; // Integer division
      case "^":
        return leftValue ^ rightValue;
      default:
        throw CompilerError(
          sourceTag: "BinOp",
          code: "E_BINOP_INVALID_OPERATOR",
          position: 0,
          expression: "",
          message: "Invalid binary operator '$op'",
        );
    }
  }
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
          "Invalid character '$currentChar' (ASCII ${currentChar.codeUnitAt(0)}). Expected: digits (0-9), operators (+, -, *, /, ^), parentheses, or spaces",
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
      
      if (lexer.next.type == "INT") {
        final value = int.parse(lexer.next.value);
        lexer.selectToken();
        return value;
      }

      throw CompilerError(
        sourceTag: "Parser",
        code: "E_PAR_EXPECTED_FACTOR",
        position: lexer.next.position,
        expression: lexer.source,
        message: "Expected number, sign (+/-), or '(', found '${lexer.next.value}' (${lexer.next.type})",
      );
  }

  int run(String code) {
    lexer = Lexer(code);
    final result =  parseExpression();
    if (lexer.next.type != "EOF") {
      throw CompilerError(
        sourceTag: "Parser",
        code: "E_PAR_UNEXPECTED_TOKEN",
        position: lexer.next.position,
        expression: lexer.source,
        message: "Unexpected token '${lexer.next.value}' (${lexer.next.type}) after end of expression",
      );
    }
    return result;
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
