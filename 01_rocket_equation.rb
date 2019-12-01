def fuel(mass)
  mass / 3 - 2
end

def fuel_of_fuel(mass)
  Enumerator.produce(fuel(mass), &method(:fuel)).take_while(&:positive?).sum
  # Another idea: https://blog.vero.site/post/advent-rocket
  # d3 = (mass + 3).digits(3)
  # (mass - d3.sum + 15) / 2 - d3[-1] - 3 * d3.size
end

input = ARGF.map(&method(:Integer)).freeze
puts input.sum(&method(:fuel))
puts input.sum(&method(:fuel_of_fuel))
