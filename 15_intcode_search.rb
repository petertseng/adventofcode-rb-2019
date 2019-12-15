require_relative 'lib/intcode'
require_relative 'lib/search'

# Unknown grid size (well, I know it's 41x41, but without that knowledge)
# we'll assume they won't exceed approx 1<<29 in each direction.
# Two coordinates; (1<<60).object_id indicates it is still Fixnum, not Bignum.
COORD = 30
Y = 1 << COORD
ORIGIN = (Y / 2) << COORD | (Y / 2)
MOVE = [nil, -Y, Y, -1, 1]

COMPUTERS = {}

def search(start, goal:, verbose: false)
  Search.bfs(
    start,
    neighbours: ->(pos) {
      # Actually, we could be really naive,
      # and only track the last direction traveled,
      # and avoid reversing it (don't go south if you just went north)
      # This works because there are no 2x2 open areas in the maze.
      # But I'll actually track my position,
      # which allows me to draw the maze if I choose to (debugging only).
      (1..4).filter_map { |move|
        new_pos = pos + MOVE[move]
        COMPUTERS[new_pos] ||= COMPUTERS[pos].dup.continue(input: move)
        new_pos if COMPUTERS[new_pos].output.last != 0
      }
    },
    goal: goal,
    verbose: verbose,
  )
end

disas = ARGV.delete('-d')
draw_map = ARGV.delete('-m')

input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

COMPUTERS[ORIGIN] = Intcode.new(input)

result = search(ORIGIN, goal: ->pos { COMPUTERS[pos].output.last == 2 }, verbose: disas)
raise 'oxygen not found' if result[:goals].empty?
puts result[:gen]

if disas
  path = result[:paths].values.first.each_cons(2).map { |a, b| MOVE.index(b - a) }
  ic = Intcode.new(input).continue(input: path, stats: true)
  Intcode.disas(ic.mem, addrs_run: ic.times_run)
end

puts search(result[:goals].keys.first, goal: ->_ { false })[:gen]

Kernel.exit(0) unless draw_map

ys, xs = COMPUTERS.keys.map { |pos| pos.divmod(Y) }.transpose
Range.new(*ys.minmax).each { |y|
  puts Range.new(*xs.minmax).map { |x|
    pos = y * Y + x
    next ?S if pos == ORIGIN
    next ?# unless (computer = COMPUTERS[pos])
    case computer.output.last
    when 0; ?#
    when 1; ' '
    when 2; ?O
    end
  }.join
}
