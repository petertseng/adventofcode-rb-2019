require 'set'

require_relative 'lib/intcode'

# Unknown grid size
# we'll assume they won't exceed approx 1<<29 in each direction.
# Two coordinates; (1<<60).object_id indicates it is still Fixnum, not Bignum.
COORD = 30
Y = 1 << COORD
ORIGIN = (Y / 2) << COORD | (Y / 2)
L = -1
R = 1
U = -Y
D = Y

TURN = [
  # 0 = left
  {U => L, L => D, D => R, R => U}.freeze,
  # 1 = right
  {U => R, L => U, D => L, R => D}.freeze,
].freeze

def understand_ant(mem)
  ic = Intcode.new(mem).continue(input: 0)
  initial_pair = ic.output.dup
  ic.output.clear

  pos = ic.pos
  ic.continue(input: 1)
  ic.continue(input: 1) until ic.pos == pos

  # Expectations:
  # The ant runs N cycles where each cycle takes M inputs
  # Colours is always the opposite of what's given.
  # Turns checks whether the input is the same as it was M inputs ago (1 cycle ago).
  # One cycle isn't actually enough to tell that both patterns hold,
  # but I don't feel like being smarter.
  colours, turns = ic.output.each_slice(2).to_a.transpose
  raise "unexpected colours #{colours}" if colours.include?(1)

  # Determine N by examining the code:
  halt = mem.index(99)
  insts = mem[halt - 7, 7]
  cmp, arg1, arg2, dst, jmp, jmparg, jmpdst = insts
  raise "compare isn't a compare: #{insts}" unless [7, 8].include?(cmp % 100)
  raise "compare doesn't compare pos to immed: #{insts}" unless [1, 10].include?(cmp / 100)
  n = cmp / 100 == 1 ? arg1 : arg2
  raise "jump isn't a jump: #{insts}" unless [5, 6].include?(jmp % 100)
  raise "jump doesn't test comparison result: #{insts}" if jmparg != dst
  raise "jump destination isn't initial position: #{insts}" if jmpdst != pos

  {
    initial_pair: initial_pair.freeze,
    # For easier accounting, I'll report how many inputs I need to take.
    # The code does a <, and the counter gets incremented before compared,
    # so it's 1 fewer cycle than the printed value of N.
    n: (n - 1) * turns.size,
    state: turns.freeze,
  }
end

def run(keep_drawing, draw, origin_white: false)
  visited = Set.new

  pos = ORIGIN
  white = Set.new
  white.add(pos) if origin_white

  n = origin_white ? 0 : 0

  dir = U

  while keep_drawing[]
    # The programs for this day have been sure to give exactly two outputs per one input,
    # but this would handle other ratios.

    output = draw[white.include?(pos) ? 1 : 0]

    while output.size >= 2
      colour, turn = output.shift(2)
      visited << pos
      if n > 0
        STDERR.puts("#{colour} #{turn} from #{pos.divmod(Y).map { |x| x - Y / 2 }}")
        n -= 1
      end

      white.send(colour == 1 ? :<< : :delete, pos)
      dir = TURN[turn][dir]
      pos += dir
    end
  end

  [white, visited]
end

slow = ARGV.delete('-s')
input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

_, visit = if slow
  ic = Intcode.new(input)
  run(->{ !ic.halted? }, ->w { ic.continue(input: w).output })
else
  ant = understand_ant(input)
  initial_consumed = false
  ant_state = ant[:state].dup

  run(->{ ant[:n] > 0 }, ->w {
    unless initial_consumed
      initial_consumed = true
      next ant[:initial_pair].dup
    end
    ant[:n] -= 1
    prev = ant_state.shift
    ant_state << w
    [1 - w, w ^ prev ^ 1]
  })
end

puts visit.size

ic = Intcode.new(input)
white, _ = run(->{ !ic.halted? }, ->w { ic.continue(input: w).output }, origin_white: true)
ys, xs = white.to_a.map { |pos| pos.divmod(Y) }.transpose

Range.new(*ys.minmax).each { |y|
  puts Range.new(*xs.minmax).map { |x|
    white.include?(y * Y + x) ? ?# : ' '
  }.join
}
