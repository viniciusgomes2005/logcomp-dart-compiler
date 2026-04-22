import 'dart:io';

class Token {
  final String type;
  final String value;
  final int position;

  Token(this.type, this.value, this.position);
}

class Variable {
  dynamic value;
  final String type;
  final bool immutable;

  Variable({required this.value, required this.type, this.immutable = false});

  Variable copy() => Variable(value: value, type: type, immutable: immutable);
}

abstract class Node {
  final dynamic value;
  final List<Node> children;

  Node(this.value, [List<Node>? children]) : children = children ?? [];

  Variable evaluate(SymbolTable st);
}

class IntVal extends Node {
  IntVal(int value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as int, type: 'number');
}

class FloatVal extends Node {
  FloatVal(double value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as double, type: 'float');
}

class BoolVal extends Node {
  BoolVal(bool value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as bool, type: 'boolean');
}

class StringVal extends Node {
  StringVal(String value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as String, type: 'string');
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

  bool _isNumericType(String type) => type == 'number' || type == 'float';

  @override
  Variable evaluate(SymbolTable st) {
    final operand = children[0].evaluate(st);

    switch (value) {
      case '+':
        if (!_isNumericType(operand.type)) {
          throw SemanticError("Unary '+' expects numeric operand");
        }
        return operand.copy();
      case '-':
        if (!_isNumericType(operand.type)) {
          throw SemanticError("Unary '-' expects numeric operand");
        }
        if (operand.type == 'float') {
          return Variable(value: -(operand.value as double), type: 'float');
        }
        return Variable(value: -(operand.value as int), type: 'number');
      case 'not':
        return Variable(value: !_toBoolean(operand), type: 'boolean');
      case '!':
        if (operand.type != 'number') {
          throw SemanticError('Factorial is only defined for integer numbers');
        }
        final n = operand.value as int;
        if (n < 0) {
          throw SemanticError(
            'Factorial is only defined for non-negative integers',
          );
        }
        return Variable(value: _factorial(n), type: 'number');
      default:
        throw SemanticError("Invalid unary operator '$value'");
    }
  }
}

class CastOp extends Node {
  CastOp(String targetType, Node operand) : super(targetType, [operand]);

  bool _isNumericType(String type) => type == 'number' || type == 'float';

  @override
  Variable evaluate(SymbolTable st) {
    final input = children[0].evaluate(st);
    final target = value as String;

    switch (target) {
      case 'number':
        if (input.type == 'number') {
          return input.copy();
        }
        if (input.type == 'float') {
          return Variable(
            value: (input.value as double).round(),
            type: 'number',
          );
        }
        if (input.type == 'boolean') {
          return Variable(value: (input.value as bool) ? 1 : 0, type: 'number');
        }
        if (input.type == 'string') {
          final raw = (input.value as String).trim();
          final asInt = int.tryParse(raw);
          if (asInt != null) {
            return Variable(value: asInt, type: 'number');
          }
          final asDouble = double.tryParse(raw);
          if (asDouble != null) {
            return Variable(value: asDouble.round(), type: 'number');
          }
          throw SemanticError("Cannot cast '$raw' to number");
        }
        break;
      case 'float':
        if (input.type == 'float') {
          return input.copy();
        }
        if (input.type == 'number') {
          return Variable(
            value: (input.value as int).toDouble(),
            type: 'float',
          );
        }
        if (input.type == 'boolean') {
          return Variable(
            value: (input.value as bool) ? 1.0 : 0.0,
            type: 'float',
          );
        }
        if (input.type == 'string') {
          final raw = (input.value as String).trim();
          final parsed = double.tryParse(raw);
          if (parsed == null) {
            throw SemanticError("Cannot cast '$raw' to float");
          }
          return Variable(value: parsed, type: 'float');
        }
        break;
      case 'boolean':
        if (input.type == 'boolean') {
          return input.copy();
        }
        if (_isNumericType(input.type)) {
          final numericValue = input.type == 'float'
              ? input.value as double
              : input.value as int;
          return Variable(value: numericValue != 0, type: 'boolean');
        }
        if (input.type == 'string') {
          final normalized = (input.value as String).trim().toLowerCase();
          if (normalized == 'true') {
            return Variable(value: true, type: 'boolean');
          }
          if (normalized == 'false') {
            return Variable(value: false, type: 'boolean');
          }
          throw SemanticError(
            "Cannot cast string '${input.value}' to boolean. Use 'true' or 'false'",
          );
        }
        break;
      case 'string':
        return Variable(value: _toStringValue(input), type: 'string');
      default:
        throw SemanticError("Unsupported cast target type '$target'");
    }

    throw SemanticError(
      "Cannot cast value of type '${input.type}' to '$target'",
    );
  }
}

class BinOp extends Node {
  BinOp(String op, Node left, Node right) : super(op, [left, right]);

  bool _isNumericType(String type) => type == 'number' || type == 'float';

  Variable _numericResult(num value, bool hasFloat) {
    if (hasFloat) {
      return Variable(value: value.toDouble(), type: 'float');
    }
    return Variable(value: value.toInt(), type: 'number');
  }

  @override
  Variable evaluate(SymbolTable st) {
    final left = children[0].evaluate(st);
    final right = children[1].evaluate(st);

    switch (value) {
      case '+':
        if (_isNumericType(left.type) && _isNumericType(right.type)) {
          final hasFloat = left.type == 'float' || right.type == 'float';
          final leftNum = left.type == 'float'
              ? left.value as double
              : left.value as int;
          final rightNum = right.type == 'float'
              ? right.value as double
              : right.value as int;
          return _numericResult(leftNum + rightNum, hasFloat);
        }
        throw SemanticError("Operator '+' expects numeric operands");

      case '..':
        return Variable(
          value: '${_toStringValue(left)}${_toStringValue(right)}',
          type: 'string',
        );

      case '-':
      case '*':
      case '/':
        if (!(_isNumericType(left.type) && _isNumericType(right.type))) {
          throw SemanticError("Operator '$value' expects numeric operands");
        }

        final hasFloat = left.type == 'float' || right.type == 'float';
        final leftNum = left.type == 'float'
            ? left.value as double
            : left.value as int;
        final rightNum = right.type == 'float'
            ? right.value as double
            : right.value as int;

        if (value == '/' && rightNum == 0) {
          throw SemanticError('Division by zero is not allowed');
        }

        if (value == '-' && hasFloat) {
          return Variable(value: leftNum - rightNum, type: 'float');
        }
        if (value == '*' && hasFloat) {
          return Variable(value: leftNum * rightNum, type: 'float');
        }
        if (value == '/') {
          if (hasFloat) {
            return Variable(value: leftNum / rightNum, type: 'float');
          }
          return Variable(value: (leftNum ~/ rightNum), type: 'number');
        }

        if (value == '-' && !hasFloat) {
          return Variable(
            value: leftNum.toInt() - rightNum.toInt(),
            type: 'number',
          );
        }

        return Variable(
          value: leftNum.toInt() * rightNum.toInt(),
          type: 'number',
        );

      case '^':
        if (left.type != 'number' || right.type != 'number') {
          throw SemanticError("Operator '^' expects integer numbers");
        }
        return Variable(
          value: (left.value as int) ^ (right.value as int),
          type: 'number',
        );

      case 'and':
        return Variable(value: _toBoolean(left) && _toBoolean(right), type: 'boolean');
      case 'or':
        return Variable(value: _toBoolean(left) || _toBoolean(right), type: 'boolean');

      case '==':
        if (_isNumericType(left.type) && _isNumericType(right.type)) {
          final leftNum = left.type == 'float'
              ? left.value as double
              : left.value as int;
          final rightNum = right.type == 'float'
              ? right.value as double
              : right.value as int;
          return Variable(value: leftNum == rightNum, type: 'boolean');
        }
        if (left.type == right.type &&
            (left.type == 'string' || left.type == 'boolean')) {
          return Variable(value: left.value == right.value, type: 'boolean');
        }
        throw SemanticError(
          "Operator '==' expects both sides with compatible types",
        );

      case '<':
      case '>':
        if (_isNumericType(left.type) && _isNumericType(right.type)) {
          final leftNum = left.type == 'float'
              ? left.value as double
              : left.value as int;
          final rightNum = right.type == 'float'
              ? right.value as double
              : right.value as int;
          return Variable(
            value: value == '<' ? leftNum < rightNum : leftNum > rightNum,
            type: 'boolean',
          );
        }
        if (left.type == 'string' && right.type == 'string') {
          final leftStr = left.value as String;
          final rightStr = right.value as String;
          return Variable(
            value: value == '<'
                ? leftStr.compareTo(rightStr) < 0
                : leftStr.compareTo(rightStr) > 0,
            type: 'boolean',
          );
        }
        throw SemanticError("Operator '$value' expects numeric or string operands");

      default:
        throw SemanticError("Invalid binary operator '$value'");
    }
  }
}

class Identifier extends Node {
  Identifier(String name) : super(name, []);

  @override
  Variable evaluate(SymbolTable st) {
    return st.resolve(value as String);
  }
}

class VarDec extends Node {
  VarDec(String variableType, List<Node> children)
    : super(variableType, children);

  @override
  Variable evaluate(SymbolTable st) {
    final identifier = children[0] as Identifier;
    final variableType = value as String;

    Variable? initializedValue;
    if (children.length == 2) {
      initializedValue = children[1].evaluate(st);
    }

    st.createVariable(
      identifier.value as String,
      variableType,
      initialValue: initializedValue,
    );

    return initializedValue ?? st.resolve(identifier.value as String);
  }
}

class Print extends Node {
  Print(Node expression) : super('print', [expression]);

  @override
  Variable evaluate(SymbolTable st) {
    final evaluated = children[0].evaluate(st);
    stdout.writeln(_toStringValue(evaluated));
    return evaluated;
  }
}

class Read extends Node {
  Read() : super('read', []);

  @override
  Variable evaluate(SymbolTable st) {
    final input = stdin.readLineSync();
    if (input == null) {
      throw SemanticError('Read failed: no input provided');
    }

    final trimmed = input.trim();

    if (trimmed.contains('.')) {
      final floatValue = double.tryParse(trimmed);
      if (floatValue != null) {
        return Variable(value: floatValue, type: 'float');
      }
    }

    final intValue = int.tryParse(trimmed);
    if (intValue != null) {
      return Variable(value: intValue, type: 'number');
    }

    throw SemanticError("Read expected a number, found '$input'");
  }
}

class Assignment extends Node {
  final bool immutable;

  Assignment(String variableName, Node expression, {this.immutable = false})
    : super(variableName, [expression]);

  @override
  Variable evaluate(SymbolTable st) {
    final resolved = children[0].evaluate(st);

    if (immutable) {
      st.createVariable(
        value as String,
        resolved.type,
        initialValue: resolved,
        immutable: true,
      );
      return resolved;
    }

    st.setVariable(value as String, resolved);
    return resolved;
  }
}

class Block extends Node {
  Block(List<Node> statements) : super('block', statements);

  @override
  Variable evaluate(SymbolTable st) {
    var result = Variable(value: 0, type: 'number');
    for (final stmt in children) {
      result = stmt.evaluate(st);
    }
    return result;
  }
}

class If extends Node {
  If(Node condition, Node thenBlock, [Node? elseBlock])
    : super(
        'if',
        elseBlock == null
            ? [condition, thenBlock]
            : [condition, thenBlock, elseBlock],
      );

  @override
  Variable evaluate(SymbolTable st) {
    final conditionValue = children[0].evaluate(st);
    if (_toBoolean(conditionValue)) {
      return children[1].evaluate(st);
    }

    if (children.length == 3) {
      return children[2].evaluate(st);
    }

    return Variable(value: 0, type: 'number');
  }
}

class While extends Node {
  While(Node condition, Node block) : super('while', [condition, block]);

  @override
  Variable evaluate(SymbolTable st) {
    var result = Variable(value: 0, type: 'number');
    while (_toBoolean(children[0].evaluate(st))) {
      result = children[1].evaluate(st);
    }
    return result;
  }
}

class IfExpression extends Node {
  IfExpression(Node condition, Node thenExpr, Node elseExpr)
    : super('if_expr', [condition, thenExpr, elseExpr]);

  @override
  Variable evaluate(SymbolTable st) {
    final conditionValue = children[0].evaluate(st);
    if (_toBoolean(conditionValue)) {
      return children[1].evaluate(st);
    }
    return children[2].evaluate(st);
  }
}

class For extends Node {
  For(String variableName, Node startExpr, Node endExpr, Node body)
    : super(variableName, [startExpr, endExpr, body]);

  @override
  Variable evaluate(SymbolTable st) {
    final startVar = children[0].evaluate(st);
    final endVar = children[1].evaluate(st);

    if (startVar.type != 'number' || endVar.type != 'number') {
      throw SemanticError('for loop bounds must be integer numbers');
    }

    final start = startVar.value as int;
    final end = endVar.value as int;

    if (!st.exists(value as String)) {
      st.createVariable(value as String, 'number');
    }

    var iterator = start;
    var result = Variable(value: 0, type: 'number');

    while (iterator <= end) {
      st.setVariable(
        value as String,
        Variable(value: iterator, type: 'number'),
      );
      result = children[2].evaluate(st);
      iterator++;
    }

    st.setVariable(value as String, Variable(value: iterator, type: 'number'));
    return result;
  }
}

class NoOp extends Node {
  NoOp() : super('noop', []);

  @override
  Variable evaluate(SymbolTable st) => Variable(value: 0, type: 'number');
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
  static String _removeLineComments(String code) {
    final output = StringBuffer();
    var i = 0;
    var insideString = false;

    while (i < code.length) {
      final current = code[i];
      final next = i + 1 < code.length ? code[i + 1] : '';

      if (current == '"') {
        insideString = !insideString;
        output.write(current);
        i++;
        continue;
      }

      if (!insideString && current == '-' && next == '-') {
        while (i < code.length && code[i] != '\n') {
          i++;
        }
        continue;
      }

      output.write(current);
      i++;
    }

    return output.toString();
  }

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
    final withoutComments = _removeLineComments(code);

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

class SymbolTable {
  final Map<String, Variable> table = {};

  bool _isValidIdentifier(String name) {
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(name);
  }

  bool _isNumericType(String type) => type == 'number' || type == 'float';

  bool exists(String name) {
    final trimmedName = name.trim();
    return table.containsKey(trimmedName);
  }

  void _assertTypeCompatibility(String expectedType, Variable value) {
    if (expectedType == value.type) {
      return;
    }

    if (_isNumericType(expectedType) && _isNumericType(value.type)) {
      return;
    }

    throw SemanticError(
      "Type mismatch: expected '$expectedType', found '${value.type}'",
    );
  }

  Variable _coerceToType(String targetType, Variable input) {
    if (targetType == input.type) {
      return input.copy();
    }

    if (targetType == 'float' && input.type == 'number') {
      return Variable(value: (input.value as int).toDouble(), type: 'float');
    }

    if (targetType == 'number' && input.type == 'float') {
      return Variable(value: (input.value as double).round(), type: 'number');
    }

    return input.copy();
  }

  Variable _defaultValueForType(String type) {
    switch (type) {
      case 'number':
        return Variable(value: 0, type: 'number');
      case 'float':
        return Variable(value: 0.0, type: 'float');
      case 'boolean':
        return Variable(value: false, type: 'boolean');
      case 'string':
        return Variable(value: '', type: 'string');
      default:
        throw SemanticError("Unsupported type '$type'");
    }
  }

  void createVariable(
    String name,
    String type, {
    Variable? initialValue,
    bool immutable = false,
  }) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!_isValidIdentifier(trimmedName)) {
      throw SemanticError("Invalid identifier '$name'");
    }

    if (table.containsKey(trimmedName)) {
      throw SemanticError("Variable '$trimmedName' is already declared");
    }

    if (initialValue != null) {
      _assertTypeCompatibility(type, initialValue);
      final coerced = _coerceToType(type, initialValue);
      table[trimmedName] = Variable(
        value: coerced.value,
        type: type,
        immutable: immutable,
      );
      return;
    }

    final defaultVar = _defaultValueForType(type);
    table[trimmedName] = Variable(
      value: defaultVar.value,
      type: type,
      immutable: immutable,
    );
  }

  void setVariable(String name, Variable value) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!table.containsKey(trimmedName)) {
      throw SemanticError("Variable '$trimmedName' is not declared");
    }

    final current = table[trimmedName]!;

    if (current.immutable) {
      throw SemanticError("cannot change the value of $trimmedName");
    }

    _assertTypeCompatibility(current.type, value);
    final coerced = _coerceToType(current.type, value);
    current.value = coerced.value;
  }

  Variable resolve(String name) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!table.containsKey(trimmedName)) {
      throw SemanticError("Variable '$trimmedName' is not declared");
    }

    final current = table[trimmedName]!;
    return Variable(value: current.value, type: current.type);
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

    if (currentChar == '"') {
      final start = position;
      position++;
      final literal = StringBuffer();

      while (position < source.length && source[position] != '"') {
        literal.write(source[position]);
        position++;
      }

      if (position >= source.length) {
        throw CompilerError(
          sourceTag: 'Lexer',
          code: 'E_LEX_UNTERMINATED_STRING',
          position: start,
          expression: source,
          message: 'Unterminated string literal',
        );
      }

      position++;
      next = Token('STR', literal.toString(), start);
      return;
    }

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

    if (currentChar == '.') {
      if (position + 1 < source.length && source[position + 1] == '.') {
        next = Token('CONCAT', '..', position);
        position += 2;
        return;
      }
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

    if (currentChar == ',') {
      next = Token('COMMA', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '!') {
      next = Token('FACT', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '\n') {
      next = Token('EOL', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '=') {
      if (position + 1 < source.length && source[position + 1] == '=') {
        next = Token('EQ', '==', position);
        position += 2;
        return;
      }
      next = Token('ASSIGN', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '<') {
      next = Token('LT', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '>') {
      next = Token('GT', currentChar, position);
      position++;
      return;
    }

    if (currentChar == '&') {
      if (position + 1 < source.length && source[position + 1] == '&') {
        next = Token('AND', 'and', position);
        position += 2;
        return;
      }
      throw CompilerError(
        sourceTag: 'Lexer',
        code: 'E_LEX_INVALID_CHAR',
        position: position,
        expression: source,
        message: "Unexpected '&'. Did you mean '&&' or 'and'?",
      );
    }

    if (currentChar == '|') {
      if (position + 1 < source.length && source[position + 1] == '|') {
        next = Token('OR', 'or', position);
        position += 2;
        return;
      }
      throw CompilerError(
        sourceTag: 'Lexer',
        code: 'E_LEX_INVALID_CHAR',
        position: position,
        expression: source,
        message: "Unexpected '|'. Did you mean '||' or 'or'?",
      );
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

      if (identifier == 'if') {
        next = Token('IF', identifier, start);
        return;
      }

      if (identifier == 'while') {
        next = Token('WHILE', identifier, start);
        return;
      }

      if (identifier == 'for') {
        next = Token('FOR', identifier, start);
        return;
      }

      if (identifier == 'else') {
        next = Token('ELSE', identifier, start);
        return;
      }

      if (identifier == 'read') {
        next = Token('READ', identifier, start);
        return;
      }

      if (identifier == 'then') {
        next = Token('OPEN_IF_BRA', identifier, start);
        return;
      }

      if (identifier == 'do') {
        next = Token('OPEN_BRA', identifier, start);
        return;
      }

      if (identifier == 'end') {
        next = Token('CLOSE_BRA', identifier, start);
        return;
      }

      if (identifier == 'and') {
        next = Token('AND', identifier, start);
        return;
      }

      if (identifier == 'or') {
        next = Token('OR', identifier, start);
        return;
      }

      if (identifier == 'not') {
        next = Token('NOT', identifier, start);
        return;
      }

      if (identifier == 'imut') {
        next = Token('IMUT', identifier, start);
        return;
      }

      if (identifier == 'local') {
        next = Token('VAR', identifier, start);
        return;
      }

      if (identifier == 'true' || identifier == 'false') {
        next = Token('BOOL', identifier, start);
        return;
      }

      if (identifier == 'number' ||
          identifier == 'boolean' ||
          identifier == 'string' ||
          identifier == 'float') {
        next = Token('TYPE', identifier, start);
        return;
      }

      next = Token('IDEN', identifier, start);
      return;
    }

    if (int.tryParse(currentChar) != null) {
      final start = position;
      var number = '';
      var hasDot = false;

      while (position < source.length) {
        final ch = source[position];
        if (int.tryParse(ch) != null) {
          number += ch;
          position++;
          continue;
        }

        if (ch == '.' && !hasDot) {
          if (position + 1 < source.length &&
              int.tryParse(source[position + 1]) != null) {
            hasDot = true;
            number += ch;
            position++;
            continue;
          }
        }

        break;
      }

      next = Token(hasDot ? 'FLOAT' : 'INT', number, start);
      return;
    }

    throw CompilerError(
      sourceTag: 'Lexer',
      code: 'E_LEX_INVALID_CHAR',
      position: position,
      expression: source,
      message:
          "Invalid character '$currentChar' (ASCII ${currentChar.codeUnitAt(0)}). Expected: digits, identifiers, operators, parentheses, or spaces",
    );
  }
}

class Parser {
  late Lexer lexer;

  Node parseExpression() {
    Node node = parseTerm();

    while (lexer.next.type == 'PLUS' ||
        lexer.next.type == 'MINUS' ||
        lexer.next.type == 'XOR' ||
        lexer.next.type == 'CONCAT') {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseTerm());
    }

    return node;
  }

  Node parseProgram() {
    List<Node> statements = [];
    while (lexer.next.type != 'EOF') {
      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
        continue;
      }
      statements.add(parseStatement());
    }
    return Block(statements);
  }

  Node parseBlock(List<String> stopTokens) {
    final statements = <Node>[];

    while (lexer.next.type != 'EOF' && !stopTokens.contains(lexer.next.type)) {
      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
        continue;
      }
      statements.add(parseStatement());
    }

    return Block(statements);
  }

  Node parseBoolExpression() {
    Node node = parseBoolTerm();

    while (lexer.next.type == 'OR') {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseBoolTerm());
    }

    return node;
  }

  Node parseBoolTerm() {
    Node node = parseRelExpression();

    while (lexer.next.type == 'AND') {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseRelExpression());
    }

    return node;
  }

  Node parseRelExpression() {
    Node node = parseExpression();

    while (lexer.next.type == 'EQ' ||
        lexer.next.type == 'LT' ||
        lexer.next.type == 'GT') {
      final op = lexer.next.value;
      lexer.selectToken();
      node = BinOp(op, node, parseExpression());
    }

    return node;
  }

  Node parseStatement() {
    if (lexer.next.type == 'EOL') {
      lexer.selectToken();
      return NoOp();
    }

    if (lexer.next.type == 'IF') {
      lexer.selectToken();

      if (lexer.next.type != 'OPEN_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_OPEN_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '(' after if, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final condition = parseBoolExpression();

      if (lexer.next.type != 'CLOSE_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_CLOSE_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected ')' after if condition, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'OPEN_IF_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_THEN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'then' after if condition, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after 'then', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final thenBlock = parseBlock(['ELSE', 'CLOSE_BRA']);
      Node? elseBlock;

      if (lexer.next.type == 'ELSE') {
        lexer.selectToken();

        if (lexer.next.type != 'EOL') {
          throw CompilerError(
            sourceTag: 'Parser',
            code: 'E_PAR_EXPECTED_EOL',
            position: lexer.next.position,
            expression: lexer.source,
            message:
                "Expected end of line after 'else', found '${lexer.next.value}' (${lexer.next.type})",
          );
        }
        lexer.selectToken();

        elseBlock = parseBlock(['CLOSE_BRA']);
      }

      if (lexer.next.type != 'CLOSE_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_END',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'end' to close if block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after if block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
      }

      return If(condition, thenBlock, elseBlock);
    }

    if (lexer.next.type == 'WHILE') {
      lexer.selectToken();

      if (lexer.next.type != 'OPEN_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_OPEN_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '(' after while, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final condition = parseBoolExpression();

      if (lexer.next.type != 'CLOSE_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_CLOSE_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected ')' after while condition, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'OPEN_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_DO',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'do' after while condition, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after 'do', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final body = parseBlock(['CLOSE_BRA']);

      if (lexer.next.type != 'CLOSE_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_END',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'end' to close while block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after while block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
      }

      return While(condition, body);
    }

    if (lexer.next.type == 'FOR') {
      lexer.selectToken();

      if (lexer.next.type != 'IDEN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_IDENTIFIER',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected identifier after for, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      final loopVar = lexer.next.value;
      lexer.selectToken();

      if (lexer.next.type != 'ASSIGN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_ASSIGN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '=' after for identifier '$loopVar', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final startExpr = parseBoolExpression();

      if (lexer.next.type != 'COMMA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_COMMA',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected ',' after for start expression, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final endExpr = parseBoolExpression();

      if (lexer.next.type != 'OPEN_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_DO',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'do' after for bounds, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after 'do', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final body = parseBlock(['CLOSE_BRA']);

      if (lexer.next.type != 'CLOSE_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_END',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'end' to close for block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after for block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
      }

      return For(loopVar, startExpr, endExpr, body);
    }

    if (lexer.next.type == 'OPEN_BRA') {
      lexer.selectToken();

      if (lexer.next.type != 'EOL') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after 'do', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final body = parseBlock(['CLOSE_BRA']);

      if (lexer.next.type != 'CLOSE_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_END',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'end' to close do block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after do block, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
      }

      return body;
    }

    if (lexer.next.type == 'VAR') {
      lexer.selectToken();

      if (lexer.next.type != 'IDEN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_IDENTIFIER',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected identifier after 'local', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      final identName = lexer.next.value;
      lexer.selectToken();

      if (lexer.next.type != 'TYPE') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_TYPE',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected type after identifier '$identName', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      final varType = lexer.next.value;
      lexer.selectToken();

      Node? expr;
      if (lexer.next.type == 'ASSIGN') {
        lexer.selectToken();
        expr = parseBoolExpression();
      }

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after variable declaration, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
      }

      return VarDec(
        varType,
        expr == null ? [Identifier(identName)] : [Identifier(identName), expr],
      );
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

      final expr = parseBoolExpression();

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after immutable declaration, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
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

      final expr = parseBoolExpression();

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after assignment, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
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

      final expr = parseBoolExpression();

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

      if (lexer.next.type != 'EOL' && lexer.next.type != 'EOF') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_EOL',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected end of line after print statement, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      if (lexer.next.type == 'EOL') {
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
          "Expected statement (if, while, for, local declaration, assignment, print, or empty line), found '${lexer.next.value}' (${lexer.next.type})",
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

    if (lexer.next.type == 'NOT') {
      final op = lexer.next.value;
      lexer.selectToken();
      return UnOp(op, parseFactor());
    }

    if (lexer.next.type == 'OPEN_PAR') {
      lexer.selectToken();

      if (lexer.next.type == 'TYPE') {
        final castType = lexer.next.value;
        lexer.selectToken();

        if (lexer.next.type != 'CLOSE_PAR') {
          throw CompilerError(
            sourceTag: 'Parser',
            code: 'E_PAR_EXPECTED_CLOSE_PAREN',
            position: lexer.next.position,
            expression: lexer.source,
            message:
                "Expected ')' after cast type '$castType', found '${lexer.next.value}' (${lexer.next.type})",
          );
        }
        lexer.selectToken();
        return CastOp(castType, parseFactor());
      }

      Node node = parseBoolExpression();
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

    if (lexer.next.type == 'IF') {
      lexer.selectToken();

      final condition = parseBoolExpression();

      if (lexer.next.type != 'OPEN_IF_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_THEN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'then' in if expression, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final thenExpr = parseBoolExpression();

      if (lexer.next.type != 'ELSE') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_ELSE',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'else' in if expression, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      final elseExpr = parseBoolExpression();

      if (lexer.next.type != 'CLOSE_BRA') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_END',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected 'end' to close if expression, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      return IfExpression(condition, thenExpr, elseExpr);
    }

    if (lexer.next.type == 'READ') {
      lexer.selectToken();

      if (lexer.next.type != 'OPEN_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_OPEN_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected '(' after read, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'CLOSE_PAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_CLOSE_PAREN',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected ')' after read, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      return Read();
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

    if (lexer.next.type == 'FLOAT') {
      return _parseFloatLiteral();
    }

    if (lexer.next.type == 'STR') {
      final node = StringVal(lexer.next.value);
      lexer.selectToken();
      return node;
    }

    if (lexer.next.type == 'BOOL') {
      final node = BoolVal(lexer.next.value == 'true');
      lexer.selectToken();
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
          "Expected number, boolean, string, identifier, read(), unary operator (+/-/not), or '(', found '${lexer.next.value}' (${lexer.next.type})",
    );
  }

  Node _parseFloatLiteral() {
    Node node = FloatVal(double.parse(lexer.next.value));
    lexer.selectToken();

    while (lexer.next.type == 'FACT') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_INVALID_FACTORIAL_FLOAT',
        position: lexer.next.position,
        expression: lexer.source,
        message: 'Factorial is only valid for integers',
      );
    }

    return node;
  }

  Variable run(String code) {
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

bool _toBoolean(Variable variable) {
  if (variable.type == 'boolean') {
    return variable.value as bool;
  }

  throw SemanticError(
    "Value of type '${variable.type}' cannot be used as boolean",
  );
}

String _toStringValue(Variable variable) {
  if (variable.type == 'boolean') {
    return (variable.value as bool) ? 'true' : 'false';
  }

  return variable.value.toString();
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
