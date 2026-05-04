local b number = 5

function soma(x number, y number) number
  local a number
  a = x + y
  print(a)
  return a
end

function main()
  local a number
  do
    local b number
    a = 3
    b = soma(a, 4)
    print(b)
  end
  print(a)
  print(b)
end

main()
