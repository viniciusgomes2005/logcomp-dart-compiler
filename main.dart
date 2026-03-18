import 'dart:io';

class Token {
  final String type;
  final String value;
  final int position;

  Token(this.type, this.value, this.position);
}

abstract class Node {
  final dynamic value;
  final List<Node> children;

  Node(this.value, [List<Node>? children]) : children = children ?? [];

  int evaluate(SymbolTable st);
}

class IntVal extends Node {
  IntVal(int value) : super(value);

  @override
  int evaluate(SymbolTable st) => value as int;
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
  int evaluate(SymbolTable st) {
    final operandValue = children[0].evaluate(st);
    switch (value) {
      case '+':
        return operandValue;
      case '-':
        return -operandValue;
      case '!':
        if (operandValue < 0) {
          throw SemanticError(
            'Factorial is only defined for non-negative integers',
          );
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
  int evaluate(SymbolTable st) {
    final leftValue = children[0].evaluate(st);
    final rightValue = children[1].evaluate(st);

    switch (value) {
      case '+':
        return leftValue + rightValue;
      case '-':
        return leftValue - rightValue;
      case '*':
        return leftValue * rightValue;
      case '/':
        if (rightValue == 0) {
          throw SemanticError('Division by zero is not allowed');
        }
        return leftValue ~/ rightValue;
      case '^':
        return leftValue ^ rightValue;
      default:
        throw SemanticError("Invalid binary operator '$value'");
    }
  }
}

class Identifier extends Node {
  Identifier(String name) : super(name, []);

  @override
  int evaluate(SymbolTable st) {
    return st.resolve(value as String);
  }
}

class Print extends Node {
  Print(Node expression) : super('print', [expression]);

  @override
  int evaluate(SymbolTable st) {
    final value = children[0].evaluate(st);
    print(value);
    return value;
  }
}

class Assignment extends Node {
  final bool immutable;

  Assignment(String variableName, Node expression, {this.immutable = false})
    : super(variableName, [expression]);

  @override
  int evaluate(SymbolTable st) {
    final resolved = children[0].evaluate(st);
    st.define(value as String, resolved, immutable: immutable);
    return resolved;
  }
}

class Block extends Node {
  Block(List<Node> statements) : super('block', statements);

  @override
  int evaluate(SymbolTable st) {
    int result = 0;
    for (final stmt in children) {
      result = stmt.evaluate(st);
    }
    return result;
  }
}

class NoOp extends Node {
  NoOp() : super('noop', []);

  @override
  int evaluate(SymbolTable st) => 0;
}

class SemanticError implements Exception {
  final String message;

  SemanticError(this.message);

  @override
  String toString() => '[Semantic] $message';
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

class Prepro {
  static String _applyConstants(String input, Map<String, String> constants) {
    var result = input;
    final keys = constants.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in keys) {
      final value = constants[key]!;
      result = result.replaceAll(RegExp('\\b${RegExp.escape(key)}\\b'), value);
    }

    return result;
  }

  static String filter(String code) {
    final withoutComments = code.replaceAll(
      RegExp(r'--.*$', multiLine: true),
      '',
    );

    final constants = <String, String>{};
    final processedLines = <String>[];

    for (final line in withoutComments.split('\n')) {
      final constMatch = RegExp(
        r'^\s*const\s+([a-zA-Z][a-zA-Z0-9_]*)\s*(?:=\s*)?(.+?)\s*$',
      ).firstMatch(line);

      if (constMatch != null) {
        final name = constMatch.group(1)!;
        final rawValue = constMatch.group(2)!;

        if (constants.containsKey(name)) {
          throw CompilerError(
            sourceTag: 'Prepro',
            code: 'E_PREPRO_DUPLICATE_CONST',
            position: 0,
            expression: code,
            message: "Constant '$name' declared more than once",
          );
        }

        final resolvedValue = _applyConstants(rawValue, constants);
        constants[name] = resolvedValue;
        continue;
      }

      processedLines.add(_applyConstants(line, constants));
    }

    final processedCode = processedLines.join('\n');

    if (processedCode.isEmpty) {
      return '\n';
    }

    return processedCode.endsWith('\n') ? processedCode : '$processedCode\n';
  }
}

class SymbolEntry {
  int value;
  final bool immutable;

  SymbolEntry({required this.value, required this.immutable});
}

class SymbolTable {
  final Map<String, SymbolEntry> table = {};

  void define(String name, int value, {bool immutable = false}) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(trimmedName)) {
      throw SemanticError("Invalid identifier '$name'");
    }

    if (table.containsKey(trimmedName)) {
      final current = table[trimmedName]!;

      if (immutable) {
        throw SemanticError("Variable '$trimmedName' is already defined");
      }

      if (current.immutable) {
        throw SemanticError("cannot change the value of $trimmedName");
      }

      current.value = value;
      return;
    }

    table[trimmedName] = SymbolEntry(value: value, immutable: immutable);
  }

  int resolve(String name) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!table.containsKey(trimmedName)) {
      throw SemanticError("Variable '$trimmedName' is not defined");
    }

    return table[trimmedName]!.value;
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
    while (position < source.length &&
        source[position] != '\n' &&
        RegExp(r'\s').hasMatch(source[position])) {
      position++;
    }
  }

  bool _isLetter(String char) => RegExp(r'^[a-zA-Z]$').hasMatch(char);

  bool _isLetterOrDigitOrUnderscore(String char) {
    return RegExp(r'^[a-zA-Z0-9_]$').hasMatch(char);
  }

  void selectToken() {
    _skipSpaces();

    if (position >= source.length) {
      next = Token('EOF', '', position);
      return;
    }

    final currentChar = source[position];

    if (currentChar == '+') {
      next = Token('PLUS', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '-') {
      next = Token('MINUS', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '^') {
      next = Token('XOR', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '*') {
      if (position + 1 < source.length && source[position + 1] == '*') {
        next = Token('POWER', '**', position);
        position += 2;
        return;
      }
      next = Token('MULT', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '/') {
      next = Token('DIV', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '(') {
      next = Token('OPEN_PAR', currentChar, position);
      position++;
      return;
    }

    if (currentChar == ')') {
      next = Token('CLOSE_PAR', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '!') {
      next = Token('FACT', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '\n') {
      next = Token('END', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '=') {
      next = Token('ASSIGN', currentChar, position);
      position++;
      return;
    }

    if (_isLetter(currentChar)) {
      final start = position;
      var identifier = '';

      while (position < source.length &&
          _isLetterOrDigitOrUnderscore(source[position])) {
        identifier += source[position];
        position++;
      }

      if (identifier == 'print') {
        next = Token('PRINT', identifier, start);
        return;
      }

      if (identifier == 'imut') {
        next = Token('IMUT', identifier, start);
        return;
      }

      next = Token('IDEN', identifier, start);
      return;
    }

    if (int.tryParse(currentChar) != null) {
      final start = position;
      var number = '';
      while (position < source.length &&
          int.tryParse(source[position]) != null) {
        number += source[position];
        position++;
      }
      next = Token('INT', number, start);
      return;
    }

    throw CompilerError(
      sourceTag: 'Lexer',
      code: 'E_LEX_INVALID_CHAR',
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

    while (lexer.next.type == 'PLUS' ||
        lexer.next.type == 'MINUS' ||
        lexer.next.type == 'XOR') {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseTerm());
    }

    return node;
  }

  Node parseProgram() {
    List<Node> statements = [];
    while (lexer.next.type != 'EOF') {
      if (lexer.next.type == 'END') {
        lexer.selectToken();
        continue;
      }
      statements.add(parseStatement());
    }
    return Block(statements);
  }

  Node parseStatement() {
    if (lexer.next.type == 'END') {
      lexer.selectToken();
      return NoOp();
    }

    if (lexer.next.type == 'IMUT') {
      lexer.selectToken();

      if (lexer.next.type != 'IDEN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_IDENTIFIER',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected identifier after 'imut', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      final identName = lexer.next.value;
      lexer.selectToken();

      if (lexer.next.type != 'ASSIGN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_ASSIGN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '=' after immutable identifier '$identName', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final expr = parseExpression();

      if (lexer.next.type != 'END' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after immutable declaration, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'END') {
        lexer.selectToken();
      }

      return Assignment(identName, expr, immutable: true);
    }

    if (lexer.next.type == 'IDEN') {
      final identName = lexer.next.value;
      lexer.selectToken();

      if (lexer.next.type != 'ASSIGN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_ASSIGN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '=' after identifier '\'$identName\'', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final expr = parseExpression();

      if (lexer.next.type != 'END' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after assignment, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'END') {
        lexer.selectToken();
      }

      return Assignment(identName, expr);
    }

    if (lexer.next.type == 'PRINT') {
      lexer.selectToken();

      if (lexer.next.type != 'OPEN_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_OPEN_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '(' after print, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final expr = parseExpression();

      if (lexer.next.type != 'CLOSE_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_CLOSE_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected ')' after expression in print, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'END' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after print statement, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'END') {
        lexer.selectToken();
      }

      return Print(expr);
    }

    throw CompilerError(
      sourceTag: 'Parser',
      code: 'E_PAR_EXPECTED_STATEMENT',
      position: lexer.next.position,
      expression: lexer.source,
      message:
          "Expected statement (assignment, print, or empty line), found '${lexer.next.value}' (${lexer.next.type})",
    );
  }

  Node parseTerm() {
    Node node = parseFactor();

    while (lexer.next.type == 'MULT' || lexer.next.type == 'DIV') {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseFactor());
    }

    return node;
  }

  Node parseFactor() {
    if (lexer.next.type == 'MINUS') {
      final op = lexer.next.value;
      lexer.selectToken();
      return UnOp(op, parseFactor());
    }

    if (lexer.next.type == 'PLUS') {
      final op = lexer.next.value;
      lexer.selectToken();
      return UnOp(op, parseFactor());
    }

    if (lexer.next.type == 'OPEN_PAR') {
      lexer.selectToken();
      Node node = parseExpression();
      if (lexer.next.type != 'CLOSE_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_UNMATCHED_OPEN_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected closing parenthesis ')', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();
      while (lexer.next.type == 'FACT') {
        lexer.selectToken();
        node = UnOp('!', node);
      }
      return node;
    }

    if (lexer.next.type == 'INT') {
      Node node = IntVal(int.parse(lexer.next.value));
      lexer.selectToken();
      while (lexer.next.type == 'FACT') {
        lexer.selectToken();
        node = UnOp('!', node);
      }
      return node;
    }

    if (lexer.next.type == 'IDEN') {
      final identName = lexer.next.value;
      lexer.selectToken();
      return Identifier(identName);
    }

    throw CompilerError(
      sourceTag: 'Parser',
      code: 'E_PAR_EXPECTED_FACTOR',
      position: lexer.next.position,
      expression: lexer.source,
      message:
          "Expected number, identifier, sign (+/-), or '(', found '${lexer.next.value}' (${lexer.next.type})",
    );
  }

  int run(String code) {
    lexer = Lexer(code);
    final root = parseProgram();

    if (lexer.next.type != 'EOF') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_UNEXPECTED_TOKEN',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Unexpected token '${lexer.next.value}' (${lexer.next.type}) after end of expression",
      );
    }

    return root.evaluate(SymbolTable());
  }
}

void main(List<String> args) {
  if (args.isEmpty) {
    stdout.writeln(
      'Use: dart run main.dart "10 + 5 - 3" | dart run main.dart teste.lua',
    );
    exit(64);
  }

  final input = args.join(' ');
  final inputFile = File(input);

  String sourceCode;
  if (args.length == 1 && inputFile.existsSync()) {
    sourceCode = inputFile.readAsStringSync();
  } else {
    sourceCode = input;
  }

  final code = Prepro.filter(sourceCode);
  final parser = Parser();

  try {
    parser.run(code);
  } on SemanticError catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } on CompilerError catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  } catch (e) {
    stderr.writeln('[Internal] E_INTERNAL: ${e.toString()}');
    exit(1);
  }
}
