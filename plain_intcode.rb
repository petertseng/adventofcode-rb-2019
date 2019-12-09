require_relative 'lib/intcode'

DISAS_DYNAMIC = ARGV.delete('-dd')
disas_static = ARGV.delete('-ds')
MEM = ARGV.delete('-m')

def run(mem, inputs)
  mem = mem.dup
  inputs = inputs.dup
  Intcode.new(mem).continue(disas: DISAS_DYNAMIC, mem_all: MEM, input: -> { inputs.shift })
end

mem = ARGV.shift.split(?,).map(&method(:Integer)).freeze
inputs = ARGV.map(&method(:Integer))

ic = run(mem, inputs)
Intcode.disas(ic.mem) if disas_static
puts "%0 #{ic.memory[0]}"
puts "out #{ic.output}"
