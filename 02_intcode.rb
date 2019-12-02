require_relative 'lib/intcode'

def run(mem, noun, verb)
  mem = mem.dup
  mem[1] = noun
  mem[2] = verb
  Intcode.new(mem, valid_ops: [1, 2, 99]).then(&:continue).memory[0]
end

input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

puts run(input, 12, 2)

# Note that for known Advent of Code inputs,
# mem[0] = noun * N + verb * V + base
# And V = 1, but I'll allow for others.

base = run(input, 0, 0)
delta_noun = run(input, 1, 0) - base
delta_verb = run(input, 0, 1) - base

target = 19690720

if delta_noun > delta_verb
  noun = (target - base) / delta_noun
  verb = (target - base - delta_noun * noun) / delta_verb
else
  verb = (target - base) / delta_verb
  noun = (target - base - delta_verb * verb) / delta_noun
end

puts noun * 100 + verb
