require_relative 'lib/intcode'

SPARSE = ARGV.delete('-s')
DISAS_DYNAMIC = ARGV.delete('-dd')

def run(mem, input)
  Intcode.new(mem, sparse: SPARSE).continue(disas: DISAS_DYNAMIC, input: input).output
end

mem = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

puts run(mem, 1)
puts run(mem, 2)
