(0..3).each { |x|
  (0..3).each { |y|
    expected = [x + y, 3].min

    a = x & 0xa
    b = x & 0x5
    c = y & 0xa
    d = y & 0x5

    bd = b & d
    upper_bits = a | c | (bd << 1)
    al = a >> 1
    cl = c >> 1
    lower_bits = (b ^ d) | (al & cl) | (bd & (al | cl))
    got = upper_bits | lower_bits

    if got != expected
      nb = ->n { "#{n} (#{n.to_s(2).rjust(2, ?0)})" }
      puts "#{nb[x]} + #{nb[y]}: Got #{nb[got]}, want #{nb[expected]}"
    end
  }
}
