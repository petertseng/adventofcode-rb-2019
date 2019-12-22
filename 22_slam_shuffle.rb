def simplify_at(steps, i, deck_size)
  return unless (op2, arg2 = steps[i + 1])
  op1, arg1 = steps[i]

  # Adjacent pairs of the same operation can be combined.
  # (dealwith by multiplication, cut by addition, reverse by elimination)
  #
  # Adjacent pairs of different operation can be transposed,
  # if applying an appropriate transformation to the pair
  # (see each pair for details on its appropriate transformation).
  #
  # Sift all dealwith to the front of the list,
  # and all reverse to the back of the list.
  #
  # Applied enough times, the list should end with just one of each operation.
  case [op1, op2]
  when [:dealwith, :dealwith]
    steps[i, 2] = [
      [:dealwith, (arg1 * arg2) % deck_size].freeze,
    ]
  when [:cut, :dealwith]
    # consider a 10-card deck:
    # cut 2:
    # 2 3 4 5 6 7 8 9 0 1
    # cut 2, deal incr 3
    # 2 9 6 3 0 7 4 1 8 5
    # deal incr 3:
    # 0 7 4 1 8 5 2 9 6 3
    # deal incr 3, cut 6:
    # 2 9 6 3 0 7 4 1 8 5
    # so cut N, deal incr M = deal incr M, cut (N * M)
    steps[i, 2] = [
      [:dealwith, arg2].freeze,
      [:cut, (arg1 * arg2) % deck_size].freeze,
    ]
  when [:cut, :cut]
    steps[i, 2] = [
      [:cut, (arg1 + arg2) % deck_size].freeze,
    ]
  when [:reverse, :dealwith]
    # consider a 10-card deck:
    # reverse, deal incr 3:
    # 9 2 5 8 1 4 7 0 3 6
    # deal incr 7:
    # 0 3 6 9 2 5 8 1 4 7
    # deal incr 7, cut 3:
    # 9 2 5 8 1 4 7 0 3 6
    # so reverse, deal incr N = deal incr (size - N), cut N
    steps[i, 2] = [
      [:dealwith, deck_size - arg2].freeze,
      [:cut, arg2].freeze,
    ]
  when [:reverse, :cut]
    steps[i, 2] = [
      [:cut, -arg2].freeze,
      [:reverse].freeze,
    ]
  when [:reverse, :reverse]
    steps[i, 2] = []
  end
end

def simplify(steps, deck_size)
  until steps.map(&:first).uniq.size == steps.size
    steps.each_index { |i| simplify_at(steps, i, deck_size) }
  end
end

def modular_inverse(a, n)
  t, newt = [0, 1]
  r, newr = [n, a]
  until newr == 0
    q = r / newr
    t, newt = [newt, t - q * newt]
    r, newr = [newr, r - q * newr]
  end
  r > 1 ? nil : t % n
end

def apply(steps, initial_pos, deck_size)
  steps.reduce(initial_pos) { |pos, (op, arg)|
    case op
    when :dealwith
      (pos * arg) % deck_size
    when :reverse
      deck_size - 1 - pos
    when :cut
      (pos - arg) % deck_size
    else raise "unknown #{op} #{arg}"
    end
  }
end

verbose = ARGV.delete('-v')
input = ARGF.map(&:chomp).map(&:freeze).freeze

test = input.size < 40
deck_size = test ? 10 : 10007

steps = input.map { |a|
  words = a.split

  if words[0, 2] == ['deal', 'with']
    n = Integer(words[-1])
    [:dealwith, n].freeze
  elsif words[0, 2] == ['deal', 'into']
    [:reverse].freeze
  elsif words[0] == 'cut'
    n = Integer(words[-1])
    [:cut, n].freeze
  else raise "unknown #{words}"
  end
}

before_simp = steps.dup.freeze
simplify(steps, deck_size)
p steps if verbose

if test
  decks = [before_simp, steps].map { |s|
    deck = (0...deck_size).to_h { |pos| [apply(s, pos, deck_size), pos] }
    ((0...deck_size).map(&deck))
  }
  raise "different decks #{decks}" if decks.uniq.size != 1
  puts decks[0].join(' ')
  exit 0
end

puts apply(steps, 2019, deck_size)

bits = {}
deck_size = 119315717514047

steps = before_simp.dup
simplify(steps, deck_size)

# Apply the shuffle repeatedly via exponentiation.
power = 1
num_shuffles = 101741582076661
until power > num_shuffles
  bits[power] = steps.dup.freeze
  power <<= 1
  steps.concat(steps)
  simplify(steps, deck_size)
end

relevant_bits = bits.keys.select { |k| num_shuffles & k != 0 }
raise "WRONG BITS!!! #{relevant_bits.sum} vs #{num_shuffles}" if relevant_bits.sum != num_shuffles
final = relevant_bits.flat_map(&bits)
simplify(final, deck_size)
p final if verbose

pos = 2020
final.reverse_each { |op, arg|
  case op
  when :dealwith
    pos = (pos * modular_inverse(arg, deck_size)) % deck_size
  when :reverse
    pos = deck_size - 1 - pos
  when :cut
    pos = (pos + arg) % deck_size
  else raise "Unknown #{op} #{arg}"
  end
}
p pos
