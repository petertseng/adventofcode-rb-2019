TO_DESTROY = 200

def asteroid_in_direction(start, dy, dx, asteroids, height, width)
  # Be careful here.
  # You cannot just add (dy * width + dx) to (y * width + x) blindly.
  # You might wrap around a row when you're not supposed to.
  # (To detect this, see whether y changed more than you expected it to)
  # It's too much work to track that so I'll just keep y and x separate.
  y, x = start.divmod(width)
  y += dy
  x += dx

  pos = y * width + x
  dpos = dy * width + dx

  while (0...height).cover?(y) && (0...width).cover?(x)
    return pos if asteroids[pos]
    y += dy
    x += dx
    pos += dpos
  end
  nil
end

def detect?(a1, a2, asteroids, height, width)
  y1, x1 = a1.divmod(width)
  y2, x2 = a2.divmod(width)
  dy = y2 - y1
  dx = x2 - x1
  g = dy.gcd(dx)

  # This shortcut saves a little bit of time.
  # The code would still be correct without it,
  # so it's purely for saving a little bit of unnecessary work.
  return true if g == 1

  asteroid_in_direction(a1, dy / g, dx / g, asteroids, height, width) == a2
end

verbose = ARGV.delete('-v')
input = ARGF.map(&:chomp).map(&:freeze).freeze
height = input.size
width = input.map(&:size).max

# Just like day 03, encode a coordinate as y * width + x,
# because creating [y, x] for all asteroids is bad perf.
# About 2.4x as fast with this.
asteroids = {}
input.each_with_index { |row, y|
  row.chars.each_with_index { |c, x|
    asteroids[y * width + x] = true if c == ?#
  }
}

detect = Hash.new(0)

asteroids.keys.combination(2) { |a1, a2|
  # For each pair, check whether they detect each other.
  # Another idea: add their reduced (dy, dx) to a set,
  # and find the set with the most elements.
  # That turns out to be about 1.5x slower.
  if detect?(a1, a2, asteroids, height, width)
    detect[a1] += 1
    detect[a2] += 1
  end
}

station, max = detect.max_by(&:last)
p max
p station if verbose

# <= instead of < is intentioal: can't destroy itself!
if asteroids.size <= TO_DESTROY
  puts "bad #{asteroids.size}"
  exit 1
end

sy, sx = station.divmod(width)
has_at_least = Hash.new(0)
in_dir = Hash.new { |h, k| h[k] = [] }

# Using rationals is slightly faster than using atan2.
# Could also skip entire quadrants with more granular counters
# (quadrant_has_at_least instead of has_at_least)
# but part 2 runs in about 1/30 the time of part 1
# (even with atan2), so it's not worth optimising further.
asteroids.keys.each { |pos|
  next if pos == station
  y, x = pos2d = pos.divmod(width)
  dy = y - sy
  dx = x - sx
  # Sort as follows:
  # 0 = directly above (dx = 0, dy < 0)
  # 1 = right (dx > 0), then sort by angle
  # 2 = directly below (dx = 0, dy > 0)
  # 3 = left (dx < 0), then sort by angle
  key = (dx == 0 ? [dy < 0 ? 0 : 2] : [dx > 0 ? 1 : 3, Rational(dy, dx)]).freeze
  new_size = (in_dir[key] << pos2d).size
  has_at_least[new_size] += 1
}

remain = TO_DESTROY
round = 1
until has_at_least[round] >= remain
  remain -= has_at_least[round]
  round += 1
end

candidates = round == 1 ? in_dir : in_dir.select { |_, v| v.size >= round }
_, at_angle = candidates.sort_by(&:first)[remain - 1]
y, x = at_angle.min_by(round) { |y, x| (y - sy).abs + (x - sx).abs }[-1]
puts x * 100 + y
