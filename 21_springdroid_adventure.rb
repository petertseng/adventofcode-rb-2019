require_relative 'lib/intcode'

VERBOSE = ARGV.delete('-v')

def run(mem, script, **args)
  Intcode.new(mem).continue(input: script, **args)
end

def show_damage(ic)
  puts ic.output.select { |x| x <= 127 }.pack('c*') if VERBOSE
  puts ic.output.select { |x| x > 127 }
end

def exactly_one_function(mem, name)
  exactly_one(
    name,
    Intcode.functions(mem).select { |f|
      mem[f].each_cons(4).any? { |x| yield x }
    },
  )
end

def exactly_one(name, things)
  raise "need exactly one #{name}, not #{things}" if things.size != 1
  things[0]
end

def modes(op)
  [(op / 100) % 10, (op / 1000) % 10]
end

# Approach 1:
# The slowest way.
# Actually runs the Springscript interpreter with a real script.

def run_springscript_scripts(mem)
  # !A+!CD
  # Also viable:
  # !(A+B+C)D and equivalent (!A+!B+!C)D
  show_damage(run(mem, <<~CODE))
  NOT C J
  AND D J
  NOT A T
  OR T J
  WALK
  CODE

  # D!(AB(C+!H))
  # equivalent D(!A+!B+(!CH))
  # Alternatives:
  # !A+!(BC)DH and equivalent !A+(!B+!C)DH
  # (!A+!B+!C)D(E+H) and equivalent !(ABC)D(E+H)
  # !A+!B!E+!CD(E+H)
  show_damage(run(mem, <<~CODE))
  NOT H J
  OR C J
  AND A J
  AND B J
  NOT J J
  AND D J
  RUN
  CODE
end

# Approach 2:
# An okay way, showcasing the use of the CUSTOM_OPCODE.
# Overwrite the Springscript interpreter and use Ruby to decide when to jump.

def overwrite_springscript_interpreter(input)
  # What address stores the number of instructions?
  viable_addresses = nil
  # 1 is used often as the identity for multiplication, so start at 2.
  (2..15).each { |num_insts|
    ic = run(input, ['NOT T T'] * num_insts << 'WALK')
    # Assume it's not on the stack.
    viable_for_num = ic.mem[0, ic.relative_base].each_with_index.filter_map { |val, addr|
      addr if val == num_insts
    }
    viable_addresses ||= viable_for_num
    viable_addresses &= viable_for_num
    break if viable_addresses.size <= 1
  }
  num_insts_addr = exactly_one('number of instructions', viable_addresses)

  mem = input.dup

  # The Springscript runner needs to compare against the number of instructions,
  # so that it knows whether it finished running the script.
  # (Okay, it could do other things like just look for a sentinel value,
  # but it so happens that it does do a comparison against this value)

  springscript_runner = exactly_one_function(mem, 'springscript runner') { |op, *operands, _|
    [7, 8].include?(op % 100) && operands.zip(modes(op)).include?([num_insts_addr, 0])
  }

  stack_frame_size = mem[springscript_runner.begin + 1]

  hull_addr = exactly_one(
    'hull array base address',
    mem[springscript_runner].each_cons(12).with_index(springscript_runner.begin).flat_map { |insts, i|
      # We're looking for three instructions of this pattern:
      # write S11 S12 D1
      # write S21 S22 D2
      # write S31 S32 D3
      op1, _, _, dst1, op2, _, _, dst2, op3 = insts
      next [] unless [op1, op2, op3].all? { |op| [1, 2].include?(op % 100) }

      # third instruction must be an an array read (D2 must point to S31 or S32)
      next [] if op2 >= 20000
      next [] unless [i + 9, i + 10].include?(dst2)

      # second instruction must use result of the first (D1 must equal one of S21 or S22)
      src2 = insts[5, 2].zip(modes(op2))
      next [] unless src2.include?([dst1, 0])

      # the argument to the runner must be an input (one of S11, S12, S21, S22 is $rb[-...])
      srcs = src2 + insts[1, 2].zip(modes(op1))
      next [] unless srcs.include?([-(stack_frame_size - 1), 2])

      # Anything that looks like a base address offset
      srcs.filter_map { |v, mode| v if v > 0 && mode == 1 }
    },
  )

  mem[springscript_runner.begin] = Intcode::CUSTOM_OPCODE

  run_ruby_jumper = ->(command, &should_jump) {
    read_len = {WALK: 4, RUN: 9}.fetch(command)

    show_damage(run(mem, command.to_s, custom: ->ic {
      # Springdroid pos was passed as an argument to Springscript function:
      springdroid_pos = ic.mem[ic.relative_base + 1]

      # Read next values from hull (values of A, B, C... etc).
      # Note that we do not read our current position, so add 1.
      regs = ic.mem[hull_addr + springdroid_pos + 1, read_len].map { |x| x != 0 }

      # return value of J register
      ic.mem[ic.relative_base + 1] = should_jump[regs] ? 1 : 0
      ic.mem[ic.relative_base]
    }))
  }

  run_ruby_jumper[:WALK] { |a, _, c, d|
    !a || !c && d
  }

  run_ruby_jumper[:RUN] { |a, b, c, d, _, _, _, h|
    d && (!a || !b || !c && h)
  }
end

# Approach 3:
# Just calculate the score without running the full Intcode or Springscript.

def auto_score(input)
  mem = input.dup

  # The damage is printed out right before a halt.
  # Determine its location.
  damage = exactly_one('damage location', mem.each_cons(3).filter_map { |(a, b, c)|
    b if a == 4 && c == 99
  })

  # Bit patterns tested come soon after the damage.
  base = damage.step.find { |x| mem[x] > 0 }

  damage = 0
  [7, 153].each { |len|
    raise "bad #{mem[base, len + 1]}" if mem[base + len] != 0
    len.times { |i|
      addr = base + i
      bits_i = mem[addr]
      raise "bad #{bits_i} at #{i} of #{len} (#{mem[base, len + 1]})" unless (1..255).cover?(bits_i)
      bits_s = bits_i.to_s(2).rjust(9, ?0)
      damage += bits_s.each_char.with_index(10).sum { |c, i|
        c == ?0 ? addr * bits_i * i : 0
      }
    }

    base += len + 1
    puts damage
  }
end

slow = ARGV.delete('-s')
slower = ARGV.delete('-ss')

input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

if slower
  run_springscript_scripts(input)
elsif slow
  overwrite_springscript_interpreter(input)
else
  auto_score(input)
end
