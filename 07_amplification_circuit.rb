require_relative 'lib/intcode'

VERBOSE = ARGV.delete('-v')

def const_input(mem, phase, input)
  ic = Intcode.new(mem, valid_ops: (1..8).to_a + [99]).continue(input: phase)
  ic.continue(input: input) until ic.halted?
  ic.output
end

# Assume each amplifier performs a linear mx+b transform.
# Determine m and b by running the amplifiers once, instead of once per permutation.
# Could take it even farther with dynamic programming:
# https://www.reddit.com/r/adventofcode/comments/e7q8fp/2019_day_7_part_2_c_feed_it_forward/
# But this is fast enough and I don't care.
def chain(mem, phases)
  amps = phases.to_h { |phase| [phase, {
    b: b = const_input(mem, phase, 0),
    m: const_input(mem, phase, 1).zip(b).map { |y, bb| y - bb },
  }.freeze] }.freeze

  puts amps if VERBOSE

  sizes = amps.values.flat_map { |a| [a[:b].size, a[:m].size] }.uniq
  raise "Incompatible sizes #{sizes}" if sizes.size != 1

  phases.permutation.map { |perm|
    ms = perm.map { |phase| amps[phase][:m] }.transpose.flatten
    bs = perm.map { |phase| amps[phase][:b] }.transpose.flatten
    ms.zip(bs).reduce(0) { |signal, (m, b)| m * signal + b }
  }.max
end

input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

[0...5, 5...10].each { |range| puts chain(input, range.to_a) }
