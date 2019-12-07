class Intcode
  OPS = {
    99 => {type: :halt},
    1 => {type: :binop, op: :+},
    2 => {type: :binop, op: :*},
    3 => {type: :input},
    4 => {type: :output},
    5 => {type: :jump_zero, op: :!=},
    6 => {type: :jump_zero, op: :==},
    7 => {type: :cmp, op: :<},
    8 => {type: :cmp, op: :==},
  }.each_value(&:freeze).freeze

  NUM_PARAMS = {
    halt: 0,
    binop: 3,
    input: 1,
    output: 1,
    jump_zero: 2,
    cmp: 3,
  }.freeze

  # Note that outputs are still counted in params.
  NUM_OUTPUTS = {
    binop: 1,
    cmp: 1,
    input: 1,
  }.freeze

  attr_reader :mem, :pos, :output
  alias :memory :mem

  def initialize(
    mem,
    valid_ops: nil
  )
    @ops = valid_ops ? OPS.slice(*valid_ops).freeze : OPS
    @mem = mem.dup
    @pos = 0
    @halt = false
    @block = false
    @output = []
  end

  def halted?
    @halt
  end

  def step(
    input: -> { raise 'no input' },
    mem_range: nil, mem_start: 0, mem_len: nil, mem_all: false,
    disas: false
  )
    raise "fell off the end at #{@pos}" unless (opcode = @mem[@pos])
    raise "unknown opcode #{opcode} at #{@pos}" unless (op = @ops[opcode % 100])

    num_params = NUM_PARAMS.fetch(op[:type])
    params = @mem[@pos + 1, num_params]
    raise "Not enough params at #{@pos}: #{op} #{params}" if params.compact.size < num_params

    num_outputs = NUM_OUTPUTS[op[:type]] || 0
    num_inputs = num_params - num_outputs

    # This was faster than opcode.digits.drop(2)
    modes = [(opcode / 100) % 10, (opcode / 1000) % 10, (opcode / 10000) % 10]

    jumped_to = nil

    resolved = []
    out_resolved = []

    params.zip(modes).each_with_index { |(param, mode), i|
      if mode != 1 && !(0...@mem.size).cover?(param)
        raise "#{param} out of range at #{pos}: #{op} #{params}"
      end

      if i < num_inputs
        resolved << (mode == 1 ? param : @mem[param])
      else
        # Spec claims we'll never get mode 1, we won't check this.
        # The @mem needs to be indexed into at write site,
        # so just put the address in.
        out_resolved << param
      end
    }

    case op[:type]
    when :binop
      @mem[out_resolved[0]] = resolved[0].send(op[:op], resolved[1])
    when :input
      if (got_input = input[])
        @mem[out_resolved[0]] = got_input
      else
        @block = true
      end
    when :output
      output.concat(resolved)
    when :jump_zero
      jumped_to = resolved[1] if resolved[0].send(op[:op], 0)
    when :cmp
      @mem[out_resolved[0]] = resolved[0].send(op[:op], resolved[1]) ? 1 : 0
    when :halt
      @halt = true
    else raise "unknown type #{op} for opcode #{opcode} at #{@pos}"
    end

    if disas
      s = "@#{@pos} #{opcode} #{params}: #{op} #{resolved}"
      s << " Store #{@mem[out_resolved[0]]} in #{out_resolved[0]}" if num_outputs > 0
      s << " Jump to #{jumped_to}" if jumped_to
      s << " Block for input" if @block
      puts s
    end

    if mem_all
      mem_to_show = @mem
      mem_range = 0...@mem.size
    elsif mem_range
      mem_to_show = @mem[mem_range]
    elsif mem_len
      mem_to_show = @mem[mem_start, mem_len]
      mem_range = mem_start...(mem_start + mem_len)
    end
    if mem_to_show
      before_current = @pos - mem_range.begin
      puts [
        mem_to_show.take(before_current).join(?,),
        self.class.yellow(mem_to_show.drop(before_current).take(1 + num_params).join(?,)),
        mem_to_show.drop(before_current + 1 + num_params).join(?,),
      ].reject(&:empty?).join(?,)
    end

    @pos = jumped_to || @pos + 1 + num_params unless @block

    self
  end

  def continue(**args)
    case args[:input]
    when Integer
      i = [args[:input]]
      args[:input] = -> { i.shift }
    when Array
      i = args[:input]
      unless i.all? { |x| x.is_a?(Integer) }
        raise "Unknown input type #{i}"
      end
      args[:input] = -> { i.shift }
    end
    @block = false
    step(**args) until @halt || @block
    self
  end

  def self.yellow(s)
    "\e[1;33m#{s}\e[0m"
  end
end
