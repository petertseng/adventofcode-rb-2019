require_relative 'lib/intcode'

OPT = !ARGV.delete('--no-opt')
SPARSE = ARGV.delete('-sp')
DISAS_DYNAMIC = ARGV.delete('-dd')
disas_static = ARGV.delete('-ds')
stats = ARGV.delete('-s')

def run(mem, input)
  Intcode.new(mem, sparse: SPARSE, funopt: OPT).continue(disas: DISAS_DYNAMIC, input: input).output
end

mem = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

puts run(mem, 1)
puts run(mem, 2)

Intcode.disas(mem) if disas_static

if stats
  ic = Intcode.new(mem)
  ic.continue(stats: true, input: 2)
  p ic.times_run.sort_by(&:last)
  p ic.jumps_taken.sort_by(&:last)
end
