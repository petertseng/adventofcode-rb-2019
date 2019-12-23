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
verbose = ARGV.delete('-v')
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

def left((dy, dx))
  # (-1, 0) -> (0, -1) -> (1, 0) -> (0, 1) -> (-1, 0)
  [-dx, dy]
end

def right((dy, dx))
  # (-1, 0) -> (0, 1) -> (1, 0) -> (0, -1) -> (-1, 0)
  [dx, -dy]
end

move = ->dir { robot_loc.zip(dir).map(&:sum) }

scaffold = scaffold.to_h { |x| [x, true] }
remain_scaffold = scaffold.dup

can_move = ->dir { scaffold[move[dir]] }

steps = []
robot_dir = [-1, 0]

until remain_scaffold.empty?
  moves = 0
  while can_move[robot_dir]
    robot_loc = move[robot_dir]
    moves += 1
    remain_scaffold.delete(robot_loc)
    next
  end
  steps << moves if moves > 0
  break if remain_scaffold.empty?

  can_turn = %i(left right).select { |dir| can_move[send(dir, robot_dir)] }
  if can_turn.size == 1
    steps << can_turn[0]
    robot_dir = send(can_turn[0], robot_dir)
    next
  end

  raise "need exactly one turn at #{robot_loc}, not #{can_turn}"
end

steps_str = steps.map { |x| {left: ?L, right: ?R}[x] || (?F * x) }.join

MAX_LEN = 20

# Only meant for use when items will STRICTLY alternate between F and non-F.
# Not for use for displaying intermediate compression results, where we might have AA etc.,
# which would just show up as A.
def chunk(func_raw)
  func_raw.chars.chunk(&:itself).map { |letter, insts| letter == ?F ? insts.size : letter }
end

# OK for use when showing intermediate compression results
def chunk2(func_raw)
  func_raw.chars.chunk { |x| x == ?F }.flat_map { |f, insts| f ? [insts.size] : insts }
end

def compress(
  free_letters, main, assigned_letters = [],
  split_moves: false, split_turns: false, split_turns2: false,
  verbose: false
)
  if free_letters.empty?
    chars = main.chars
    return [] unless chars.all? { |c| (?A..?C).cover?(c) }
    main = chars.join(?,)

    return [] if main.size > MAX_LEN
    return [[main] + assigned_letters]
  end

  unless (start = main.chars.index { |c| !(?A..?C).cover?(c) })
    # Erm, I guess we don't need to assign anything more?
    return compress([], main, assigned_letters + free_letters.map { '' })
  end

  letter = free_letters.first
  possible_lengths = []

  1.step { |len|
    break if (?A..?C).cover?(main[start + len - 1])
    break if start + len > main.size
    next if !split_moves && main[start + len - 1] == ?F && main[start + len] == ?F

    func_raw = main[start, len]
    func_chunks = chunk(func_raw)
    comma_joined_length = func_chunks.join(?,).size
    break if comma_joined_length > MAX_LEN

    possible_lengths << [func_raw, func_chunks, comma_joined_length]
  }

  possible_lengths.reverse_each.flat_map { |func_raw, func_chunks, comma_joined_length|
    # If it ends on a number, consider adding a turn to this function and the opposite turn to the next.
    # Not necessary on askalski's input, but I remain convinced it's theoretically necessary.
    # See mk17.rb A,A,B,C,A,C,C,B,A    R,10,L,6,L,10,R,6,L    6,L,4,L,10,R,10,L,8    R,8,L,10,L,6,R,6
    possible_funcs = if split_turns2 && func_chunks[-1].is_a?(Integer) && comma_joined_length + 2 <= MAX_LEN
      turn_pairs = [[nil, ''], [?L, ?R], [?R, ?L]]
      turn_pairs.map { |term_turn, add_turn|
        [
          func_raw,
          (func_chunks + (term_turn ? [term_turn] : [])).join(?,),
          letter + add_turn,
        ]
      }
    else
      [[func_raw, func_chunks.join(?,), letter]]
    end

    possible_funcs.flat_map { |func_raw, func_comma, replace_with|
      allowed_subs = [[func_raw, replace_with]]
      if split_turns && func_raw.size > 1
        # If it starts with a turn, also allow placing the opposite turn before.
        if func_raw.start_with?(?R)
          allowed_subs << [func_raw[1..-1], ?L + replace_with]
        elsif func_raw.start_with?(?L)
          allowed_subs << [func_raw[1..-1], ?R + replace_with]
        end
      end
      if split_turns2 && func_raw.size > 1 && replace_with.size > 1 && 'LR'.include?(func_comma[-1])
        # Function ends with a turn (such as A = 10,R), there are two choices:
        # Replace 10 with A,L (equivalent to 10,R,L = 10)
        # Replace 10,R with A
        allowed_subs << [func_raw + func_comma[-1], replace_with[0..-2]]
        allowed_subs << ['LR', '']
        allowed_subs << ['RL', '']
      end

      new_main = main.dup
      allowed_subs.each { |from, to|
        new_main.gsub!(from, to)
        # If it ends with a turn, allow replacing at the very end as well.
        if from.size > 1 && 'LR'.include?(from[-1])
          new_main.sub!(/#{from[0..-2]}$/, to)
        end
      }

      # Since function calls are irreducible,
      # prune search if we have too many of them.
      # (N function calls needs N-1 commas, so it's 2N-1)
      function_calls = new_main.chars.count { |c| (?A..?C).cover?(c) }
      next [] if function_calls * 2 - 1 > MAX_LEN

      # For debugging, put the expected letter assignments here.
      expected = [
        nil,
      ]
      right_track = (assigned_letters + [func_comma]).zip(expected).all? { |a, b| a == b }

      if verbose || right_track
        puts "#{chunk2(main).join(?,)}: assign #{letter} <- #{func_comma}, replace #{func_raw} w/ #{replace_with}, now #{chunk2(new_main).join(?,)}"
      end

      compress(
        free_letters[1..-1], new_main, assigned_letters + [func_comma],
        verbose: verbose, split_moves: split_moves, split_turns: split_turns,
      )
    }
  }
end

# split_moves and split_turns only needed to solve some hard inputs:
# https://www.reddit.com/r/adventofcode/comments/ebz338/2019_day_17_part_2_pathological_pathfinding/
# Try it without them first, then try it if needed.
solns = compress(%w(A B C), steps_str)
solns = compress(%w(A B C), steps_str, split_moves: true, split_turns: true) if solns.empty?
if solns.empty?
  puts 'split_turns2 needed' if verbose
  solns = compress(%w(A B C), steps_str, split_moves: true, split_turns: true, split_turns2: true)
end
solns.each { |soln|
  soln << ?n
  if ic
    output = ic.dup.continue(input: soln).output
    puts output.select { |x| x > 127 }
  end
}
if verbose
  puts solns
elsif !ic
  puts solns.empty? ? 'impossible' : 'possible'
end
