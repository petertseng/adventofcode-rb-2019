# Alternate idea: Store only segment endpoints,
# and then calculate intersections between them.
# Don't feel like doing the work right now.
def trace_wire(wire_segments, origin)
  pos = origin
  total_dist = 0

  wire_segments.each { |direction, length|
    length.times {
      total_dist += 1
      pos += direction
      yield pos, total_dist
    }
  }
end

total = Hash.new(0)

# Change to a one-dimensional coordinate system
# because creating a 2-element array for each position is expensive.
wires = ARGF.map { |l|
  wire_total = Hash.new(0)
  l.split(?,).map { |seg|
    [seg[0], Integer(seg[1..-1])].tap { |dir, length| wire_total[dir] += length }
  }.tap { total.merge!(wire_total) { |_, v1, v2| [v1, v2].max } }
}.freeze

raise "expected two wires not #{wires.size}" if wires.size != 2

# There are this many possible values for the x coordinate,
# so increasing y needs to increase by this many.
# Do need to include 0 here, for +1, since 0 is a possible value.
horiz_span = (-total[?L]..total[?R]).size
# Equivalent to:
# horiz_span = total[?L] + total[?R] + 1

# Do need to translate x coordinates to all positives,
# because otherwise [y, -x] gets treated by divmod as [y - 1, horiz_span - x],
# which gives the wrong distance from origin.
# Test that demonstrates the failure:
# ruby 03_crossed_wires.rb <(echo "L5,D5\nD5,L5")
# Should be 10, but is 7 if origin = 0.
# Fortunately, y coordinates can safely be negatives.
origin = total[?L]

dir_change = {
  ?U => horiz_span,
  ?D => -horiz_span,
  ?L => -1,
  ?R => 1,
}.freeze

wire1, wire2 = wires.map { |wire| wire.map { |dir, length| [dir_change[dir], length].freeze } }

dist = {}
trace_wire(wire1, origin) { |pos, total_dist|
  #puts "#{total_dist}: Wire 1 at #{pos}"
  dist[pos] ||= total_dist
}
dist.freeze

from_origin = []
on_wire = []

trace_wire(wire2, origin) { |pos, total_dist|
  #puts "#{total_dist}: Wire 2 at #{pos}"
  next unless (other_dist = dist[pos])
  coords = pos.divmod(horiz_span)
  coords[-1] -= origin
  #p coords
  from_origin << coords.sum(&:abs)
  on_wire << total_dist + other_dist
}

puts from_origin.min
puts on_wire.min
