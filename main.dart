import 'dart:io';

class Token {
  String type;
  String value;
  int position;
  Token(this.type, this.value, this.position);
}

abstract class Node {
  final dynamic value;
  final List<Node> children;

  Node(this.value, [List<Node>? children]) : children = children ?? [];

  int evaluate();
}

class IntVal extends Node {
  IntVal(int value) : super(value);

  @override
  int evaluate() => value as int;
}

class UnOp extends Node {
  UnOp(String op, Node operand) : super(op, [operand]);

  int _factorial(int n) {
    var result = 1;
    for (var i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  @override
  int evaluate() {
    final operandValue = children[0].evaluate();
    switch (value) {
      case "+":
        return operandValue;
      case "-":
        return -operandValue;
      case "!":
        if (operandValue < 0) {
          throw SemanticError("Factorial is only defined for non-negative integers");
        }
        return _factorial(operandValue);
      default:
        throw SemanticError("Invalid unary operator '$value'");
    }
  }
}

class BinOp extends Node {
  BinOp(String op, Node left, Node right) : super(op, [left, right]);

  @override
  int evaluate() {
    final leftValue = children[0].evaluate();
    final rightValue = children[1].evaluate();
    switch (value) {
      case "+":
        return leftValue + rightValue;
      case "-":
        return leftValue - rightValue;
      case "*":
        return leftValue * rightValue;
      case "/":
        if (rightValue == 0) {
          throw SemanticError("Division by zero is not allowed");
        }
        return leftValue ~/ rightValue;
      case "^":
        return leftValue ^ rightValue;
      default:
        throw SemanticError("Invalid binary operator '$value'");
    }
  }
}

class SemanticError implements Exception {
  final String message;

  SemanticError(this.message);

  @override
  String toString() => "[Semantic] $message";
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
        if (position + 1 < source.length && source[position + 1] == "*") {
          next = Token("POWER", "**", position);
          position += 2;
          return;
        }
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
      if (currentChar == "!"){
        next = Token("FACT", currentChar, position);
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
          "Invalid character '$currentChar' (ASCII ${currentChar.codeUnitAt(0)}). Expected: digits (0-9), operators (+, -, *, /, ^, !), parentheses, or spaces",
    );
  }
}

class Parser {
  late Lexer lexer;

  Node parseExpression() {
    Node node = parseTerm();

    while (lexer.next.type == "PLUS" ||
        lexer.next.type == "MINUS" ||
        lexer.next.type == "XOR") {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseTerm());
    }
    return node;
  }

  Node parseTerm() {
    Node node = parseFactor();

    while (lexer.next.type == "MULT" || lexer.next.type == "DIV") {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseFactor());
    }
    return node;
  }

  Node parseFactor() {
    if (lexer.next.type == "MINUS") {
      final op = lexer.next.value;
      lexer.selectToken();
      return UnOp(op, parseFactor());
    }

    if (lexer.next.type == "PLUS") {
      final op = lexer.next.value;
      lexer.selectToken();
      return UnOp(op, parseFactor());
    }

    if (lexer.next.type == "OPEN_PAR") {
      lexer.selectToken();
      Node node = parseExpression();
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
      while (lexer.next.type == "FACT") {
        lexer.selectToken();
        node = UnOp("!", node);
      }
      return node;
    }

    if (lexer.next.type == "INT") {
      Node node = IntVal(int.parse(lexer.next.value));
      lexer.selectToken();
      while (lexer.next.type == "FACT") {
        lexer.selectToken();
        node = UnOp("!", node);
      }
      return node;
    }

    throw CompilerError(
      sourceTag: "Parser",
      code: "E_PAR_EXPECTED_FACTOR",
      position: lexer.next.position,
      expression: lexer.source,
      message:
          "Expected number, sign (+/-), or '(', found '${lexer.next.value}' (${lexer.next.type})",
    );
  }

  int run(String code) {
    lexer = Lexer(code);
    final root = parseExpression();
    if (lexer.next.type != "EOF") {
      throw CompilerError(
        sourceTag: "Parser",
        code: "E_PAR_UNEXPECTED_TOKEN",
        position: lexer.next.position,
        expression: lexer.source,
        message: "Unexpected token '${lexer.next.value}' (${lexer.next.type}) after end of expression",
      );
    }
    return root.evaluate();
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
  } on SemanticError catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } on CompilerError catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } catch (e) {
    stderr.writeln("[Internal] E_INTERNAL: ${e.toString()}");
    exit(1);
  }
}
