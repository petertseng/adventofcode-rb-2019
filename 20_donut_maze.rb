require_relative 'lib/search'

def parse_maze(flat_input, height, width)
  portal_pairs = Hash.new { |h, k| h[k] = {outer: nil, inner: nil} }
  portal_entrances = {}

  dirs = [-width, width, -1, 1].freeze

  flat_input.each_char.with_index { |cell, pos|
    next if pos < width
    next unless flat_input[pos + width]

    # Find letters with dots next to them.
    next unless (?A..?Z).cover?(cell)
    dirs_with_dot = dirs.select { |dpos| flat_input[pos + dpos] == ?. }
    raise "more than one dot for #{pos} (#{pos.divmod(width)}): #{dirs_with_dot}" if dirs_with_dot.size > 1
    next unless (dir_with_dot = dirs_with_dot[0])

    other_letter = flat_input[pos - dir_with_dot]

    # dot below (+width) or to right (+1) of letter means other letter comes first.
    # dot above (-width) or to left (-1) of letter means other letter comes second.
    id = (dir_with_dot > 0 ? other_letter + cell : cell + other_letter).freeze

    y, x = (pos - dir_with_dot).divmod(width)
    type = y == 0 || y == height - 1 || x == 0 || x == width - 1 ? :outer : :inner

    raise "REPEAT #{id} #{type}" if portal_pairs[id][type]
    dot_pos = pos + dir_with_dot
    portal_entrances[dot_pos] = true
    portal_pairs[id][type] = dot_pos
  }

  portal_entrances.freeze

  outer = ->k {
    raise "no #{k}" unless (pair = portal_pairs.delete(k))
    raise "inner #{k} #{pair[:inner]}" if pair[:inner]
    pair[:outer]
  }

  start = outer['AA']
  goal = outer['ZZ']

  portal_pairs.each { |k, v|
    raise "MISSING INNER FOR #{k}" unless v[:inner]
    raise "MISSING OUTER FOR #{k}" unless v[:outer]
  }
  portal_pairs.freeze

  dists = portal_pairs.values.flat_map { |v|
    [
      [v[:outer], [v[:inner], 1, -1].freeze],
      [v[:inner], [v[:outer], 1, 1].freeze],
    ]
  }.to_h

  portal_to_portal = portal_to_portal(flat_input, dirs, portal_entrances)

  [
    start, goal,
    # not using this anymore (failed heuristic)
    nil && min_in_out(portal_pairs, portal_to_portal),
    dists.merge!(portal_to_portal) { |_, v1, v2| (v2 << v1).freeze }.freeze,
  ]
end

def min_in_out(portal_pairs, portal_to_portal)
  outers = portal_pairs.values.to_h { |v| [v[:outer], true] }
  portal_pairs.values.flat_map { |v|
    next [] unless (inner = v[:inner])
    portal_to_portal[inner].filter_map { |dest, dist, ddepth|
      next if ddepth != 0
      next unless outers[dest]
      dist
    }
  }.min
end

def portal_to_portal(flat_input, dirs, portal_entrances)
  portal_entrances.keys.to_h { |src|
    other_portals = Search.bfs(
      src, num_goals: Float::INFINITY,
      neighbours: ->pos {
        dirs.map { |dpos| pos + dpos }.select { |npos| flat_input[npos] == ?. }
      },
      goal: ->pos { pos != src && portal_entrances.has_key?(pos) },
    )

    [src, other_portals[:goals].map { |pos, dist| [pos, dist, 0].freeze }]
  }.freeze
end

input = ARGF.map(&:chomp).map(&:freeze).freeze
width = input.map(&:size).max
flat_input = input.map { |l| l.ljust(width, ' ') }.join.freeze
height = input.size
start, goal, _min_in_out, dists = parse_maze(flat_input, height, width)
maze_size = flat_input.size

# Attempts to prove a bound on depth have failed:
# https://www.reddit.com/r/adventofcode/comments/ed5ei2/2019_day_20_solutions/fbg6p0s/
# Maze with:
# long corridor whose distance means an optimal solution crosses it once
# left side allowing depths 4, 9, 14... to connect to long corridor
# right side allowing depths 6, 12, 18... to connect to long corridor
# Only contains 11 portal pairs, but best path would go down to depth 24.
#
# Only remaining hope is if there is a property of the inputs to exploit.
#
# However, I need to set some limit here, to allow example 2 to pass on part 2 test.
# Don't want to doom myself to wander the halls of Pluto for all eternity.
# The input described above had its depth determined by multiplying (n - k) * k
# So we'll just limit at the maximum this value could be,
# which is splitting the number of pairs in half as equally as possible.
# 11 -> 6 * 5, 12 -> 6 * 6, etc.
portal_pairs = (dists.size - 2) / 2
half_up = (portal_pairs + 1) / 2
max_depth = portal_pairs / 2 * half_up

search = ->depth_mult {
  cost, _junk = Search.astar(
    start,
    goal: {goal => true}.freeze,
    neighbours: ->depth_and_pos {
      depth, pos = depth_and_pos.divmod(maze_size)
      dists[pos].filter_map { |dest, dist, depth_change|
        new_depth = depth + depth_change * depth_mult
        [new_depth * maze_size + dest, dist] if (0..max_depth).cover?(new_depth)
      }
    },
    heuristic: ->depth_and_pos {
      0
      # I would like to use this, but it's non-monotonic (AKA inconsistent),
      # 1. that will cause MonotonePriorityQueue to raise.
      # 2. my A* implementation assumes I never need to revisit a node,
      #    but with an inconsistent heuristic, you might.
      # I could use PriorityQueue along with this heuristic,
      # but PriorityQueue slowdown is more than the heuristic's speedup.
      #depth = depth_and_pos / maze_size
      #depth * (min_in_out + 1)
      # Why it's inconsistent:
      # Moving from an outer portal at depth 1 to an inner portal at depth 0
      # costs only 1, but decreases heuristic from (min_in_out + 1) to 0.
      # This violates the requirement: h(x) <= d(x, y) + h(y)
      # because min_in_out + 1 > 1 + 0
    },
  )
  cost || 'impossible'
}

puts search[0]
puts search[1]
