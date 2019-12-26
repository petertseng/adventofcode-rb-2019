# Two possible approaches:
# 1. Store a set of all points touched by each wire,
#    do a set intersection.
#
# 2. Store all segment endpoints and intersect them.
#
# Turns out, the second one is faster.

# 0 = unchanging coordinate
# 1 = changing coordinate min
# 2 = changing coordinate max
# 3 = length at min
# 4 = delta length while moving toward max

wires = ARGF.map { |l|
  horiz = []
  vert = []
  y = 0
  x = 0
  total_length = 0

  l.split(?,).map { |seg|
    dir = seg[0]
    length = Integer(seg[1..-1])

    old_y = y
    old_x = x
    old_length = total_length

    total_length += length
    case dir
    when ?U
      y -= length
      vert << [x, y, old_y, total_length, -1]
    when ?D
      y += length
      vert << [x, old_y, y, old_length, 1]
    when ?L
      x -= length
      horiz << [y, x, old_x, total_length, -1]
    when ?R
      x += length
      horiz << [y, old_x, x, old_length, 1]
    end
  }

  {horiz: horiz.freeze, vert: vert.freeze}.freeze
}.freeze

raise "expected two wires not #{wires.size}" if wires.size != 2

from_origin = []
on_wire = []

[
  [wires[0][:horiz], wires[1][:vert]],
  [wires[1][:horiz], wires[0][:vert]],
].each { |horizs, verts|
  horizs.each { |y1, x1min, x1max, l1min, l1d|
    verts.each { |x2, y2min, y2max, l2min, l2d|
      next unless (y2min..y2max).cover?(y1)
      next unless (x1min..x1max).cover?(x2)
      next if y1 == 0 && x2 == 0

      from_origin << y1.abs + x2.abs

      l1 = l1min + l1d * (x2 - x1min)
      l2 = l2min + l2d * (y1 - y2min)
      on_wire << l1 + l2
    }
  }
}

puts from_origin.min
puts on_wire.min
