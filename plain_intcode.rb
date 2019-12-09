require_relative 'lib/intcode'

DISAS = ARGV.delete('-d')
MEM = ARGV.delete('-m')

def run(mem, inputs)
  mem = mem.dup
  inputs = inputs.dup
  Intcode.new(mem).continue(disas: DISAS, mem_all: MEM, input: -> { inputs.shift })
end

mem = ARGV.shift.split(?,).map(&method(:Integer)).freeze
inputs = ARGV.map(&method(:Integer))

ic = run(mem, inputs)
puts "%0 #{ic.memory[0]}"
puts "out #{ic.output}"
