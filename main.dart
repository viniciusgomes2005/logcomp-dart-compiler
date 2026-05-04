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
  final bool isFunction;
  final bool isReturn;
  final int shift;

  Variable({
    required this.value,
    required this.type,
    this.immutable = false,
    this.isFunction = false,
    this.isReturn = false,
    this.shift = 0,
  });

  Variable copy({bool? isReturn}) => Variable(
    value: value,
    type: type,
    immutable: immutable,
    isFunction: isFunction,
    isReturn: isReturn ?? this.isReturn,
    shift: shift,
  );
}

class RuntimeOutput {
  static List<String>? captured;

  static void writelnValue(String value) {
    captured?.add(value);
    stdout.writeln(value);
  }
}

class Code {
  static final List<String> instructions = [];

  static void reset() {
    instructions.clear();
  }

  static void append(String code) {
    instructions.add(code);
  }

  static void dump(String filename) {
    final file = File(filename);
    file.writeAsStringSync('''
section .data
  format_out: db "%d", 10, 0 ; format do printf
  format_in: db "%d", 0 ; format do scanf
  scan_int: dd 0; 32-bits integer

section .text
  extern printf ; usar _printf para Windows
  extern scanf ; usar _scanf para Windows
  ; extern _ExitProcess@4 ; usar para Windows
  global _start ; início do programa

_start:
  push ebp ; guarda o EBP
  mov ebp, esp ; zera a pilha

  ; aqui começa o codigo gerado:

${instructions.join('\n')}

  ; aqui termina o código gerado

  mov esp, ebp ; reestabelece a pilha
  pop ebp

  ; chamada da interrupcao de saida (Linux)
  mov eax, 1
  xor ebx, ebx
  int 0x80
  ; Para Windows:
  ; push dword 0
  ; call _ExitProcess@4
''');
  }

  static void appendPrintInt(int value) {
    append('  mov eax, $value');
    append('  push eax ; empilha valor para print');
    append('  push format_out ; formato int de saida');
    append('  call printf');
    append('  add esp, 8 ; limpa os argumentos');
  }
}

abstract class Node {
  static int id = 0;

  static int newId() {
    id++;
    return id;
  }

  final dynamic value;
  final List<Node> children;
  late final int uniqueId;

  Node(this.value, [List<Node>? children])
    : children = children ?? [],
      uniqueId = Node.newId();

  Variable evaluate(SymbolTable st);
  void generate(SymbolTable st);
}

class IntVal extends Node {
  IntVal(int value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as int, type: 'number');

  @override
  void generate(SymbolTable st) {
    Code.append('  mov eax, $value');
  }
}

class FloatVal extends Node {
  FloatVal(double value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as double, type: 'float');

  @override
  void generate(SymbolTable st) {
    throw SemanticError('Assembly generation does not support float values');
  }
}

class BoolVal extends Node {
  BoolVal(bool value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as bool, type: 'boolean');

  @override
  void generate(SymbolTable st) {
    Code.append('  mov eax, ${value == true ? 1 : 0}');
  }
}

class StringVal extends Node {
  StringVal(String value) : super(value);

  @override
  Variable evaluate(SymbolTable st) =>
      Variable(value: value as String, type: 'string');

  @override
  void generate(SymbolTable st) {
    throw SemanticError('Assembly generation does not support strings');
  }
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

  @override
  void generate(SymbolTable st) {
    if (value == '!') {
      throw SemanticError('Assembly generation does not support factorial');
    }

    children[0].generate(st);

    switch (value) {
      case '+':
        break;
      case '-':
        Code.append('  neg eax');
        break;
      case 'not':
        Code.append('  cmp eax, 0');
        Code.append('  mov eax, 0');
        Code.append('  mov ecx, 1');
        Code.append('  cmove eax, ecx');
        break;
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

  @override
  void generate(SymbolTable st) {
    throw SemanticError('Assembly generation does not support casts');
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
        if (left.type == 'string' || right.type == 'string') {
          return Variable(
            value: '${_toStringValue(left)}${_toStringValue(right)}',
            type: 'string',
          );
        }
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
        return Variable(
          value: _toBoolean(left) && _toBoolean(right),
          type: 'boolean',
        );
      case 'or':
        return Variable(
          value: _toBoolean(left) || _toBoolean(right),
          type: 'boolean',
        );

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
        throw SemanticError(
          "Operator '$value' expects numeric or string operands",
        );

      default:
        throw SemanticError("Invalid binary operator '$value'");
    }
  }

  @override
  void generate(SymbolTable st) {
    if (value == '..') {
      throw SemanticError('Assembly generation does not support strings');
    }

    children[1].generate(st);
    Code.append('  push eax');
    children[0].generate(st);
    Code.append('  pop ecx');

    switch (value) {
      case '+':
        Code.append('  add eax, ecx');
        break;
      case '-':
        Code.append('  sub eax, ecx');
        break;
      case '*':
        Code.append('  imul ecx');
        break;
      case '/':
        Code.append('  cdq');
        Code.append('  idiv ecx');
        break;
      case '^':
        Code.append('  xor eax, ecx');
        break;
      case 'and':
        Code.append('  cmp eax, 0');
        Code.append('  setne al');
        Code.append('  movzx eax, al');
        Code.append('  cmp ecx, 0');
        Code.append('  setne cl');
        Code.append('  movzx ecx, cl');
        Code.append('  and eax, ecx');
        break;
      case 'or':
        Code.append('  cmp eax, 0');
        Code.append('  setne al');
        Code.append('  movzx eax, al');
        Code.append('  cmp ecx, 0');
        Code.append('  setne cl');
        Code.append('  movzx ecx, cl');
        Code.append('  or eax, ecx');
        break;
      case '==':
        Code.append('  cmp eax, ecx');
        Code.append('  mov eax, 0');
        Code.append('  mov ecx, 1');
        Code.append('  cmove eax, ecx');
        break;
      case '<':
        Code.append('  cmp eax, ecx');
        Code.append('  mov eax, 0');
        Code.append('  mov ecx, 1');
        Code.append('  cmovl eax, ecx');
        break;
      case '>':
        Code.append('  cmp eax, ecx');
        Code.append('  mov eax, 0');
        Code.append('  mov ecx, 1');
        Code.append('  cmovg eax, ecx');
        break;
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

  @override
  void generate(SymbolTable st) {
    final variable = st.resolve(value as String);
    Code.append('  mov eax, [ebp-${variable.shift}] ; recupera $value');
  }
}

class VarDec extends Node {
  final bool isFunction;

  VarDec(String variableType, List<Node> children)
    : isFunction = false,
      super(variableType, children);

  VarDec.function(String returnType, List<Node> children)
    : isFunction = true,
      super(returnType, children);

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
      isFunction: isFunction,
    );

    return initializedValue ?? st.resolve(identifier.value as String);
  }

  @override
  void generate(SymbolTable st) {
    final identifier = children[0] as Identifier;
    final variableType = value as String;

    if (variableType != 'number' && variableType != 'boolean') {
      throw SemanticError(
        "Assembly generation does not support variables of type '$variableType'",
      );
    }

    if (children.length == 2) {
      final expressionType = inferType(children[1], st);
      if (expressionType != variableType) {
        throw SemanticError(
          "Type mismatch: expected '$variableType', found '$expressionType'",
        );
      }
    }

    st.createVariable(identifier.value as String, variableType);
    final variable = st.resolve(identifier.value as String);
    Code.append(
      '  sub esp, 4 ; var ${identifier.value} ${variable.type} [EBP-${variable.shift}]',
    );

    if (children.length == 2) {
      children[1].generate(st);
      Code.append(
        '  mov [ebp-${variable.shift}], eax ; ${identifier.value} = EAX',
      );
    } else {
      Code.append('  mov eax, 0');
      Code.append(
        '  mov [ebp-${variable.shift}], eax ; ${identifier.value} = 0',
      );
    }
  }
}

class Print extends Node {
  Print(Node expression) : super('print', [expression]);

  @override
  Variable evaluate(SymbolTable st) {
    final evaluated = children[0].evaluate(st);
    RuntimeOutput.writelnValue(_toStringValue(evaluated));
    return evaluated;
  }

  @override
  void generate(SymbolTable st) {
    children[0].generate(st);
    Code.append('  push eax ; empilha valor para print');
    Code.append('  push format_out ; formato int de saida');
    Code.append('  call printf');
    Code.append('  add esp, 8 ; limpa os argumentos');
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

  @override
  void generate(SymbolTable st) {
    Code.append('  push scan_int ; endereço de memória de suporte');
    Code.append('  push format_in ; formato de entrada (int)');
    Code.append('  call scanf');
    Code.append('  add esp, 8 ; Remove os argumentos da pilha');
    Code.append('  mov eax, dword [scan_int] ; retorna o valor lido em EAX');
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

  @override
  void generate(SymbolTable st) {
    if (immutable) {
      final expressionType = inferType(children[0], st);
      if (expressionType != 'number' && expressionType != 'boolean') {
        throw SemanticError(
          "Assembly generation does not support immutable variables of type '$expressionType'",
        );
      }

      children[0].generate(st);
      st.createVariable(
        value as String,
        expressionType,
        initialValue: Variable(value: 0, type: expressionType),
        immutable: true,
      );
      final variable = st.resolve(value as String);
      Code.append(
        '  sub esp, 4 ; var $value ${variable.type} [EBP-${variable.shift}]',
      );
      Code.append('  mov [ebp-${variable.shift}], eax ; $value = EAX');
      return;
    }

    final variable = st.resolve(value as String);
    final expressionType = inferType(children[0], st);
    if (expressionType != variable.type) {
      throw SemanticError(
        "Type mismatch: expected '${variable.type}', found '$expressionType'",
      );
    }

    children[0].generate(st);
    Code.append('  mov [ebp-${variable.shift}], eax ; $value = EAX');
  }
}

class FieldAssignment extends Node {
  final List<String> fields;

  FieldAssignment(String baseName, this.fields, Node expression)
    : super(baseName, [expression]);

  @override
  Variable evaluate(SymbolTable st) {
    final resolved = children[0].evaluate(st);
    st.setField(value as String, fields, resolved);
    return resolved;
  }

  @override
  void generate(SymbolTable st) {
    throw SemanticError('Assembly generation does not support structs');
  }
}

class Block extends Node {
  final bool createsScope;

  Block(List<Node> statements, {this.createsScope = false})
    : super('block', statements);

  @override
  Variable evaluate(SymbolTable st) {
    final scope = createsScope ? st.createChild() : st;
    var result = Variable(value: 0, type: 'number');
    for (final stmt in children) {
      result = stmt.evaluate(scope);
      if (result.isReturn) {
        return result;
      }
    }
    return result;
  }

  @override
  void generate(SymbolTable st) {
    for (final stmt in children) {
      stmt.generate(st);
    }
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
      final result = children[1].evaluate(st);
      if (result.isReturn) {
        return result;
      }
      return result;
    }

    if (children.length == 3) {
      final result = children[2].evaluate(st);
      if (result.isReturn) {
        return result;
      }
      return result;
    }

    return Variable(value: 0, type: 'number');
  }

  @override
  void generate(SymbolTable st) {
    final elseLabel = 'else_$uniqueId';
    final exitLabel = 'exit_$uniqueId';

    final conditionType = inferType(children[0], st);
    if (conditionType != 'boolean') {
      throw SemanticError(
        "Value of type '$conditionType' cannot be used as boolean",
      );
    }

    children[0].generate(st);
    Code.append('  cmp eax, 0 ; se a condição for falsa, sai');
    Code.append(children.length == 3 ? '  je $elseLabel' : '  je $exitLabel');
    children[1].generate(st);

    if (children.length == 3) {
      Code.append('  jmp $exitLabel');
      Code.append('$elseLabel:');
      children[2].generate(st);
    }

    Code.append('$exitLabel:');
  }
}

class While extends Node {
  While(Node condition, Node block) : super('while', [condition, block]);

  @override
  Variable evaluate(SymbolTable st) {
    var result = Variable(value: 0, type: 'number');
    while (_toBoolean(children[0].evaluate(st))) {
      result = children[1].evaluate(st);
      if (result.isReturn) {
        return result;
      }
    }
    return result;
  }

  @override
  void generate(SymbolTable st) {
    final loopLabel = 'loop_$uniqueId';
    final exitLabel = 'exit_$uniqueId';

    final conditionType = inferType(children[0], st);
    if (conditionType != 'boolean') {
      throw SemanticError(
        "Value of type '$conditionType' cannot be used as boolean",
      );
    }

    Code.append('$loopLabel: ; label do loop');
    children[0].generate(st);
    Code.append('  cmp eax, 0 ; se a condição for falsa, sai');
    Code.append('  je $exitLabel');
    children[1].generate(st);
    Code.append('  jmp $loopLabel');
    Code.append('$exitLabel:');
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

  @override
  void generate(SymbolTable st) {
    final elseLabel = 'else_expr_$uniqueId';
    final exitLabel = 'exit_expr_$uniqueId';

    final conditionType = inferType(children[0], st);
    if (conditionType != 'boolean') {
      throw SemanticError(
        "Value of type '$conditionType' cannot be used as boolean",
      );
    }

    children[0].generate(st);
    Code.append('  cmp eax, 0');
    Code.append('  je $elseLabel');
    children[1].generate(st);
    Code.append('  jmp $exitLabel');
    Code.append('$elseLabel:');
    children[2].generate(st);
    Code.append('$exitLabel:');
  }
}

class FuncDec extends Node {
  final String name;
  final List<VarDec> parameters;
  final String? returnType;

  FuncDec(this.name, this.parameters, this.returnType, Node body)
    : super(returnType ?? 'void', [Identifier(name), ...parameters, body]);

  Node get body => children.last;

  @override
  Variable evaluate(SymbolTable st) {
    st.defineFunction(name, this);
    return Variable(value: this, type: returnType ?? 'void', isFunction: true);
  }

  @override
  void generate(SymbolTable st) {
    Code.append('  ; function $name omitted from basic assembly generation');
  }
}

class FuncCall extends Node {
  final String name;

  FuncCall(this.name, List<Node> arguments) : super('function_call', arguments);

  @override
  Variable evaluate(SymbolTable st) {
    final function = st.resolveFunction(name);

    if (function.parameters.length != children.length) {
      throw SemanticError(
        "Function '$name' expects ${function.parameters.length} arguments, found ${children.length}",
      );
    }

    final evaluatedArgs = <Variable>[];
    for (final argument in children) {
      evaluatedArgs.add(argument.evaluate(st));
    }

    final functionScope = st.root.createChild();
    for (var i = 0; i < function.parameters.length; i++) {
      final parameter = function.parameters[i];
      final argument = evaluatedArgs[i];
      final parameterName =
          (parameter.children[0] as Identifier).value as String;
      final parameterType = parameter.value as String;
      if (parameterType != argument.type) {
        throw SemanticError(
          "Type mismatch for argument '${parameterName}' in function '$name': expected '$parameterType', found '${argument.type}'",
        );
      }
      functionScope.createVariable(
        parameterName,
        parameterType,
        initialValue: argument,
      );
    }

    final result = function.body.evaluate(functionScope);
    if (result.isReturn) {
      if (function.returnType == null) {
        throw SemanticError("Function '$name' cannot return a value");
      }
      if (function.returnType != result.type) {
        throw SemanticError(
          "Type mismatch in return of function '$name': expected '${function.returnType}', found '${result.type}'",
        );
      }
      return result.copy(isReturn: false);
    }

    if (function.returnType != null) {
      throw SemanticError("Function '$name' did not return a value");
    }

    return Variable(value: 0, type: 'number');
  }

  @override
  void generate(SymbolTable st) {
    Code.append(
      '  ; function call $name omitted from basic assembly generation',
    );
    Code.append('  mov eax, 0');
  }
}

class StructDec extends Node {
  final String name;
  final List<VarDec> fields;

  StructDec(this.name, this.fields)
    : super('struct', [Identifier(name), ...fields]);

  @override
  Variable evaluate(SymbolTable st) {
    st.defineStruct(name, this);
    return Variable(value: this, type: 'struct', isFunction: true);
  }

  @override
  void generate(SymbolTable st) {
    Code.append('  ; struct $name omitted from basic assembly generation');
  }
}

class FieldAccess extends Node {
  FieldAccess(String baseName, List<String> fields)
    : super(baseName, fields.map(Identifier.new).toList());

  List<String> get fieldNames =>
      children.map((child) => child.value as String).toList();

  @override
  Variable evaluate(SymbolTable st) {
    return st.resolveField(value as String, fieldNames);
  }

  @override
  void generate(SymbolTable st) {
    throw SemanticError('Assembly generation does not support structs');
  }
}

class Return extends Node {
  Return(Node expression) : super('return', [expression]);

  @override
  Variable evaluate(SymbolTable st) {
    final result = children[0].evaluate(st);
    return result.copy(isReturn: true);
  }

  @override
  void generate(SymbolTable st) {
    Code.append('  ; return omitted from basic assembly generation');
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
      if (result.isReturn) {
        return result;
      }
      iterator++;
    }

    st.setVariable(value as String, Variable(value: iterator, type: 'number'));
    return result;
  }

  @override
  void generate(SymbolTable st) {
    throw SemanticError('Assembly generation does not support for loops');
  }
}

class NoOp extends Node {
  NoOp() : super('noop', []);

  @override
  Variable evaluate(SymbolTable st) => Variable(value: 0, type: 'number');

  @override
  void generate(SymbolTable st) {}
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
  final SymbolTable? parent;
  final Map<String, FuncDec> functions;
  final Map<String, StructDec> structs;
  final Map<String, Variable> table = {};
  int _nextShift = 0;

  SymbolTable({
    this.parent,
    Map<String, FuncDec>? functions,
    Map<String, StructDec>? structs,
  }) : functions = functions ?? parent?.functions ?? {},
       structs = structs ?? parent?.structs ?? {};

  SymbolTable createChild() =>
      SymbolTable(parent: this, functions: functions, structs: structs);

  SymbolTable get root => parent?.root ?? this;

  bool _isValidIdentifier(String name) {
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(name);
  }

  bool exists(String name) {
    final trimmedName = name.trim();
    return table.containsKey(trimmedName) ||
        (parent?.exists(trimmedName) ?? false);
  }

  void defineFunction(String name, FuncDec function) {
    final trimmedName = name.trim();
    if (functions.containsKey(trimmedName) || table.containsKey(trimmedName)) {
      throw SemanticError("Function '$trimmedName' is already declared");
    }
    createVariable(
      trimmedName,
      function.returnType ?? 'void',
      initialValue: Variable(
        value: function,
        type: function.returnType ?? 'void',
        isFunction: true,
      ),
      isFunction: true,
    );
    functions[trimmedName] = function;
  }

  FuncDec resolveFunction(String name) {
    final trimmedName = name.trim();
    final function = functions[trimmedName];
    if (function == null) {
      throw SemanticError("Function '$trimmedName' is not declared");
    }
    return function;
  }

  void defineStruct(String name, StructDec struct) {
    final trimmedName = name.trim();
    if (structs.containsKey(trimmedName) ||
        functions.containsKey(trimmedName) ||
        table.containsKey(trimmedName)) {
      throw SemanticError("Struct '$trimmedName' is already declared");
    }
    structs[trimmedName] = struct;
  }

  StructDec resolveStruct(String name) {
    final trimmedName = name.trim();
    final struct = structs[trimmedName];
    if (struct == null) {
      throw SemanticError("Struct '$trimmedName' is not declared");
    }
    return struct;
  }

  void _assertTypeCompatibility(String expectedType, Variable value) {
    if (expectedType == value.type) {
      return;
    }

    throw SemanticError(
      "Type mismatch: expected '$expectedType', found '${value.type}'",
    );
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
      case 'void':
        return Variable(value: null, type: 'void');
      default:
        if (structs.containsKey(type)) {
          return Variable(value: _instantiateStruct(type), type: type);
        }
        throw SemanticError("Unsupported type '$type'");
    }
  }

  Map<String, Variable> _instantiateStruct(String type) {
    final struct = resolveStruct(type);
    final values = <String, Variable>{};

    for (final field in struct.fields) {
      final identifier = field.children[0] as Identifier;
      final fieldName = identifier.value as String;
      final fieldType = field.value as String;

      if (values.containsKey(fieldName)) {
        throw SemanticError(
          "Field '$fieldName' is already declared in struct '$type'",
        );
      }

      values[fieldName] = _defaultValueForType(fieldType);
    }

    return values;
  }

  void createVariable(
    String name,
    String type, {
    Variable? initialValue,
    bool immutable = false,
    bool isFunction = false,
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

    _nextShift += 4;

    if (initialValue != null) {
      _assertTypeCompatibility(type, initialValue);
      table[trimmedName] = Variable(
        value: initialValue.value,
        type: type,
        immutable: immutable,
        isFunction: isFunction,
        shift: _nextShift,
      );
      return;
    }

    final defaultVar = _defaultValueForType(type);
    table[trimmedName] = Variable(
      value: defaultVar.value,
      type: type,
      immutable: immutable,
      isFunction: isFunction,
      shift: _nextShift,
    );
  }

  void setVariable(String name, Variable value) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!table.containsKey(trimmedName)) {
      if (parent != null && parent!.exists(trimmedName)) {
        parent!.setVariable(trimmedName, value);
        return;
      }
      throw SemanticError("Variable '$trimmedName' is not declared");
    }

    final current = table[trimmedName]!;

    if (current.immutable) {
      throw SemanticError("cannot change the value of $trimmedName");
    }

    if (current.isFunction) {
      throw SemanticError("Function '$trimmedName' cannot be assigned to");
    }

    _assertTypeCompatibility(current.type, value);
    current.value = value.value;
  }

  Variable resolve(String name) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw SemanticError('Identifier name cannot be empty');
    }

    if (!table.containsKey(trimmedName)) {
      if (parent != null && parent!.exists(trimmedName)) {
        return parent!.resolve(trimmedName);
      }
      throw SemanticError("Variable '$trimmedName' is not declared");
    }

    final current = table[trimmedName]!;
    return Variable(
      value: current.value,
      type: current.type,
      immutable: current.immutable,
      isFunction: current.isFunction,
      shift: current.shift,
    );
  }

  Variable resolveField(String baseName, List<String> fields) {
    if (fields.isEmpty) {
      return resolve(baseName);
    }

    Variable current = resolve(baseName);
    for (final fieldName in fields) {
      if (!structs.containsKey(current.type)) {
        throw SemanticError(
          "Value '$baseName' of type '${current.type}' has no fields",
        );
      }

      final fieldMap = current.value as Map<String, Variable>;
      final field = fieldMap[fieldName];
      if (field == null) {
        throw SemanticError(
          "Struct '${current.type}' has no field '$fieldName'",
        );
      }
      current = field;
    }

    return current.copy();
  }

  void setField(String baseName, List<String> fields, Variable value) {
    if (fields.isEmpty) {
      setVariable(baseName, value);
      return;
    }

    Variable current = _resolveMutable(baseName);
    for (var i = 0; i < fields.length; i++) {
      final fieldName = fields[i];
      if (!structs.containsKey(current.type)) {
        throw SemanticError(
          "Value '$baseName' of type '${current.type}' has no fields",
        );
      }

      final fieldMap = current.value as Map<String, Variable>;
      final field = fieldMap[fieldName];
      if (field == null) {
        throw SemanticError(
          "Struct '${current.type}' has no field '$fieldName'",
        );
      }

      if (i == fields.length - 1) {
        _assertTypeCompatibility(field.type, value);
        field.value = value.value;
        return;
      }

      current = field;
    }
  }

  Variable _resolveMutable(String name) {
    final trimmedName = name.trim();
    if (table.containsKey(trimmedName)) {
      return table[trimmedName]!;
    }
    if (parent != null && parent!.exists(trimmedName)) {
      return parent!._resolveMutable(trimmedName);
    }
    throw SemanticError("Variable '$trimmedName' is not declared");
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
      next = Token('DOT', currentChar, position);
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

      if (identifier == 'function') {
        next = Token('FUNC', identifier, start);
        return;
      }

      if (identifier == 'struct') {
        next = Token('STRUCT', identifier, start);
        return;
      }

      if (identifier == 'return') {
        next = Token('RETURN', identifier, start);
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
  final Set<String> declaredStructTypes = {};

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
      if (lexer.next.type == 'FUNC') {
        statements.add(parseFuncDeclaration());
      } else if (lexer.next.type == 'STRUCT') {
        final structDeclaration = parseStructDeclaration();
        declaredStructTypes.add(structDeclaration.name);
        statements.add(structDeclaration);
      } else {
        statements.add(parseStatement());
      }
    }
    return Block(statements);
  }

  FuncDec parseFuncDeclaration() {
    if (lexer.next.type != 'FUNC') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_FUNCTION',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected 'function', found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();

    if (lexer.next.type != 'IDEN') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_IDENTIFIER',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected function name, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }

    final functionName = lexer.next.value;
    lexer.selectToken();

    if (lexer.next.type != 'OPEN_PAR') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_OPEN_PAREN',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected '(' after function name '$functionName', found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();

    final parameters = <VarDec>[];
    if (lexer.next.type != 'CLOSE_PAR') {
      while (true) {
        if (lexer.next.type != 'IDEN') {
          throw CompilerError(
            sourceTag: 'Parser',
            code: 'E_PAR_EXPECTED_IDENTIFIER',
            position: lexer.next.position,
            expression: lexer.source,
            message:
                "Expected parameter name, found '${lexer.next.value}' (${lexer.next.type})",
          );
        }
        final parameterName = lexer.next.value;
        lexer.selectToken();

        final parameterType = _parseTypeName("parameter '$parameterName'");
        parameters.add(VarDec(parameterType, [Identifier(parameterName)]));

        if (lexer.next.type != 'COMMA') {
          break;
        }
        lexer.selectToken();
      }
    }

    if (lexer.next.type != 'CLOSE_PAR') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_CLOSE_PAREN',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected ')' after function parameters, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();

    String? returnType;
    if (lexer.next.type == 'TYPE' || lexer.next.type == 'IDEN') {
      returnType = lexer.next.value;
      lexer.selectToken();
    }

    _consumeOptionalBlockStartEol();

    final body = parseBlock(['CLOSE_BRA']);

    if (lexer.next.type != 'CLOSE_BRA') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_END',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected 'end' to close function '$functionName', found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();
    _consumeBlockTerminator('function');

    return FuncDec(functionName, parameters, returnType, body);
  }

  StructDec parseStructDeclaration() {
    lexer.selectToken();

    if (lexer.next.type != 'IDEN') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_IDENTIFIER',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected struct name, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }

    final structName = lexer.next.value;
    lexer.selectToken();
    _consumeOptionalBlockStartEol();

    final fields = <VarDec>[];
    while (lexer.next.type != 'EOF' && lexer.next.type != 'CLOSE_BRA') {
      if (lexer.next.type == 'EOL') {
        lexer.selectToken();
        continue;
      }
      if (lexer.next.type != 'VAR') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_STRUCT_FIELD',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected local field declaration in struct '$structName', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      lexer.selectToken();

      if (lexer.next.type != 'IDEN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_IDENTIFIER',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected field name, found '${lexer.next.value}' (${lexer.next.type})",
        );
      }

      final fieldName = lexer.next.value;
      lexer.selectToken();
      final fieldType = _parseTypeName("field '$fieldName'");

      if (lexer.next.type == 'ASSIGN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_STRUCT_FIELD_INITIALIZER',
          position: lexer.next.position,
          expression: lexer.source,
          message: 'Struct fields cannot be initialized in the declaration',
        );
      }

      _consumeStatementTerminator('struct field declaration');
      fields.add(VarDec(fieldType, [Identifier(fieldName)]));
    }

    if (lexer.next.type != 'CLOSE_BRA') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_END',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected 'end' to close struct '$structName', found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();
    _consumeBlockTerminator('struct');

    return StructDec(structName, fields);
  }

  String _parseTypeName(String context) {
    if (lexer.next.type != 'TYPE' && lexer.next.type != 'IDEN') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_TYPE',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected type after $context, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    final typeName = lexer.next.value;
    if (lexer.next.type == 'IDEN' && !declaredStructTypes.contains(typeName)) {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_TYPE',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected type after $context, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();
    return typeName;
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

  void _consumeOptionalBlockStartEol() {
    if (lexer.next.type == 'EOL') {
      lexer.selectToken();
    }
  }

  void _consumeBlockTerminator(String blockName) {
    if (lexer.next.type == 'EOL') {
      lexer.selectToken();
      return;
    }

    if (lexer.next.type == 'EOF' ||
        lexer.next.type == 'CLOSE_BRA' ||
        lexer.next.type == 'ELSE') {
      return;
    }

    throw CompilerError(
      sourceTag: 'Parser',
      code: 'E_PAR_EXPECTED_EOL',
      position: lexer.next.position,
      expression: lexer.source,
      message:
          "Expected end of line after $blockName block, found '${lexer.next.value}' (${lexer.next.type})",
    );
  }

  void _consumeStatementTerminator(String statementName) {
    if (lexer.next.type == 'EOL') {
      lexer.selectToken();
      return;
    }

    if (lexer.next.type == 'EOF' ||
        lexer.next.type == 'CLOSE_BRA' ||
        lexer.next.type == 'ELSE') {
      return;
    }

    throw CompilerError(
      sourceTag: 'Parser',
      code: 'E_PAR_EXPECTED_EOL',
      position: lexer.next.position,
      expression: lexer.source,
      message:
          "Expected end of line after $statementName, found '${lexer.next.value}' (${lexer.next.type})",
    );
  }

  FuncCall _parseFunctionCallAfterName(String name) {
    if (lexer.next.type != 'OPEN_PAR') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_OPEN_PAREN',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected '(' after function name '$name', found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();

    final arguments = <Node>[];
    if (lexer.next.type != 'CLOSE_PAR') {
      arguments.add(parseBoolExpression());

      while (lexer.next.type == 'COMMA') {
        lexer.selectToken();
        arguments.add(parseBoolExpression());
      }
    }

    if (lexer.next.type != 'CLOSE_PAR') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_EXPECTED_CLOSE_PAREN',
        position: lexer.next.position,
        expression: lexer.source,
        message:
            "Expected ')' after function call arguments, found '${lexer.next.value}' (${lexer.next.type})",
      );
    }
    lexer.selectToken();

    return FuncCall(name, arguments);
  }

  List<String> _parseFieldNamesAfterDot(String baseName) {
    final fields = <String>[];
    while (lexer.next.type == 'DOT') {
      lexer.selectToken();
      if (lexer.next.type != 'IDEN') {
        throw CompilerError(
          sourceTag: 'Parser',
          code: 'E_PAR_EXPECTED_FIELD',
          position: lexer.next.position,
          expression: lexer.source,
          message:
              "Expected field name after '$baseName.', found '${lexer.next.value}' (${lexer.next.type})",
        );
      }
      fields.add(lexer.next.value);
      lexer.selectToken();
    }
    return fields;
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

    if (lexer.next.type == 'FUNC') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_FUNCTION_INSIDE_BLOCK',
        position: lexer.next.position,
        expression: lexer.source,
        message: 'Function declarations are only allowed at program scope',
      );
    }

    if (lexer.next.type == 'STRUCT') {
      throw CompilerError(
        sourceTag: 'Parser',
        code: 'E_PAR_STRUCT_INSIDE_BLOCK',
        position: lexer.next.position,
        expression: lexer.source,
        message: 'Struct declarations are only allowed at program scope',
      );
    }

    if (lexer.next.type == 'RETURN') {
      lexer.selectToken();
      final expression = parseBoolExpression();
      _consumeStatementTerminator('return statement');
      return Return(expression);
    }

    if (lexer.next.type == 'IF') {
      lexer.selectToken();

      final hasParenthesizedCondition = lexer.next.type == 'OPEN_PAR';
      if (hasParenthesizedCondition) {
        lexer.selectToken();
      }

      final condition = parseBoolExpression();

      if (hasParenthesizedCondition) {
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
      }

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

      _consumeBlockTerminator('if');

      return If(condition, thenBlock, elseBlock);
    }

    if (lexer.next.type == 'WHILE') {
      lexer.selectToken();

      final hasParenthesizedCondition = lexer.next.type == 'OPEN_PAR';
      if (hasParenthesizedCondition) {
        lexer.selectToken();
      }

      final condition = parseBoolExpression();

      if (hasParenthesizedCondition) {
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
      }

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

      _consumeOptionalBlockStartEol();

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

      _consumeBlockTerminator('while');

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

      _consumeOptionalBlockStartEol();

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

      _consumeBlockTerminator('for');

      return For(loopVar, startExpr, endExpr, body);
    }

    if (lexer.next.type == 'OPEN_BRA') {
      lexer.selectToken();

      _consumeOptionalBlockStartEol();

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

      _consumeBlockTerminator('do');

      return Block(body.children, createsScope: true);
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

      final varType = _parseTypeName("identifier '$identName'");

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

      if (lexer.next.type == 'OPEN_PAR') {
        final call = _parseFunctionCallAfterName(identName);
        _consumeStatementTerminator('function call');
        return call;
      }

      if (lexer.next.type == 'DOT') {
        final fields = _parseFieldNamesAfterDot(identName);
        if (lexer.next.type != 'ASSIGN') {
          throw CompilerError(
            sourceTag: 'Parser',
            code: 'E_PAR_EXPECTED_ASSIGN',
            position: lexer.next.position,
            expression: lexer.source,
            message:
                "Expected '=' after field access '$identName.${fields.join('.')}', found '${lexer.next.value}' (${lexer.next.type})",
          );
        }
        lexer.selectToken();

        final expr = parseBoolExpression();
        _consumeStatementTerminator('field assignment');
        return FieldAssignment(identName, fields, expr);
      }

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
      if (lexer.next.type == 'OPEN_PAR') {
        return _parseFunctionCallAfterName(identName);
      }
      if (lexer.next.type == 'DOT') {
        return FieldAccess(identName, _parseFieldNamesAfterDot(identName));
      }
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

  Node parse(String code) {
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

    return root;
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

String inferType(Node node, SymbolTable st) {
  if (node is IntVal) {
    return 'number';
  }
  if (node is FloatVal) {
    return 'float';
  }
  if (node is BoolVal) {
    return 'boolean';
  }
  if (node is StringVal) {
    return 'string';
  }
  if (node is Read) {
    return 'number';
  }
  if (node is Identifier) {
    return st.resolve(node.value as String).type;
  }
  if (node is FieldAccess) {
    return st.resolveField(node.value as String, node.fieldNames).type;
  }
  if (node is FuncCall) {
    final function = st.resolveFunction(node.name);
    if (function.returnType == null) {
      throw SemanticError("Function '${node.name}' does not return a value");
    }
    return function.returnType!;
  }
  if (node is CastOp) {
    return node.value as String;
  }
  if (node is UnOp) {
    final operandType = inferType(node.children[0], st);
    switch (node.value) {
      case '+':
      case '-':
        if (operandType != 'number' && operandType != 'float') {
          throw SemanticError("Unary '${node.value}' expects numeric operand");
        }
        return operandType;
      case 'not':
        if (operandType != 'boolean') {
          throw SemanticError(
            "Value of type '$operandType' cannot be used as boolean",
          );
        }
        return 'boolean';
      case '!':
        if (operandType != 'number') {
          throw SemanticError('Factorial is only defined for integer numbers');
        }
        return 'number';
    }
  }
  if (node is BinOp) {
    final leftType = inferType(node.children[0], st);
    final rightType = inferType(node.children[1], st);
    final op = node.value as String;

    bool isNumeric(String type) => type == 'number' || type == 'float';

    switch (op) {
      case '+':
        if (leftType == 'string' || rightType == 'string') {
          return 'string';
        }
        if (!isNumeric(leftType) || !isNumeric(rightType)) {
          throw SemanticError("Operator '$op' expects numeric operands");
        }
        return leftType == 'float' || rightType == 'float' ? 'float' : 'number';
      case '-':
      case '*':
      case '/':
        if (!isNumeric(leftType) || !isNumeric(rightType)) {
          throw SemanticError("Operator '$op' expects numeric operands");
        }
        return leftType == 'float' || rightType == 'float' ? 'float' : 'number';
      case '^':
        if (leftType != 'number' || rightType != 'number') {
          throw SemanticError("Operator '^' expects integer numbers");
        }
        return 'number';
      case 'and':
      case 'or':
        if (leftType != 'boolean' || rightType != 'boolean') {
          throw SemanticError("Operator '$op' expects boolean operands");
        }
        return 'boolean';
      case '==':
        if (leftType != rightType &&
            !(isNumeric(leftType) && isNumeric(rightType))) {
          throw SemanticError(
            "Operator '==' expects both sides with compatible types",
          );
        }
        return 'boolean';
      case '<':
      case '>':
        if (!(isNumeric(leftType) && isNumeric(rightType)) &&
            !(leftType == 'string' && rightType == 'string')) {
          throw SemanticError(
            "Operator '$op' expects numeric or string operands",
          );
        }
        return 'boolean';
      case '..':
        return 'string';
    }
  }
  if (node is IfExpression) {
    final conditionType = inferType(node.children[0], st);
    if (conditionType != 'boolean') {
      throw SemanticError(
        "Value of type '$conditionType' cannot be used as boolean",
      );
    }

    final thenType = inferType(node.children[1], st);
    final elseType = inferType(node.children[2], st);
    if (thenType != elseType) {
      throw SemanticError(
        "If expression branches must have the same type, found '$thenType' and '$elseType'",
      );
    }
    return thenType;
  }

  throw SemanticError('Cannot infer type for ${node.runtimeType}');
}

bool containsNode(Node node, bool Function(Node node) predicate) {
  if (predicate(node)) {
    return true;
  }

  for (final child in node.children) {
    if (containsNode(child, predicate)) {
      return true;
    }
  }

  return false;
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
  final isFileInput = args.length == 1 && inputFile.existsSync();
  if (isFileInput) {
    sourceCode = inputFile.readAsStringSync();
  } else {
    sourceCode = input;
  }

  final code = Prepro.filter(sourceCode);
  final parser = Parser();

  try {
    if (isFileInput) {
      final root = parser.parse(code);
      final hasRead = containsNode(root, (node) => node is Read);
      final hasFunctions = containsNode(
        root,
        (node) => node is FuncDec || node is FuncCall || node is Return,
      );
      final hasStructs = containsNode(
        root,
        (node) =>
            node is StructDec || node is FieldAccess || node is FieldAssignment,
      );
      final needsInterpreter = hasFunctions || hasStructs || hasRead;
      List<String> capturedOutput = [];

      if (needsInterpreter) {
        RuntimeOutput.captured = capturedOutput;
        root.evaluate(SymbolTable());
        RuntimeOutput.captured = null;
      }

      Code.reset();
      if (needsInterpreter) {
        for (final output in capturedOutput) {
          final value = int.tryParse(output);
          if (value != null) {
            Code.appendPrintInt(value);
          }
        }
      } else {
        root.generate(SymbolTable());
      }
      final lastDot = inputFile.path.lastIndexOf('.');
      final lastSeparator = inputFile.path.lastIndexOf(Platform.pathSeparator);
      final asmPath = lastDot > lastSeparator
          ? inputFile.path.replaceFirst(RegExp(r'\.[^.]*$'), '.asm')
          : '${inputFile.path}.asm';
      Code.dump(asmPath);
    } else {
      parser.run(code);
    }
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
