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

# can't destroy itself, so exactly 200 is also not enough. <= instead of < is intentional.
if asteroids.size <= 200
  puts "bad #{asteroids.size}"
  exit 1
end

# Encoding these as dy * width + dx would require translating negative dx.
# And part 2 takes only 1/30 the time of part 1, not worth trying to improve it.
dirs = (-height..height).flat_map { |dy|
  (-width..width).filter_map { |dx|
    [dy, dx] if dy.gcd(dx) == 1
  }
}

count = 0
# atan2 returns between -pi and pi.
# Returns pi for (0, -1)
# We want [dy = -1, dx = 0] to be first,
# So that means we do atan2(dx, dy) and reverse it.
dirs.sort_by { |dy, dx| -Math.atan2(dx, dy) }.cycle { |dy, dx|
  next unless (asteroid = asteroid_in_direction(station, dy, dx, asteroids, height, width))
  asteroids.delete(asteroid)
  puts "#{count + 1} destroy #{asteroid.divmod(width)}" if verbose
  if (count += 1) == 200
    y, x = asteroid.divmod(width)
    puts x * 100 + y
    break
  end
}
