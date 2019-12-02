class Intcode
  OPS = {
    99 => {type: :halt},
    1 => {type: :binop, op: :+},
    2 => {type: :binop, op: :*},
  }.each_value(&:freeze).freeze

  NUM_PARAMS = {
    halt: 0,
    binop: 3,
  }.freeze

  # Note that outputs are still counted in params.
  NUM_OUTPUTS = {
    binop: 1,
  }.freeze

  attr_reader :mem, :pos
  alias :memory :mem

  def initialize(
    mem,
    valid_ops: nil
  )
    @ops = valid_ops ? OPS.slice(*valid_ops).freeze : OPS
    @mem = mem.dup
    @pos = 0
    @halt = false
  end

  def step(
    mem_range: nil, mem_start: 0, mem_len: nil, mem_all: false,
    disas: false
  )
    raise "fell off the end at #{@pos}" unless (opcode = @mem[@pos])
    raise "unknown opcode #{opcode} at #{@pos}" unless (op = @ops[opcode])

    num_params = NUM_PARAMS.fetch(op[:type])
    params = @mem[@pos + 1, num_params]
    raise "Not enough params at #{@pos}: #{op} #{params}" if params.compact.size < num_params

    num_outputs = NUM_OUTPUTS[op[:type]] || 0
    num_inputs = num_params - num_outputs

    resolved = []
    out_resolved = []

    params.each_with_index { |param, i|
      if !(0...@mem.size).cover?(param)
        raise "#{param} out of range at #{pos}: #{op} #{params}"
      end

      if i < num_inputs
        resolved << @mem[param]
      else
        # The @mem needs to be indexed into at write site,
        # so just put the address in.
        out_resolved << param
      end
    }

    case op[:type]
    when :binop
      @mem[out_resolved[0]] = resolved[0].send(op[:op], resolved[1])
    when :halt
      @halt = true
    else raise "unknown type #{op} for opcode #{opcode} at #{@pos}"
    end

    if disas
      s = "@#{@pos} #{opcode} #{params}: #{op} #{resolved}"
      s << " Store #{@mem[out_resolved[0]]} in #{out_resolved[0]}" if num_outputs > 0
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

    @pos += 1 + num_params

    self
  end

  def continue(*args)
    step(*args) until @halt
    self
  end

  def self.yellow(s)
    "\e[1;33m#{s}\e[0m"
  end
end
