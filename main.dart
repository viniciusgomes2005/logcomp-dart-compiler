class Token {
  String type;
  String value;
  Token(this.type, this.value);
}

class Lexer {
  String source;
  int position = 0;
  late Token next;
  Lexer(this.source) {
    selectToken();
  }

  selectToken() {
    if (position >= source.length) {
      next = Token("EOF", "");
      return;
    }

    String current_char = source[position];
    if (source[position] == " ") {
      position++;
      selectToken();
      return;
    }
    if (position == 0 && (source[position] == "-" || source[position] == "+")) {
      throw Exception("Expression cannot start with an operator");
    }
    if (current_char == "+" || current_char == "-") {
      int checkPos = position - 1;
      while (checkPos >= 0 && source[checkPos] == " ") {
        checkPos--;
      }
      if (checkPos >= 0 &&
          (source[checkPos] == "+" || source[checkPos] == "-")) {
        throw Exception("Cannot have consecutive operators");
      }
      next = Token("OPERATOR", current_char);
      position++;
      return;
    }
    if (current_char == " ") {
      position++;
      selectToken();
      return;
    }
    if (int.tryParse(current_char) != null) {
      String number = "";
      while (position < source.length &&
          int.tryParse(source[position]) != null) {
        number += source[position];
        position++;
      }
      next = Token("NUMBER", number);
      return;
    }
    throw Exception("Invalid character: $current_char");
  }
}

class Parser {
  Lexer lexer;
  Parser(this.lexer);

  int parseExpression() {
    int value = lexer.next.type == "NUMBER" ? int.parse(lexer.next.value) : 0;
    if (lexer.next.type == "NUMBER") {
      lexer.selectToken();
    }
    if (lexer.next.type == "EOF") {
      return value;
    }
    while (lexer.next.type == "OPERATOR") {
      String operator = lexer.next.value;
      lexer.selectToken();
      if (lexer.next.type != "NUMBER") {
        throw Exception("Expected number after operator");
      }
      int term = int.parse(lexer.next.value);
      switch (operator) {
        case "+":
          value += term;
          break;
        case "-":
          value -= term;
          break;
      }
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
    print("Use: dart run main.dart 10 + 5 - 3");
    return;
  }
  Parser parser = Parser(Lexer(""));
  print(parser.run(args.join(" ")));
}
