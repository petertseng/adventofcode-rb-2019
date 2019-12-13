require_relative 'lib/intcode'

def affine(mem)
  score_func = Intcode.functions(mem)[-1]
  nums = mem[score_func].each_cons(4).filter_map { |op, a1, a2, d|
    next if op != 21101 && op != 21102
    [d, op == 21101 ? a1 + a2 : a1 * a2]
  }.to_h

  a = nums[2]
  b = nums[3]
  m = nums[4]

  game_grid = mem[score_func.end + 3, m]
  non_one = game_grid.index { |x| x != 1 }
  width = non_one - 1
  height = m / width
  blocks = game_grid.each_with_index.filter_map { |x, i|
    next if x != 2
    i.divmod(width)
  }

  scores = mem[score_func.end + 3 + m, m]
  score = blocks.sum { |y, x|
    scores[((x * height + y) * a + b) % m]
  }

  [blocks.size, score]
end

def hijack(ic, blocks)
  mem = ic.memory
  # where is the function that is called when a block is broken?
  block_broken = Intcode.functions(mem).select { |f|
    mem[f].each_cons(5).include?([104, -1, 104, 0, 4])
  }
  raise "need exactly one block_broken not #{block_broken}" if block_broken.size != 1
  block_broken = block_broken[0].begin

  # Set return addr to current pos (where we're pausing for input)
  # so it pauses for input after having called the function
  mem[ic.relative_base] = ic.pos

  blocks.each { |y, x|
    # call block_broken(x, y)
    mem[ic.relative_base + 1] = x
    mem[ic.relative_base + 2] = y
    ic.continue(hijack: block_broken, input: [])
    yield ic.output
  }
end

slow = ARGV.delete('-s')
slower = ARGV.delete('-ss')
input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer))
input[0] = 2
input.freeze

ballx = nil
paddlex = nil
blocks = {}
score = 0

parse_output = ->output {
  while output.size >= 3
    x, y, tile = output.shift(3)

    if x == -1 && y == 0
      score = tile
      next
    end

    # ordered by frequency, though I'm not sure this matters.
    case tile
    when 0; blocks.delete([y, x])
    when 4; ballx = x
    when 3; paddlex = x
    when 2; blocks[[y, x].freeze] = true
    when 1; # nothing
    else raise "Unknown tile #{tile}"
    end
  end
}

init_game = -> {
  Intcode.new(input).continue(input: []).tap { |ic|
    parse_output[ic.output]
  }
}

if slower
  ic = init_game[]
  puts blocks.size
  until blocks.empty?
    # ballx > paddlex: 1; ballx < paddlex: -1
    ic.continue(input: ballx <=> paddlex)
    parse_output[ic.output]
  end

  puts score
elsif slow
  ic = init_game[]
  puts blocks.size
  hijack(ic, blocks.keys, &parse_output)
  puts score
else
  puts affine(input)
end
