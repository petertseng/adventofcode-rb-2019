require_relative 'lib/intcode'

# vars prefixed with an underscore are not used by this implementation,
# but may be used as temporaries by the Intcode implementation.
Computer = Struct.new(:sent, :tmp1, :_tmp2, :_tmp3, :_y, :slot_divisor, :rx_slots, :rx_base, :tx_f_addr, :_to_send, :num_txs, :tx_base) {
  attr_reader :id

  def initialize(mem, *args)
    super(*args)
    @id = tmp1
    @rxs = mem[rx_base, rx_slots * 2].each_slice(2).map { |present, val|
      present == 1 ? val : present == 0 ? nil : (raise "unknown present #{present} #{val}")
    }
    @txs = mem[tx_base, num_txs * 2].each_slice(2).to_a
    self.sent = sent == 1 ? true : sent == 0 ? false : (raise "unknown sent #{sent}")
    # NB: None of these tx_f actually use their tx_arg
    case tx_f_addr
    when 253
      @tx_f_name = :add_rxs
      @tx_f = ->_ { @rxs.sum }
    when 302
      @tx_f_name = :multiply_rxs
      @tx_f = ->_ { @rxs.reduce(1, :*) }
    when 351
      @tx_f_name = :divide_rxs
      @tx_f = ->_ { @rxs[0] / @rxs[1] }
    when 556
      @tx_f_name = :first_rx
      @tx_f = ->_ { @rxs[0] }
    else raise "unknown tx_f #{tx_f}"
    end
  end

  def to_s
    "slot_divisor #{slot_divisor}, rxs #@rxs, tx_f #@tx_f_name, txs #@txs"
  end

  def no_packet
    sent ? [] : send_packets
  end

  def receive_packet(x, y)
    rx_slot = x / slot_divisor - 1
    return [] unless (0...rx_slots).cover?(rx_slot)
    return [] if @rxs[rx_slot] == y
    @rxs[rx_slot] = y
    send_packets
  end

  def send_packets
    self.sent = true
    return [] if @rxs.include?(nil)
    # The actual computers do call it with 210 (same across inputs), but it's never used.
    y = @tx_f[210]
    @txs.map { |addr, x| [addr, x, y] }
  end
}

def run_nics(nics, verbose: false)
  qs = nics.map { [] }.freeze

  nat = nil
  last_y_sent_by_nat = nil

  0.step { |t|
    nics.zip(qs).each_with_index { |(nic, q), i|
      rx = q.size
      tx = []

      (yield nic, q.shift(rx)).each { |addr, x, y|
        tx << [addr, x, y]
        if addr == 255
          puts y if nat.nil?
          nat = [x, y].freeze
        else
          qs[addr] << [x, y].freeze
        end
      }

      puts "time #{t}: #{i} receives #{rx} and sends #{tx.size} #{tx}" if verbose && (rx != 0 || tx.size != 0)
    }

    if qs.all?(&:empty?)
      if nat[1] == last_y_sent_by_nat
        puts nat[1]
        exit 0
      end
      last_y_sent_by_nat = nat[1]
      qs[0] << nat.dup.freeze
    end
  }
end

verbose = ARGV.delete('-v')
slow = ARGV.delete('-s')

input = (ARGV[0]&.include?(?,) ? ARGV[0] : ARGF.read).split(?,).map(&method(:Integer)).freeze

nics = (0..49).map { |x| Intcode.new(input).continue(input: x) }

if slow
  run_nics(nics, verbose: verbose) { |nic, q|
    nic.continue(input: q.empty? ? -1 : q.flatten)
    nic.output.shift(nic.output.size / 3 * 3).each_slice(3)
  }
else
  run_nics(nics.map { |nic| Computer.new(nic.mem, *nic.mem[61..72]) }, verbose: verbose) { |nic, q|
    q.empty? ? nic.no_packet : q.flat_map { |pkt| nic.receive_packet(*pkt) }
  }
end
