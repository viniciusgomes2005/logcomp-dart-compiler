# logcomp-dart-compiler

[![Compilation Status](https://compiler-tester.insper-comp.com.br/svg/viniciusgomes2005/logcomp-dart-compiler)](https://compiler-tester.insper-comp.com.br/svg/viniciusgomes2005/logcomp-dart-compiler)

This repository is monitored by Compiler Tester for automatic compilation status.

## Diagrama Sintático

```mermaid
flowchart TD
    Start((Start)) --> Expr[EXPRESSION]
    Expr --> ExprLoop{"+ | - | ^ ?"}
    ExprLoop -->|sim| TermInExpr[TERM]
    TermInExpr --> ExprLoop
    ExprLoop -->|não| End((EOF))

    Expr --> Term[TERM]
    Term --> TermLoop{"* | / ?"}
    TermLoop -->|sim| FactorInTerm[FACTOR]
    FactorInTerm --> TermLoop
    TermLoop -->|não| ReturnTerm[retorna TERM]

    Term --> Factor[FACTOR]
    Factor --> Unary{"+ ou - ?"}
    Unary -->|sim| FactorUnary[FACTOR]
    Unary -->|não| GroupOrInt{"( EXPRESSION ) ou INT"}
    GroupOrInt --> ReturnFactor[retorna FACTOR]
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
EXPRESSION = TERM, { ("+" | "-"), TERM } ;
TERM = FACTOR, { ("*" | "/"), FACTOR } ;
FACTOR = ("+" | "-"), FACTOR | "(", EXPRESSION, ")" | NUMBER ;
NUMBER = DIGIT, {DIGIT} ;
DIGIT = 0 | 1 | ... | 9 ;
```