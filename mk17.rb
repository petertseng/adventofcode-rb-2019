def scaffold(path)
  robot_loc = [0, 0].freeze
  move = ->dir { robot_loc.zip(dir).map(&:sum).freeze }

  dir = [-1, 0]
  prev_inter = false

  scaffold = {robot_loc => true}

  path.split(?,) { |x|
    if x == ?R
      dir = right(dir)
      next
    elsif x == ?L
      dir = left(dir)
      next
    else
      Integer(x).times {
        robot_loc = move[dir]
        if scaffold[robot_loc]
          puts "WARNING: path doubles back, most solvers can't handle" if prev_inter
          prev_inter = true
        else
          prev_inter = false
        end
        scaffold[robot_loc] = true
      }
    end
  }

  scaffold.keys.sort
end

def left((dy, dx))
  # (-1, 0) -> (0, -1) -> (1, 0) -> (0, 1) -> (-1, 0)
  [-dx, dy]
end

def right((dy, dx))
  # (-1, 0) -> (0, 1) -> (1, 0) -> (0, -1) -> (-1, 0)
  [dx, -dy]
end

f = {}
main, f[?A], f[?B], f[?C] = ARGV

expand_main = main.gsub(/[A-C]/, f)
puts expand_main

no_rl_main = expand_main.split(?,).map { |x| Integer(x) rescue x }
while (_, i = no_rl_main.each_cons(2).each_with_index.find { |x, i| i if [[?R, ?L], [?L, ?R]].include?(x) })
  before = no_rl_main[i - 1] || 0
  after = no_rl_main[i + 2] || 0
  raise 'Too many turns in a row' unless before.is_a?(Integer)
  raise 'Too many turns in a row' unless after.is_a?(Integer)
  if i == 0
    no_rl_main[0, 3] = after
  else
    no_rl_main[i - 1, 4] = before + after
  end
end
while (_, i = no_rl_main.each_cons(2).each_with_index.find { |x, i| i if x.all? { |y| y.is_a?(Integer) } })
  no_rl_main[i, 2] = no_rl_main[i] + no_rl_main[i + 1]
end

scaffold1 = scaffold(expand_main)
ys, xs = scaffold1.transpose

no_rl_main = no_rl_main.join(?,)
scaffold2 = scaffold(no_rl_main)
raise "WRONG #{scaffold1 - scaffold2} vs #{scaffold2 - scaffold1}" if scaffold1 != scaffold2
puts no_rl_main

Range.new(*ys.minmax).each { |y|
  puts Range.new(*xs.minmax).map { |x|
    [y, x] == [0, 0] ? ?^ : scaffold1.include?([y, x]) ? ?# : ?.
  }.join
}

puts "main: #{main.size}"
f.each { |k, v|
  puts "#{k}: #{v.size}"
}
f.keys.permutation(2) { |x|
  puts "#{x}: #{main.include?(x.join(?,))}"
}
