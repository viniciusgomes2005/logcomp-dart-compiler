function fat(n number) number
  if n == 0 then
    return 1
  end
  return n * fat(n - 1)
end

print(fat(5))
