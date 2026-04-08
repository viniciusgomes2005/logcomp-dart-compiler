-- Base de testes com: while + if + and/or/not + read()
n = read()
i = 1
f = 1

if (not (n < 0) and (n > 1 or n == 1)) then
    while (i < n or i == n) do
        f = f * i
        i = i + 1
    end
else
    f = 0
end

print(f)
