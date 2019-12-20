class Intcode
  OPS = {
    99 => {type: :halt},
    1 => {type: :binop, op: :+},
    2 => {type: :binop, op: :*},
    3 => {type: :input},
    4 => {type: :output},
    5 => {type: :jump_zero, op: :!=},
    6 => {type: :jump_zero, op: :==},
    7 => {type: :cmp, op: :<, opposite: :>=},
    8 => {type: :cmp, op: :==, opposite: :!=},
    9 => {type: :adjust_rel_base},
  }.each_value(&:freeze).freeze

  NUM_PARAMS = {
    halt: 0,
    binop: 3,
    input: 1,
    output: 1,
    jump_zero: 2,
    cmp: 3,
    adjust_rel_base: 1,
  }.freeze

  # Note that outputs are still counted in params.
  NUM_OUTPUTS = {
    binop: 1,
    cmp: 1,
    input: 1,
  }.freeze

  attr_reader :mem, :pos, :output
  alias :memory :mem
  attr_reader :times_run, :jumps_taken

  def initialize(
    mem,
    funlog: false, funopt: false,
    sparse: false,
    valid_ops: nil
  )
    @ops = valid_ops ? OPS.slice(*valid_ops).freeze : OPS
    @sparse = sparse
    @mem = sparse ? mem.each_with_index.to_h { |x, i| [i, x] }.tap { |h| h.default = 0 } : mem.dup
    @pos = 0
    @relative_base = 0
    @halt = false
    @block = false
    @output = []

    @relative_writes = []
    @funopt = funopt
    @funlog = funlog
    @funopt_or_log = funopt || funlog
    # cached_funcalls[function_address][args] = result
    @cached_funcalls = Hash.new { |h, k| h[k] = {} }
    # inflight_funcalls[rb_when_called] = {args: [1, 2, 3], function: 123, nret: 1}
    @inflight_funcalls = {}

    @times_run = Hash.new(0)
    @jumps_taken = Hash.new(0)
  end

  def halted?
    @halt
  end

  def step(
    input: -> { raise 'no input' },
    stats: false,
    mem_range: nil, mem_start: 0, mem_len: nil, mem_all: false,
    disas: false
  )
    raise "fell off the end at #{@pos}" unless (opcode = @mem[@pos])
    raise "unknown opcode #{opcode} at #{@pos}" unless (op = @ops[opcode % 100])

    num_params = NUM_PARAMS.fetch(op[:type])
    params = @sparse ? num_params.times.map { |x| @mem[pos + 1 + x] } : mem[@pos + 1, num_params]
    if params.compact.size < num_params
      # Doesn't happen yet as of day 09, but will prepare.
      # Also, should only happen in non-sparse mode since sparse has default 0
      missing_params = num_params - params.size
      params.concat([0] * missing_params)
      # I won't bother adding @mem, either this is a branch back to 0,
      # or we're going to execute an instruction 0 soon.
    end

    num_outputs = NUM_OUTPUTS[op[:type]] || 0
    num_inputs = num_params - num_outputs

    # This was faster than opcode.digits.drop(2)
    modes = [(opcode / 100) % 10, (opcode / 1000) % 10, (opcode / 10000) % 10]

    jumped_to = nil

    resolved = []
    out_resolved = []

    params.zip(modes).each_with_index { |(param, mode), i|
      param += @relative_base if mode == 2

      if mode != 1 && param < 0
        raise "#{param} out of range at #{pos}: #{op} #{params}"
      end

      if i < num_inputs
        resolved << (mode == 1 ? param : (@mem[param] || 0))
      else
        # Spec claims we'll never get mode 1, we won't check this.
        # The @mem needs to be indexed into at write site,
        # so just put the address in.
        out_resolved << param
        if @funopt_or_log
          if mode == 2
            @relative_writes.unshift(param - @relative_base)
          else
            @relative_writes.unshift(nil)
          end
          @relative_writes.pop if @relative_writes.size > 2
        end
      end
    }

    case op[:type]
    when :binop
      result = resolved[0].send(op[:op], resolved[1])
      @mem[out_resolved[0]] = result
      just_stored_ret_addr = result > 0 && result == @pos + 7
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

      # Try to cache results of function calls.
      if jumped_to && @funopt_or_log
        if jumped_to == @mem[@relative_base] && (inflight = @inflight_funcalls.delete(@relative_base))
          # RET
          returned = @mem[@relative_base + 1, inflight[:nret]].freeze
          puts "f#{inflight[:function]}(#{inflight[:args]}) = #{returned}" if @funlog
          @cached_funcalls[inflight[:function]][inflight[:args]] = returned if @funopt
        elsif @prev_stored_ret_addr
          # CALL
          num_args = @relative_writes[0] == 0 && @relative_writes[1]&.>(0) ? @relative_writes[1] : 0

          args = @mem[@relative_base + 1, num_args].freeze
          if (cached_result = @cached_funcalls[jumped_to][args])
            # funcall w/ args we seen before
            # insert cached result and immediately return.
            @mem[@relative_base + 1, cached_result.size] = cached_result
            jumped_to = @mem[@relative_base]
          else
            # new funcall w/ args we haven't seen before
            # do it and mark as in flight
            # Hmm, assuming all functions return only 1 value???
            @inflight_funcalls[@relative_base] = {args: args, function: jumped_to, nret: 1}.freeze
          end
        end
      end
    when :cmp
      @mem[out_resolved[0]] = resolved[0].send(op[:op], resolved[1]) ? 1 : 0
    when :halt
      @halt = true
    when :adjust_rel_base
      @relative_base += resolved[0]
    else raise "unknown type #{op} for opcode #{opcode} at #{@pos}"
    end

    if stats
      @times_run[@pos] += 1
      natural_destination = @pos + 1 + num_params
      @jumps_taken[[@pos, jumped_to]] += 1 if jumped_to && jumped_to != natural_destination
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

    @prev_stored_ret_addr = just_stored_ret_addr

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

  def self.disas(mem, addrs_run: nil)
    return disas(mem.mem, addrs_run: mem.times_run) if mem.is_a?(self)

    mem = mem.dup

    pos = 0
    disas = []
    prev_assign = {target: nil}
    prev_stored_ret_addr = false

    while (opcode = mem[pos])
      if addrs_run && !addrs_run.has_key?(pos) || !(op = OPS[opcode % 100])
        start = pos
        # Not an op, so assume it's data. Collect data.
        # Gets confused if there's a valid opcode lying in the data.
        # Perhaps need to analyse actual jump targets in code?
        pos += 1 until pos >= mem.size || (!addrs_run || addrs_run.has_key?(pos)) && possible_opcode?(mem[pos] || 0)
        disas << {start: start, end: pos - 1, s: 'DATA', ints: mem[start...pos]}
        next
      end

      num_params = NUM_PARAMS.fetch(op[:type])
      modes = [(opcode / 100) % 10, (opcode / 1000) % 10, (opcode / 10000) % 10]
      params = mem[pos + 1, num_params]
      params << 0 until params.size >= num_params
      fmt_params = params.zip(modes).map { |pm| fmt_param(*pm) }

      s = case (t = op[:type])
      when :binop, :cmp
        if t == :cmp
          just_assigned = {
            target: fmt_params[2],
            s_true: "#{fmt_params[0]} #{op[:op]} #{fmt_params[1]}",
            s_false: "#{fmt_params[0]} #{op[:opposite]} #{fmt_params[1]}",
          }
        end

        if fmt_params[0].is_a?(Integer) && fmt_params[1].is_a?(Integer)
          result = fmt_params[0].send(op[:op], fmt_params[1])
          just_stored_ret_addr = result > 0 && result == pos + 7
        elsif op[:op] == :* && fmt_params.include?(1)
          result = "#{fmt_params.find { |x| x != 1 }}"
        elsif op[:op] == :+ && fmt_params.include?(0)
          result = "#{fmt_params.find { |x| x != 0 }}"
        else
          result = "#{fmt_params[0]} #{op[:op]} #{fmt_params[1]}"
        end

        "#{fmt_params[2]} <- #{result}"
      when :input
        "#{fmt_params[0]} <- input"
      when :output
        "output #{fmt_params[0]}"
      when :jump_zero
        if prev_assign&.[](:target) &.== fmt_params[0]
          # != 0 means true
          "goto #{fmt_params[1]} if #{prev_assign[op[:op] == :!= ? :s_true : :s_false]}"
        elsif fmt_params[0].is_a?(Integer)
          if fmt_params[0].send(op[:op], 0)
            "goto #{fmt_params[1]}#{' CALL' if prev_stored_ret_addr}#{' RET' if fmt_params[1] == fmt_param(0, 2)}"
          else
            'nop'
          end
        else
          "goto #{fmt_params[1]} if #{fmt_params[0]} #{op[:op]} 0"
        end
      when :halt
        'HALT'
      when :adjust_rel_base
        "$rb += #{fmt_params[0]}"
      else raise "unknown type #{op} for opcode #{opcode} at #{pos}"
      end

      disas << {start: pos, end: pos + num_params, s: s, ints: mem[pos, 1 + num_params]}
      pos += 1 + num_params
      prev_assign = just_assigned
      prev_stored_ret_addr = just_stored_ret_addr
      just_assigned = nil
      just_stored_ret_addr = nil
    end

    addr_len = (mem.size - 1).to_s.size
    s_len = disas.map { |x| x[:s].to_s.size }.max
    ints_len = disas.reject { |x| x[:s] == 'DATA' }.map { |x| x[:ints].to_s.size }.max

    disas.each { |d|
      fmt = "%#{addr_len}d %#{addr_len}d %-#{s_len}s %-#{ints_len}s"
      dat = [
        d[:start],
        d[:end],
        d[:s],
        d[:ints],
      ]
      puts (fmt % dat).rstrip
    }
  end

  def self.fmt_param(param, mode)
    case mode
    when 0; "%#{param}"
    when 1; Integer(param)
    when 2; "$rb[#{param}]"
    else raise "Invalid mode #{mode}"
    end
  end

  def self.possible_opcode?(opcode)
    return false unless (op = OPS[opcode % 100])
    modes = opcode.digits.drop(2)
    return false if modes.size > NUM_PARAMS[op[:type]]
    modes << 0 until modes.size == NUM_PARAMS[op[:type]]
    num_outputs = NUM_OUTPUTS[op[:type]] || 0
    modes.all? { |x| (0..2).cover?(x) } && modes.last(num_outputs).all? { |x| x != 1 }
  end

  def self.yellow(s)
    "\e[1;33m#{s}\e[0m"
  end
end
