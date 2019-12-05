require_relative 'lib/intcode'

DISAS = ARGV.delete('-d')

def ic(mem, input)
  ops = (1..8).to_a + [99]
  Intcode.new(mem, valid_ops: ops).then { |ic| ic.continue(disas: DISAS, input: input) }.output
end

input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

output = ic(input, 1)
all_but_last = output[0..-2]
raise "nonzero outputs #{all_but_last}" unless all_but_last.all?(&:zero?)
puts output[-1]

puts ic(input, 5)
