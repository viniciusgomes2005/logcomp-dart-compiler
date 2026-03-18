# logcomp-dart-compiler

[![Compilation Status](https://compiler-tester.insper-comp.com.br/svg/viniciusgomes2005/logcomp-dart-compiler)](https://compiler-tester.insper-comp.com.br/svg/viniciusgomes2005/logcomp-dart-compiler)

This repository is monitored by Compiler Tester for automatic compilation status.

## Diagrama Sintático

```mermaid
flowchart TB
    N1(( ))
    N2(( ))
    N3(( ))
    N4(( ))
    N5(( ))

    N1 --- N2
    N1 --- N3
    N3 --- N4
    N4 --- N5
```

**Descrição:**
- `EXPRESSION` começa por `TERM` e aceita repetições com `+`, `-` ou `^`
- `TERM` começa por `FACTOR` e aceita repetições com `*` ou `/`
- `FACTOR` pode ser: operador unário (`+` ou `-`) aplicado a `FACTOR`, parênteses `(` `EXPRESSION` `)`, ou `INT`
- A análise termina quando encontra `EOF` (fim da entrada)

**Exemplos válidos:**
- `1+2`
- `3-2`
- `11+22-33`
- `2 ^ 3` (XOR - Extra Credit)
- `789   +345  -    123`

## EBNF:
```ebnf
PROGRAM = { STATEMENT } ;
STATEMENT = ((IDENTIFIER, "=", EXPRESSION) | (PRINT, "(", EXPRESSION, ")") | ε), EOL ;
EXPRESSION = TERM, { ("+" | "-"), TERM } ;
TERM = FACTOR, { ("*" | "/"), FACTOR } ;
FACTOR = ("+" | "-"), FACTOR | "(", EXPRESSION, ")" | NUMBER ;
NUMBER = DIGIT, {DIGIT} ;
DIGIT = 0 | 1 | ... | 9 ;
IDENTIFIER = LETTER, {LETTER | DIGIT | "_"} ;
LETTER = a | b | ... | z | A | B | ... | Z ;
```