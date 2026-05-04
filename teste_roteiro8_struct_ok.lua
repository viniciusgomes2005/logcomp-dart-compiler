struct A
  local b number
end

function main()
  local x A
  x.b = 1
  print(x.b)
end

main()
