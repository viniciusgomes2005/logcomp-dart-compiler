-- Roteiro 7 v2.2 - cenário válido
local nome string = "Ana"
local idade number = 20
local ativo boolean = true
local pi float = 1.6
local msg string

msg = nome + " tem " + idade + " anos"
print(msg)

if (ativo and idade > 17) then
    print("if valido")
else
    print("if invalido")
end

local i number = 1
local acumulado number = 1
while (i < 5) do
    acumulado = acumulado * i
    i = i + 1
end
print(acumulado)

local x number = (number) pi
print(x)

pi = x + pi
print(pi)
