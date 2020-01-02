require_relative 'lib/search'
require_relative 'lib/union_find'

def bitfield(chars, range)
  base = range.begin.ord
  chars.select { |c| range.cover?(c) }.map { |c| 1 << (c.ord - base) }.reduce(0, :|)
end

def key_to_key(flat_input, width, sources)
  # AoC-specific optimisation:
  # For all paths between key -> key that contain doors,
  # the doors block the ONLY path to the key.
  # Given this property is true, all key -> key paths are precomputed.
  # This property is false for these inputs, with sources:
  # https://www.reddit.com/r/adventofcode/comments/ecj4e7/2019_day_18_challenging_input/
  # ##########
  # #.a###.Ab#
  # #.B..@.###
  # #...######
  # ##########
  # https://www.reddit.com/r/adventofcode/comments/ecgyey/2019_day_18_part_1_im_not_seeing_how_to_optimize/fbc3iih/
  # #######
  # #....@#
  # #.###A#
  # #.###b#
  # #.aBCc#
  # #######

  idx = sources.each_with_index.to_h

  # BFS from {start, each key} to all other single keys.
  # Paths picking up multiple keys will be computed after, using this info.
  # Positions will be renumbered to be their index in the list.
  sources.map { |src|
    have_new_key = ->pos { pos != src && (?a..?z).cover?(flat_input[pos]) }

    keys = Search.bfs(
      src, num_goals: Float::INFINITY,
      neighbours: ->pos {
        next [] if have_new_key[pos]
        [pos - width, pos + width, pos - 1, pos + 1].select { |npos|
          flat_input[npos] != ?#
        }
      },
      goal: have_new_key,
    )

    keys[:goals].to_h { |pos, dist|
      path = Search.path_of(keys[:prev], pos)
      things_on_path = path.map { |path_pos| flat_input[path_pos] }

      [idx[pos], {
        from: i,
        pos: idx[pos],
        dist: dist,
        # Represent keys and doors as bitfields so set intersections become cheap
        keys: bitfield([flat_input[pos], flat_input[src]], ?a..?z),
        doors: bitfield(things_on_path, ?A..?Z),
      }.freeze]
    }
  }
end

def all_pairs(keys_from)
  # https://en.wikipedia.org/wiki/Floyd%E2%80%93Warshall_algorithm
  # Using this is much faster than traveling the entire map for each key.
  keys_from.each_index { |k|
    keys_from.each_index { |i|
      next if k == i
      next unless (ik = keys_from.dig(i, k))
      keys_from.each_index { |j|
        next if i == j || k == j
        next unless (kj = keys_from.dig(k, j))
        new_dist = ik[:dist] + kj[:dist]
        ij = keys_from.dig(i, j)
        if !ij || ij[:dist] > new_dist
          keys_from[i][j] = {
            from: i,
            pos: kj[:pos],
            dist: new_dist,
            keys: ik[:keys] | kj[:keys],
            doors: ik[:doors] | kj[:doors],
          }.freeze
        end
      }
    }
  }

  keys_from.map { |vs| vs.values.sort_by { |v| -v[:dist] }.freeze }.freeze
end

def all_keys_time(keys_from, num_keys, robots)
  all_keys = (1 << num_keys) - 1

  # Pack all robot positions into one int.
  # Now that positions are renumbered to max 31 (4 robots + 26 keys + 1 dummy start),
  # they fit in 5 bits.
  # With the key bitfield taking 26 bits, the entire state fits within 46 bits.
  bits_per_robot = keys_from.size.bit_length
  robot_mask = (1 << bits_per_robot) - 1
  robot_base = (0...robots.size).map { |i| bits_per_robot * i + num_keys }

  edges = keys_from.flatten.select { |k| k[:from] < k[:pos] }.sort_by { |k| k[:dist] }
  mst_cache = {}

  cost, _junk = Search.astar(
    # Assumption: Renumbering done by keys_from put the robots first.
    robots.zip(robot_base).map { |bot, base| bot << base }.reduce(0, :|),
    neighbours: ->(robots_and_keys) {
      keys = robots_and_keys & all_keys
      robot_base.flat_map { |base|
        robot = (robots_and_keys >> base) & robot_mask

        keys_from[robot].filter_map { |key|
          # Have these keys already.
          next if key[:keys] | keys == keys
          # Don't have all keys needed.
          next unless key[:doors] | keys == keys

          [(robots_and_keys & ~(robot_mask << base)) | (key[:pos] << base) | key[:keys], key[:dist]]
        }
      }
    },
    # heuristic - max dist to remaining keys is at most harmless,
    # but does help for certain inputs, it seems.
    # Also tried unsuccessfully:
    # * MST of remaining keys
    # * number remaining keys * minimum distance between two keys
    # * Dijkstra's:
    # heuristic: Hash.new(0),
    heuristic: ->(robots_and_keys) {
      keys = robots_and_keys & all_keys
      robot_base.sum { |base|
        robot = (robots_and_keys >> base) & robot_mask
        remaining_keys = keys_from[robot].select { |key|
          key[:keys] | keys != keys
        }
        key_poses = remaining_keys.map { |k| k[:pos] } << robot
        key_bits = key_poses.sum { |k| 1 << k }

        mst_cache[key_bits] ||= begin
          mst_cost = 0
          relevant_edges = edges.select { |k|
            key_bits[k[:from]] != 0 && key_bits[k[:pos]] != 0
          }
          # This is slower
          #relevant_edges = key_poses.flat_map { |pos|
          #  keys_from[pos].select { |k| key_bits[k[:pos]] != 0 && k[:from] < k[:pos] }
          #}.sort_by { |k| k[:dist] }
          forests = UnionFind.new(key_poses)
          relevant_edges.each { |k|
            u = forests.find(k[:from])
            v = forests.find(k[:pos])
            next if u == v

            mst_cost += k[:dist]
            forests.union(u, v)
          }

          mst_cost
        end
      }
    },
    goal: ->(robots_and_keys) { robots_and_keys & all_keys == all_keys },
  )

  cost
end

input = ARGF.map(&:chomp).map(&:freeze).freeze
# Represent position as y * width + x, indexing into flattened grid.
# The edge of the grid is all walls, so this is fine.
width = input.map(&:size).max
flat_input = input.map { |l| l.ljust(width, ' ') }.join.freeze

keys = []
robots = []

input.each_with_index { |row, y|
  row.chars.each_with_index { |cell, x|
    pos = y * width + x
    keys << pos if (?a..?z).cover?(cell)
    robots << pos if cell == ?@
  }
}

# If this is a part 1 that can be converted to a part 2, then do both.
# If not, it's fine, just do what's given, since tests use maps that only do part 1 or only do part 2.

can_part_2 = robots.size == 1 && begin
  bot = robots[0]
  diagonal = [-width, width].product([-1, 1]).map(&:sum)
  orthogonal = [-width, width, -1, 1]
  surrounding = diagonal + orthogonal
  surrounding.all? { |s| flat_input[bot + s] == ?. }
end

if can_part_2
  # Calculate the key-to-key map for part 2,
  # then transform it into one for part 1.
  # (This is faster because of traveling the map fewer times)
  robots = diagonal.map { |diag| bot + diag }
  flat_input = flat_input.dup
  orthogonal.each { |orth| flat_input[bot + orth] = ?# }
  flat_input.freeze

  k2k = key_to_key(flat_input, width, [bot] + robots + keys)

  k2k1 = k2k.map(&:dup)
  add_pair = ->(i, j, dist) {
    k2k1[i][j] = {from: i, pos: j, dist: dist, keys: 0, doors: 0}.freeze
    k2k1[j][i] = {from: j, pos: i, dist: dist, keys: 0, doors: 0}.freeze
  }
  (1..4).each { |i|
    # Allow each key to go back to the corner (part 2 entrances).
    # Normally, they would not try to because the corner has no keys.
    k2k1[i].each { |k, v| k2k1[k][i] = v.merge(from: k, pos: i) }
    # Centre (part 1 entrance) is 2 away from each corner (part 2 entrances)
    add_pair[0, i, 2]
  }
  (1..4).to_a.combination(2) { |i, j|
    # Allow each corner (part 2 entrances) to reach each other.
    y1, x1 = robots[i - 1].divmod(width)
    y2, x2 = robots[j - 1].divmod(width)
    add_pair[i, j, (y1 - y2).abs + (x1 - x2).abs]
  }

  puts all_keys_time(all_pairs(k2k1), keys.size, [0])
  puts all_keys_time(all_pairs(k2k), keys.size, (1..robots.size).to_a)
else
  k2k = key_to_key(flat_input, width, robots + keys)
  puts all_keys_time(all_pairs(k2k), keys.size, (0...robots.size).to_a)
end
