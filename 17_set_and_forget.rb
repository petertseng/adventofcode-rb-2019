require_relative 'lib/intcode'

def exactly_one(name, things)
  raise "need exactly one #{name}, not #{things}" if things.size != 1
  things[0]
end

def modes(op)
  [(op / 100) % 10, (op / 1000) % 10]
end

def read_intcode_map(mem)
  _, dust_update = find_dust(mem)

  width = mem[dust_update].each_cons(4) { |op, arg1, arg2, _|
    next if op % 100 != 2
    modes = modes(op)
    break arg1 if modes == [1, 2]
    break arg2 if modes == [2, 1]
  }

  dot = true
  pos = 0
  scaffold = {}
  inter = Hash.new(0)

  range = mem[7, 2].max...mem[11, 2].max
  mem[range].each { |len|
    if dot
      pos += len
    else
      len.times {
        scaffold[pos] = true
        inter[pos] = 1 if scaffold[pos - 1] && scaffold[pos - width]
        inter[pos - 1] += 1
        inter[pos - width] += 1
        pos += 1
      }
    end
    dot = !dot
  }

  robot_loc = mem[robot_loc_addr(mem, dust_update), 2].reverse
  alignment_sum = inter.sum { |pos, v|
    raise "impossible #{pos} #{v}" unless (0..3).cover?(v)
    v == 3 ? pos.divmod(width).reduce(:*) : 0
  }
  [robot_loc, scaffold.keys.map { |x| x.divmod(width) }, width, alignment_sum]
end

def read_ascii_map(img)
  img = img.lines.map(&:freeze).freeze

  alignment_sum = 0

  robot_loc = nil
  scaffold = []

  width = img.map { |x| x.chomp.size }.max

  img.each_with_index { |row, y|
    break if row == "\n"
    row.chomp.chars.each_with_index { |cell, x|
      case cell
      when ?#
        scaffold << [y, x]
        intersection = x > 0 && y > 0 && img[y][x - 1, 3] == '###' && img[y - 1][x] == ?# && img[y + 1]&.[](x) == ?#
        alignment_sum += y * x if intersection
      when ?.
        # ok
      when ?^
        raise "multiple robots? #{robot_loc} vs #{y} #{x}" if robot_loc
        robot_loc = [y, x]
      else raise "bad char #{cell}"
      end
    }
  }

  [robot_loc, scaffold, width, alignment_sum]
end

def robot_loc_addr(mem, dust_update)
  compare = mem[dust_update].each_cons(4).find { |op, *| op % 100 == 8 }
  exactly_one('robot loc', compare[1, 2].zip(modes(compare[0])).filter_map { |v, mode|
    v if mode == 0
  })
end

def find_dust(mem)
  dust = exactly_one('dust location', mem.each_cons(3).filter_map { |(a, b, c)|
    b if a == 4 && c == 99
  })

  dust_update = exactly_one(
    'dust_update',
    Intcode.functions(mem).select { |f|
      mem[f].each_cons(4).any? { |(a, _, _, d)|
        # Writes to the dust address
        a < 20000 && [1, 2].include?(a % 100) && d == dust
      }
    },
  )

  [dust, dust_update]
end

def teleport_robot(ic, scaffold)
  mem = ic.mem

  dust, dust_update = find_dust(mem)
  robot_loc_addr = robot_loc_addr(mem, dust_update)

  # Turn printing off
  mem[robot_loc_addr - 1] = 0

  # Set return addr to current pos (where we're pausing for input)
  # so it pauses for input after having called the function
  mem[ic.relative_base] = ic.pos

  scaffold.each { |y, x|
    # Teleport to this scaffold location and call dust update function.
    mem[robot_loc_addr, 2] = [x, y]
    ic.continue(hijack: dust_update.begin, input: [])
  }

  mem[dust]
end

# This is not actually that much faster,
# but might as well keep the code to have for reference.
def auto_dust(mem, scaffold, width)
  _, dust_update = find_dust(mem)

  scaffold_base_addr = exactly_one(
    'scaffold base address',
    mem[dust_update].each_cons(8).with_index(dust_update.begin).flat_map { |insts, i|
      # We're looking for three instructions of this pattern:
      # write S11 S12 D1
      # write S21 S22 D2
      # anything S31 S32 ...
      op1, _, _, dst1, op2, _, _, dst2 = insts
      next [] unless [op1, op2].all? { |op| [1, 2].include?(op % 100) }

      # third instruction must be an array read (D2 must point to S31 or S32)
      next [] if op2 >= 20000
      next [] unless [i + 9, i + 10].include?(dst2)

      # second instruction must use result of the first (D1 must equal one of S21 or S22)
      next [] if dst1 == 0
      next [] unless insts[5, 2].include?(dst1)

      # Anything that looks like a base address offset
      insts[1, 2].zip(modes(op1)).filter_map { |v, mode| v if v > 0 && mode == 1 }
    },
  )

  scaffold.each_with_index.sum { |(y, x), i|
    scaffold_base_addr + x + y * width + x * y + i + 1
  }
end

slower = ARGV.delete('-ss')
slow = ARGV.delete('-s')
input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read)

if input.include?(?,)
  mem = input.split(?,).map(&method(:Integer)).freeze
  ic = Intcode.new([2] + mem.drop(1))
  if slow || slower
    ic.continue(input: [])
    map = read_ascii_map(ic.ascii_output)
  else
    map = read_intcode_map(mem)
  end
elsif input.include?(?#)
  map = read_ascii_map(input)
else
  raise 'Unknown kind of input'
end

robot_loc, scaffold, width, alignment_sum = map

p alignment_sum

if ic && !slower
  if slow
    puts teleport_robot(ic, scaffold)
  else
    puts auto_dust(ic.mem, scaffold, width)
  end
  exit 0
end

# legit version not written yet...
_ = robot_loc
puts 'possible'
