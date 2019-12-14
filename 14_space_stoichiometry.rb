def ore_to_make(things, leftovers = Hash.new(0), ceil: true, verbose: false)
  puts "make #{things} w/ leftovers #{leftovers.select { |_, v| v > 0 }}" if verbose
  return things[:ORE] if things.keys == [:ORE]

  ore_to_make({}.merge(*things.map { |thing, amount_needed|
    next {ORE: amount_needed} if thing == :ORE

    if leftovers.has_key?(thing)
      use_leftover = [leftovers[thing], amount_needed].min
      amount_needed -= use_leftover
      leftovers[thing] -= use_leftover
    end

    recipe = RECIPES[thing]
    times = Rational(amount_needed, recipe[:produced])
    times = times.ceil if ceil
    next {} if times == 0

    recipe[:inputs].transform_values { |v| v * times }.tap {
      leftovers[thing] += recipe[:produced] * times - amount_needed
    }
  }) { |_, v1, v2| v1 + v2 }, leftovers, ceil: ceil, verbose: verbose)
end

def name_and_amount(thing)
  amount, name = thing.split
  [name.to_sym, Integer(amount)]
end

RECIPES = {}

verbose = ARGV.delete('-v')

ARGF.each_line { |l|
  inputs, output = l.split(' => ')
  output_name, output_amount = name_and_amount(output)
  if (existing = RECIPES[output_name])
    raise "#{output_name} already has #{existing}"
  end
  RECIPES[output_name] = {
    produced: output_amount,
    inputs: inputs.split(', ').to_h { |x| name_and_amount(x) }.freeze
  }.freeze
}

RECIPES.freeze

puts make_one = ore_to_make({FUEL: 1}, verbose: verbose)

trillion = 1_000_000_000_000

# The binary search still runs almost instantly even with bounds (1..trillion)
# so these tighter bounds aren't strictly necessary.
lower_bound = trillion / make_one
upper_bound = (trillion / ore_to_make({FUEL: 1}, ceil: false)).ceil

puts (lower_bound..upper_bound).bsearch { |x|
  ore_to_make({FUEL: x}) > trillion
} - 1
