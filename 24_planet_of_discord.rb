SIDE_LEN = 5

NUM_ITERS = Hash.new(200)
NUM_ITERS[1205552] = 10

# Only 4 values are important: 0, 1, 2, 3+ (dead for sure)
# that's 2 bits
BITS_PER_NEIGHBOUR_COUNT = 2
NEIGHBOUR_COUNT_MASK = (1 << BITS_PER_NEIGHBOUR_COUNT) - 1

# For deciding whether a cell is alive at the next iteration,
# precompute groups at a time, keyed by concatenation of (neighbour counts, alive bits)
# (to disable cache, just lift the `until` and replace the `until` in `grow_bugs`)
# Through experimentation, 4 was a good group size? You'd think 5, but that was slower.
GROUP_SIZE = 4
BITS_PER_NEIGHBOUR_COUNT_GROUP = BITS_PER_NEIGHBOUR_COUNT * GROUP_SIZE
NEIGHBOUR_COUNT_GROUP_MASK = (1 << BITS_PER_NEIGHBOUR_COUNT_GROUP) - 1
ALIVE_GROUP_MASK = (1 << GROUP_SIZE) - 1
GROUP_CACHE = (1 << (GROUP_SIZE * (BITS_PER_NEIGHBOUR_COUNT + 1))).times.map { |x|
  ncs = (x >> GROUP_SIZE) & NEIGHBOUR_COUNT_GROUP_MASK
  current_alive = x & ALIVE_GROUP_MASK

  pos = 0
  new_level = 0

  until ncs == 0
    nc = ncs & NEIGHBOUR_COUNT_MASK
    now_alive = nc == 1 || nc == 2 && current_alive & 1 == 0
    new_level |= 1 << pos if now_alive
    ncs >>= BITS_PER_NEIGHBOUR_COUNT
    current_alive >>= 1
    pos += 1
  end

  new_level
}.freeze

def grow_bugs(grids, neigh)
  # Keyed by level, each value is the concatenated neighbour counts of all cells.
  # Takes advantage of the fact that it's only possible to spread one level above and below.
  # -1 will be at the end of the array, using negative indexing.
  # Slightly faster than using Hash.new(0) and lmin, lmax = neigh_count.keys.minmax
  neigh_count = Array.new(grids.size + 2, 0)

  grids.each_with_index { |grid, level|
    neigh.each { |v|
      masked = grid & v[:mask]
      v[:neigh][masked].each { |dlevel, neigh_contribs|
        existing = neigh_count[level + dlevel]
        if existing == 0
          neigh_count[level + dlevel] = neigh_contribs
        else
          # Saturating add on each group of two bits.
          # These formulae were determined by examining all 16 possibilities,
          # and determining formulae by hand.
          a = existing & 0xaaaaaaaaaaaaaaa
          b = existing & 0x555555555555555
          c = neigh_contribs & 0xaaaaaaaaaaaaaaa
          d = neigh_contribs & 0x555555555555555
          bd = b & d
          # upper_bits is pretty much exactly like an adder.
          upper_bits = a | c | (bd << 1)
          alow = a >> 1
          clow = c >> 1
          # lower_bits would normally be like an adder (just b ^ d),
          # but also adds the following:
          # alow & clow, so that 10+10 == 11
          # bd & (alow | clow), so that 11+01 == 01+11 == 11
          lower_bits = (b ^ d) | (alow & clow) | (bd & (alow | clow))
          # Alternative:
          # Only cases where lower bit is 0: 00+00, 00+10, 01+01, 10+00.
          # So lower bit is 1 if b | d, except if it's 01+01,
          # And also need to make 10+10 == 11, which alow & clow will do.
          #lower_bits = ((b | d) & (alow | clow | ~bd)) | (alow & clow)
          neigh_count[level + dlevel] = upper_bits | lower_bits
        end
      }
    }
  }

  lmin = -1
  lmin += 1 until neigh_count[lmin] != 0
  lmax = grids.size
  lmax -= 1 until neigh_count[lmax] != 0

  # Note this doesn't preserve indices, but it doesn't matter.
  # Careful to preserve empty levels, however.
  (lmin..lmax).map { |level|
    ncs = neigh_count[level]
    current_alive = (0...grids.size).cover?(level) ? grids[level] : 0
    pos = 0
    new_level = 0
    until ncs == 0
      nc = ncs & NEIGHBOUR_COUNT_GROUP_MASK
      now_alive = current_alive & ALIVE_GROUP_MASK
      new_level |= GROUP_CACHE[(nc << GROUP_SIZE) | now_alive] << pos
      ncs >>= BITS_PER_NEIGHBOUR_COUNT_GROUP
      current_alive >>= GROUP_SIZE
      pos += GROUP_SIZE
    end
    new_level
  }
end

# the neighbours of each individual position
# Hash[position] => Array[Tuple[delta_depth, position]]
def neigh_map(side_len, recursive: false)
  mid_coord = side_len / 2
  in_bounds = ->*ns { ns.all? { |n| (0...side_len).cover?(n) } }

  directions = [
    [-1, 0, ->nx { [1, side_len - 1, nx] }],
    [1, 0,  ->nx { [1, 0,            nx] }],
    [0, -1, ->ny { [1, ny,           side_len - 1] }],
    [0, 1,  ->ny { [1, ny,           0] }],
  ].map(&:freeze).freeze

  (side_len * side_len).times.map { |pos|
    y, x = pos.divmod(side_len)

    unless recursive
      next directions.filter_map { |dy, dx, _|
        ny = y + dy
        nx = x + dx
        [0, ny * side_len + nx] if in_bounds[ny, nx]
      }
    end

    directions.flat_map { |dy, dx, inner_neigh|
      ny = y + dy
      nx = x + dx
      if ny == mid_coord && nx == mid_coord
        side_len.times.map(&inner_neigh)
      elsif in_bounds[ny, nx]
        [[0, ny, nx]]
      else
        [[-1, mid_coord + dy, mid_coord + dx]]
      end
    }.map { |d, ny, nx| [d, ny * side_len + nx] }
  }.freeze
end

# Array[Group]
# Group = {
#   mask: Int
#   neigh: Hash[Int => Array[Tuple[delta_depth, neighbour_counts]]]
# }
# To compute the neighbour contributions of a group,
# mask the grid bitfield with the group's mask,
# then index into the neigh map.
# Multiple neighbour counts are to be combined with saturating add.
def grouped_neigh_map(side_len, recursive: false)
  neigh_map = neigh_map(side_len, recursive: recursive)
  mid_coord = side_len / 2

  groups = Hash.new { |h, k| h[k] = [] }
  (side_len * side_len).times { |pos|
    # This seems to be a good division,
    # balancing between not having any one group be too large
    # vs not having to do as many neighbour count saturating additions.
    # Current sizes are 4, 6, 6, 5, 4
    # It does perform slightly better than the obvious `group = pos / 5`
    y, x = pos.divmod(side_len)
    on_vert_edge = y == 0 || y == side_len - 1
    on_horiz_edge = x == 0 || x == side_len - 1
    group = if on_vert_edge && on_horiz_edge
      :corner
    elsif on_vert_edge
      :vert_edge
    elsif on_horiz_edge
      :horiz_edge
    elsif y == mid_coord || x == mid_coord
      :mid
    else
      :other
    end
    groups[group] << pos
  }

  groups.values.map { |group|
    neigh = (1 << group.size).times.to_h { |n|
      n_bits = n.digits(2)
      # neigh_count[dlevel][npos] = 0..3
      # Could use one integer (all counts concatenated),
      # but this function is such a small portion of the runtime that it's not worth it.
      neigh_count = Hash.new { |h, k| h[k] = Hash.new(0) }
      shifted = group.zip(n_bits).sum { |pos, bit| (bit || 0) << pos }
      n_bits.zip(group) { |bit, pos|
        next if bit == 0
        neigh_map[pos].each { |dlevel, npos|
          neigh_count[dlevel][npos] += 1
        }
      }
      [shifted, neigh_count.transform_values { |count_for_level|
        count_for_level.sum { |npos, count_for_pos|
          [count_for_pos, NEIGHBOUR_COUNT_MASK].min << (npos * BITS_PER_NEIGHBOUR_COUNT)
        }
      }.freeze]
    }
    raise "Should be #{1 << group.size} in neighbours map, only have #{neigh.size}" if neigh.size != 1 << group.size
    {
      neigh: neigh.freeze,
      mask: group.sum { |b| 1 << b },
    }.freeze
  }.freeze
end

def first_repeat(x)
  seen = {}
  until seen[x]
    seen[x] = true
    x = yield x
  end
  [x, seen.size]
end

def show_grids(grids)
  size = SIDE_LEN * SIDE_LEN
  grids.each_with_index { |g, i|
    puts i if grids.size > 1
    bits = g.digits(2)
    bits << 0 until bits.size == size
    bits.each_slice(SIDE_LEN) { |row| puts row.join.tr('01', '.#') }
    puts
  }
end

verbose = ARGV.delete('-v')
bit = {?# => 1, ?. => 0}.freeze
input = ARGV[0]&.match?(/^[0-9]$/) ? Integer(ARGV) : ARGF.map { |l|
  l.chomp.tap { |lc| raise "wrong size #{l}" if lc.size != SIDE_LEN }
}.join.each_char.with_index.sum { |c, i| bit.fetch(c) << i }

raise "too big #{input}" if input >= 1 << (SIDE_LEN * SIDE_LEN)

neigh = grouped_neigh_map(SIDE_LEN)

if verbose && NUM_ITERS[input] <= 10
  grids = [input]

  puts "----- 0 minutes -----"
  show_grids(grids)

  NUM_ITERS[input].times { |i|
    grids = grow_bugs(grids, neigh)

    puts "----- #{i + 1} minutes -----"
    show_grids(grids)
  }
end

repeat, time = first_repeat(input) { |x|
  xs = grow_bugs([x], neigh)
  raise "expanded to another level in part 1??? #{xs}" if xs.size > 1
  xs[0] || 0
}
if verbose
  puts "----- repeat after #{time} minutes -----"
  show_grids([repeat])
end
p repeat

neigh = grouped_neigh_map(SIDE_LEN, recursive: true)
grids = [input]
NUM_ITERS[input].times {
  grids = grow_bugs(grids, neigh)
}
if verbose
  puts "----- #{NUM_ITERS[input]} minutes, recursive -----"
  show_grids(grids)
end
p grids.sum { |g| g.digits(2).count(1) }
