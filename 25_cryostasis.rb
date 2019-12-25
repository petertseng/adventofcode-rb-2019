require_relative 'lib/intcode'

def find_string(mem, str)
  expected_delta = str.chars.each_cons(2).map { |a, b| (b.ord - 1) - a.ord }
  deltas = mem.each_cons(2).map { |a, b| b - a }
  substr_starts = deltas.each_cons(str.size - 1).each_with_index.filter_map { |ds, i|
    i if ds == expected_delta
  }

  first_char = str[0].ord
  substr_starts.flat_map { |start|
    encoded_start = mem[start]
    (0...start).select { |len_addr|
      len = mem[len_addr]
      encoded_start + len + (start - (len_addr + 1)) == first_char
    }
  }
end

def exactly_one(name, things)
  raise "need exactly one #{name}, not #{things}" if things.size != 1
  things[0]
end

def exactly_one_function(functions, mem, name)
  exactly_one('function ' + name, functions.select { |f|
    mem[f].each_cons(4).any? { |x| yield x }
  })
end

def modes(op)
  [(op / 100) % 10, (op / 1000) % 10, (op / 10000) % 10]
end

def infer_answer(mem)
  # The prompt tells us to look for an airlock password,
  # so it stands to reason that the password will be printed alongside the string "airlock".
  airlock_string = exactly_one('airlock string', find_string(mem, 'airlock'))

  functions = Intcode.functions(mem)

  airlock_string_printer = exactly_one_function(functions, mem, 'printing airlock string') { |a, b, c, d|
    # Writes base of airlock string to a location on the stack.
    next unless [1, 2].include?(a % 100)
    m = modes(a)
    m[2] == 2 && d > 0 && [b, c].zip(m).any? { |arg, mode| mode == 1 && arg == airlock_string }
  }

  # The address printed before the airlock string will eventually contain the answer.
  address_used = exactly_one(
    'address printed before airlock',
    mem[airlock_string_printer].each_cons(4).with_index.flat_map { |(a, b, c, d), i|
      next [] unless [1, 2].include?(a % 100)
      m = modes(a)
      next [] unless m[2] == 2 && d > 0
      [b, c].zip(m).filter_map { |arg, mode| arg if mode == 0 }
    },
  )

  # One function writes a constant to this address.
  # (The constant is not the answer, it's just 0,
  # but it signifies that the answer is about to be computed into that address)
  # (Another way to find this is to find the one room that has an on_entry function)
  const_write_to_address = exactly_one_function(functions, mem, 'writing const to password address') { |a, _, _, d|
    [1102, 1101].include?(a) && d == address_used
  }

  # That function multiplies two values to get a target value and stores the target value.
  target_loc, target = exactly_one(
    'target',
    mem[const_write_to_address].each_cons(4).filter_map { |a, b, c, d|
      [d, mem[b] * mem[c]] if a == 2 && [b, c, d].all? { |x| x > 0 && mem[x] }
    }
  )

  # Find a function that compares against the target value.
  comparer = exactly_one_function(functions, mem, 'comparing against target') { |op, *operands|
    [7, 8].include?(op % 100) && operands.zip(modes(op)).include?([target_loc, 0])
  }

  # That function uses elements of an array in the comparison.
  weight_base_addr = exactly_one(
    'weight array base address',
    mem[comparer].each_cons(8).with_index(comparer.begin).flat_map { |insts, i|
      # We're looking for two instructions of this pattern:
      # write S11 S12 D1
      # write S21 S22 D2
      op1, src1, src2, dst1, op2 = insts
      next [] unless [op1, op2].all? { |op| [1, 2].include?(op % 100) }

      # second instruction must be an an array read (D1 must point to S21 or S22)
      next [] if op1 >= 20000
      next [] unless [i + 5, i + 6].include?(dst1)

      # Anything that looks like a base address offset
      [src1, src2].zip(modes(op1)).filter_map { |v, mode| v if v > 0 && mode == 1 }
    },
  )

  # Find the length of the array, as follows:
  array_len = exactly_one('weight array length', mem.each_cons(8).flat_map { |insts|
    # Find an instruction that stores the address of the function.
    op1, src11, src12, _, op2, src21, src22 = insts
    next [] unless [op1, op2].all? { |op| [1, 2].include?(op % 100) }
    next [] unless [src21, src22].zip(modes(op2)).include?([comparer.begin, 1])
    # The array length is stored right before the address of the function.
    [src11, src12].zip(modes(op1)).filter_map { |v, mode| v if v > 1 && mode == 1 }
  })

  mem[weight_base_addr, array_len].map { |x| x < target ? 0 : 1 }.join.to_i(2)
end

def string_at(mem, i)
  len = mem[i]
  mem[i + 1, len].map.with_index { |c, j| (c + len + j).chr }.join
end

def strings(mem)
  mem.each_with_index.filter_map { |len, i|
    next if len <= 0
    next unless mem[i + 1 + len]
    potential_string = len.times.map { |j|
      mem[i + 1 + j] + j + len
    }
    next unless potential_string.all? { |c| c == 10 || (32..127).cover?(c) }
    {
      start: i,
      len: len,
      s: potential_string.pack('c*').freeze,
    }.freeze
  }
end

def items(mem)
  mem[4601, 13 * 4].each_slice(4).map.with_index { |(a, b, c, d), i|
    {
      loc_id: a,
      loc_name: a == -1 ? 'Inventory' : string_at(mem, a + 7),
      name: string_at(mem, b),
      weight: c - 27 - i,
      on_pickup: d == 0 ? nil : d,
    }.freeze
  }
end

def fmt_items(mem)
  items(mem).map { |item|
    "%-20<name>s %10<weight>d in %-24<loc_name>s#{" #{item[:on_pickup]} on pickup" if item[:on_pickup]}" % item
  }
end

def room_at(input, i)
  {
    id: i,
    name_addr: name_addr = input[i],
    text_addr: text_addr = input[i + 1],
    on_entry: input[i + 2] == 0 ? nil : input[i + 2],
    neighbours: %i(north east south west).zip(input[i + 3, 4]).to_h.select { |_, v| v > 0 },
    name: string_at(input, name_addr).freeze,
    text: string_at(input, text_addr).freeze,
  }.freeze
end

def path_to(rooms, to, from, seen = {})
  return [] if to == from
  new_seen = seen.merge(from => true)

  rooms[from][:neighbours].each { |ndir, nid|
    next if seen[nid]
    if (sub_path_to = path_to(rooms, to, nid, new_seen))
      return [ndir] + sub_path_to
    end
  }
  nil
end

def rooms(mem)
  room_queue = [[mem[3], mem[4]].max]
  rooms = {}
  while (room_addr = room_queue.shift)
    next if rooms[room_addr]
    rooms[room_addr] = room = room_at(mem, room_addr)
    room_queue.concat(room[:neighbours].values)
  end
  rooms
end

def fmt_rooms(mem, current: nil, text: false)
  items = items(mem).group_by { |i| i[:loc_id] }
  rooms = rooms(mem)

  rooms.values.map { |r|
    parts = ["\e[1;32m#{r[:name]}\e[0m"]
    parts << "\e[1;35mYou are here\e[0m" if r[:id] == current&.[](:id)
    parts.concat((items[r[:id]] || []).map { |item|
      "\e[1;#{item[:on_pickup] ? 31 : 34}m#{item[:name]}\e[0m"
    })
    parts.concat(r[:neighbours].filter_map { |ndir, nid|
      "\e[1;33m#{ndir.to_s[0].upcase} = #{rooms[nid][:name]}\e[0m"
    })
    parts << "route #{path_to(rooms, r[:id], current[:id]).map { |dir| dir.to_s[0].upcase }.join}" if current
    parts << r[:text] if text
    parts.join(' - ')
  }
end

def brute_force(ic, items, dir, prefix)
  include_items = []
  exclude_items = []

  unknown_items = -> { items - include_items - exclude_items }

  status = -> {
    prefix + ' ' + [
      ['include', include_items],
      ['exclude', exclude_items],
      ['unknown', unknown_items[]],
    ].map { |name, items|
      "#{name}: \e[1m#{items.map { |item| item[:name] }.join(', ')}\e[0m (#{items.sum { |item| item[:weight] }})"
    }.join(' - ')
  }

  items.size.times {
    unknown_items[].each { |item|
      case attempt_pressure(ic, ["drop #{item[:name]}", dir, "take #{item[:name]}"])
      when :ok
        exclude_items << item
        include_items.concat(unknown_items[])
        puts status[]
        return
      when :too_light
        puts "#{prefix} too light without #{item[:name]} (#{item[:weight]}) - include it."
        include_items << item
      end
    }

    ic.continue(input: unknown_items[].map { |item| "drop #{item[:name]}" })

    unknown_items[].each { |item|
      case attempt_pressure(ic, ["take #{item[:name]}", dir, "drop #{item[:name]}"])
      when :ok
        include_items << item
        exclude_items.concat(unknown_items[])
        puts status[]
        return
      when :too_heavy
        puts "#{prefix} too heavy with #{item[:name]} (#{item[:weight]}) - exclude it."
        exclude_items << item
      end
    }

    ic.continue(input: unknown_items[].map { |item| "take #{item[:name]}" })
  }

  puts status[]

  # Our inventory should have just the items we need now, so let's just try to move in.
  ic.output.clear
  ic.continue(input: dir)
  # Let the main loop print out the output.
end

def attempt_pressure(ic, cmd)
  ic.continue(input: cmd)
  output = ic.ascii_output

  status = if output.include?('lighter')
    :too_heavy
  elsif output.include?('heavier')
    :too_light
  elsif output.include?('proceed')
    :ok
  else
    raise "Unknown output #{output}"
  end

  ic.output.clear if status != :ok

  status
end

show_strings = ARGV.delete('-s')
show_items = ARGV.delete('-i')
show_rooms = ARGV.delete('-r')
manual = ARGV.delete('-m')
input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

strings(input).each { |s| puts "@#{s[:start]} (#{s[:len]}): #{s[:s]}" } if show_strings

puts fmt_rooms(input, text: true) if show_rooms
puts fmt_items(input) if show_items

unless manual
  p infer_answer(input)
  Kernel.exit(0)
end

ic = Intcode.new(input).continue(input: [])

rooms = rooms(ic.mem).freeze
rooms_by_name = rooms.values.to_h { |r| [r[:name], r] }.freeze

prefix = '!!!'.freeze

saves = {}
current_loc = nil
prev_output = nil

loop {
  unless ic.output.empty?
    prev_output = ic.ascii_output
    puts prev_output
    ic.output.clear

    if prev_output =~ /== ([A-Za-z ]+) ==/ && current_loc&.[](:name) != $1
      current_loc = rooms_by_name[$1]
      saves['auto'] = {ic: ic.dup, output: prev_output, loc: current_loc}
    end
  end

  s = STDIN.gets
  break if s.nil?

  fast_travel = ->(target, purpose = '') {
    moves = path_to(rooms, target[:id], current_loc[:id])
    puts "#{prefix} Using \e[1;33m#{moves}\e[0m to fast travel to \e[1;32m#{target[:name]}\e[0m #{purpose}"

    # Discard output from all but last
    last_move = moves.pop
    ic.continue(input: moves.map(&:to_s))
    ic.output.clear
    ic.continue(input: last_move.to_s)

    current_loc = target
  }

  if s.start_with?('sa')
    name = s.split[1] || 'unnamed'
    saves[name] = {ic: ic.dup, output: prev_output, loc: current_loc}
    puts "#{prefix} Saved #{name}"
  elsif s.start_with?(?l)
    name = s.split[1] || 'unnamed'
    if (save = saves[name])
      puts "#{prefix} Loading #{name}"
      ic = save[:ic].dup
      current_loc = save[:loc]
      puts save[:output]
    else
      puts "#{prefix} There is no save named #{name}. Try one of: #{saves.keys}"
    end
  elsif s.start_with?(?i) && s.chomp != 'inv'
    puts fmt_items(ic.mem)
  elsif s.start_with?(?r)
    puts fmt_rooms(ic.mem, current: current_loc)
  elsif s.start_with?('ft')
    unless (query = s.split[1])
      puts "#{prefix} Need a target to fast travel to"
      next
    end

    # Hmm, first try substring matching.
    targets = rooms.values.select { |r| r[:name].downcase.include?(query.downcase) }

    # That didn't work, guess let's try regex... (subsequence matching)
    if targets.size != 1
      regex = query.downcase.chars.join('.*')
      targets = rooms.values.select { |r| r[:name].downcase.match?(regex) }
    end

    if targets.size == 0
      puts "#{prefix} No matching rooms for #{query}"
    elsif targets.size > 1
      puts "#{prefix} Too many matches: #{targets.map { |r| r[:name] }}, disambiguate"
    else
      fast_travel[targets[0]]
    end
  elsif s.chomp == 'ta' || s.start_with?('takea') || s.start_with?('take all')
    # So, I could use BFS to find the shortest path that takes all items and ends at the checkpoint...
    # but I don't feel like it.
    pickup = 0
    already_in = 0
    skip = 0
    items(ic.mem).each { |item|
      if item[:loc_id] == -1
        puts "#{prefix} \e[1;32m#{item[:name]}\e[0m is already in the inventory"
        already_in += 1
        next
      end
      if item[:on_pickup]
        puts "#{prefix} \e[1;31m#{item[:name]}\e[0m executes a function on pick-up, skipping."
        skip += 1
        next
      end

      pickup += 1
      fast_travel[rooms[item[:loc_id]], "to pick up \e[1;34m#{item[:name]}\e[0m"]
      ic.continue(input: "take #{item[:name]}")
    }
    ic.output.clear
    puts "#{prefix} Picked up #{pickup} items, now have #{already_in + pickup} in inventory. Skipped #{skip} items that execute functions."
  elsif s.start_with?('b')
    final_room = exactly_one('room executing function on entry', rooms.values.select { |r| r[:on_entry] })
    penultimate_room = exactly_one('room leading to final room', rooms.values.select { |r|
      r[:neighbours].has_value?(final_room[:id])
    })
    fast_travel[penultimate_room] unless current_loc == penultimate_room

    dir = exactly_one(
      'direction to final room',
      path_to(rooms, final_room[:id], penultimate_room[:id]),
    ).to_s
    items = items(ic.mem).select { |item| item[:loc_id] == -1 }
    brute_force(ic, items, dir, prefix)
  else
    autosave = ic.dup

    ic.continue(input: s)

    if ic.halted?
      puts ic.ascii_output
      puts "#{prefix} Halted. Rolling back."
      ic = autosave.dup
      puts prev_output
    end
  end
}
