local A number = 2
function myprint(text string)
  print(text)
end

function fac(x number) number
  if (x == 1) then
    return 1
  end
  return x * fac(x - 1)
end

function sum(x number, y number) number
  return x + y
end

function tautology() boolean
  return true
end

function main()
  local x_1 number
  x_1 = read()
  local x_2 number = fac(4)
  print(A)
  print(x_2)
  do
    local x_2 number = 7
    x_1 = 9
    A = 8
    print(x_2)
  end
  print(A)
  print(x_1)

  if ((x_1 > 1 and not not not (x_1 < 1)) or x_1 == 9) then
    x_1 = 2
  end

  local x number = 3 + 6 / 3 * 2 -+- + 2 * 4 / 2 + 0 / 1 - ((6 + ((4))) / (2))
  local y_1 number = 3
  y_1 = sum(y_1, x_1)
  local z__ number
  z__ = x + y_1

  if (x_1 == 2) then
    x_1 = 2
  end

  if (x_1 == 3) then
    x_1 = 2
  else
    x_1 = 3
  end

  x_1 = 0
  while (x_1 < 1 or x == 2) do
    print(x_1)
    x_1 = x_1 + 1
  end

  do
    do
    end
  end

  print(x_1)
  print(x)
  print(z__ + 1)

  local y number = 2
  local z number
  z = (y - 1)
  print(y + z)
  print(y - z)
  print(y * z)
  print(y / z)
  print(y == z)
  print(y < z)
  print(y > z)

  local a string
  local b string

  x_1 = 1
  y = 1
  z = 2
  a = "abc"
  b = "def"
  myprint(a..b)
  myprint(a)
  print(a..x_1)
  print(x_1..a)
  print(a..(x_1 == 1))
  print(a == a)
  print(a < b)
  print(a > b)
end

main()
