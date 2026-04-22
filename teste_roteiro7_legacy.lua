-- Roteiro 6 com declarações explícitas (compatibilidade estrutural)
local n number = 5
local i number = 1
local f number = 1

if (not (n < 0) and (n > 1 or n == 1)) then
    while (i < n or i == n) do
        f = f * i
        i = i + 1
    end
else
    f = 0
end

print(f)
