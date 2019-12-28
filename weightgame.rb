def half_bits(n)
  raise "sorry must be even" if n % 2 != 0
  # Information not known to the player:
  # The eight items each weigh a power of two,
  # and the answer is four items.

  (0...(1 << n)).select { |x| x.to_s(2).count(?1) == n / 2 }
end

def powerset(n)
  (0...(1 << n)).to_a
end

def play_game(limit, answer, guesser)
  guesses = []

  limit.times { |x|
    guess = guesser.guess
    if guess == answer
      guesses << [guess, :ok].freeze
      return {
        guesses: guesses,
        num_guesses: x + 1,
      }
    end
    if guess < answer
      guesser[guess] = :too_light
      guesses << [guess, :too_light].freeze
    else
      guesser[guess] = :too_heavy
      guesses << [guess, :too_heavy].freeze
    end
  }
  {
    guesses: guesses,
    num_guesses: nil,
  }
end

def rate_guesser(n, answers, new_guesser, verbose: false)
  t = Time.now
  results = {
    failed: 0,
    guessed: 0,
    total: 0,
    minimum: Float::INFINITY,
    maximum: 0,
  }
  answers[n].each { |ans|
    result = play_game(1 << n, ans, new_guesser[n, verbose: verbose])

    p result[:guesses].map { |guess, result|
      [guess.to_s(2).rjust(n, ?0), result]
    } if false #|| true

    if (guesses = result[:num_guesses])
      results[:guessed] += 1
      results[:total] += guesses
      results[:minimum] = [results[:minimum], guesses].min
      results[:maximum] = [results[:maximum], guesses].max
    else
      results[:failed] += 1
    end
  }
  results.merge(average: results[:total].fdiv(results[:guessed]), time: Time.now - t)
end

class Seq
  attr_reader :guess
  def initialize(*_)
    @guess = 0
  end
  def []=(_, _)
    @guess += 1
  end
end

class IncludeExclude
  def initialize(n, initial_state, verbose: false)
    raise "bad state #{initial_state}" unless %i(include exclude).include?(initial_state)
    @n = n
    @state = initial_state
    @must_include = 0
    @must_exclude = 0
    @unknown = n.times.map { |x| 1 << x }
    @guesses = @unknown.dup
    @verbose = verbose
  end

  def guess
    return @must_include if @guesses.empty?

    if @state == :include
      # See if we must include an item - guess all items except this one and any must-not-haves,
      # and see if it's too light.
      ((1 << @n) - 1) ^ @must_exclude ^ @guesses[0]
    elsif @state == :exclude
      # See if we must exclude an item - guess must-have items plus this one,
      # and see if it's too heavy.
      @must_include | @guesses[0]
    else
      raise "Unknown state #{@state}"
    end
  end

  def []=(guess, feedback)
    b = ->x { x.to_s(2).rjust(@n, ?0) }
    puts "got #{feedback} for #{b[guess]} which was derived from #{b[@guesses[0]]}" if @verbose

    if @state == :include && feedback == :too_light
      @must_include |= @guesses[0]
      @unknown.delete(@guesses[0])
    elsif @state == :exclude && feedback == :too_heavy
      @must_exclude |= @guesses[0]
      @unknown.delete(@guesses[0])
    end
    @guesses.shift
    return unless @guesses.empty?

    @state = @state == :include ? :exclude : :include
    @guesses = @unknown.dup
    puts "include #{b[@must_include]}, exclude #{b[@must_exclude]}, unknown #{@unknown.map(&b).join(', ')}" if @verbose
  end
end

class IncludeThenExclude < IncludeExclude
  def initialize(n, **kwargs)
    super(n, :include, **kwargs)
  end
end

class ExcludeThenInclude < IncludeExclude
  def initialize(n, **kwargs)
    super(n, :exclude, **kwargs)
  end
end

class Possibilities
  def initialize(n, verbose: false)
    @n = n
    @possible = (0...(1 << n)).to_a
    @guesses = (0...(1 << n)).to_h { |x| [x, nil] }
    @verbose = verbose
  end

  def []=(guess, feedback)
    if feedback == :too_light
      @possible.reject! { |candidate| candidate & guess == candidate }
    elsif feedback == :too_heavy
      @possible.reject! { |candidate| candidate & guess == guess }
    else
      raise "unknown feedback #{feedback}"
    end
    puts "got #{feedback} for #{guess}, now #{@possible.size} left" if @verbose
  end
end

class MinEntropy < Possibilities
  def guess
    return @possible[0] if @possible.size == 1

    @guesses.keys.min_by { |guess|
      eq = 0
      subset_of_guess = 0
      superset_of_guess = 0
      neither = 0
      @possible.each { |candidate|
        if candidate == guess
          eq += 1
        elsif candidate & guess == candidate
          subset_of_guess += 1
        elsif candidate & guess == guess
          superset_of_guess += 1
        else
          neither += 1
        end
      }

      # Day 25 guesser doesn't know object weights, so using comparisons isn't fair.
      #n_too_light = @possible.count { |candidate| candidate > guess }
      #n_too_heavy = @possible.count { |candidate| candidate < guess }

      # careful here,
      # *result* will be "too heavy" if guess is superset of real answer (real answer is subset of guess),
      # "too light" if guess is subset of real answer (real answer is superset of guess).
      #
      # No real way to tell for the others so just call them equally likely.
      # I'd add Rational(neither, 2) to each, but I'll just multiply through by 2 to avoid Rationals (faster).
      n_too_light = 2 * superset_of_guess + neither
      n_too_heavy = 2 * subset_of_guess + neither

      # If this is too light, any subset is also too light.
      # If this is too heavy, any superset is also too heavy.
      # eq contributes 1 if guess is possible, else 0, but remember we're multiplying by 2 to avoid halves.
      2 * eq + n_too_light * (@possible.size - subset_of_guess) + n_too_heavy * (@possible.size - superset_of_guess)
    }.tap { |g| @guesses.delete(g) }
  end
end

class MinEntropyNoTrivial < MinEntropy
  def initialize(n, **kwargs)
    super
    @possible.delete(0)
    @possible.delete((1 << n) - 1)
  end
end

class MinEntropyHalf < MinEntropy
  def initialize(n, **kwargs)
    super
    if n.even?
      @possible.select! { |x| x.digits(2).count(1) == n / 2 }
    else
      want = [n / 2, (n + 1) / 2]
      @possible.select! { |x| want.include?(x.digits(2).count(1)) }
    end
  end
end

# Restricting to only guess possible ones makes things worse;
# sometimes you have to guess one that you know is not possible.
class MinEntropyHalfGuessPossible < MinEntropyHalf
  def initialize(n, **kwargs)
    super
    @guesses = @possible.to_h { |x| [x, nil] }
  end
end

class MinEntropyCheater < Possibilities
  def guess
    return @possible[0] if @possible.size == 1

    (0...(1 << @n)).min_by { |guess|
      eq = 0
      subset_of_guess = 0
      superset_of_guess = 0
      greater_than_guess = 0
      less_than_guess = 0
      neither = 0
      @possible.each { |candidate|
        if candidate == guess
          eq += 1
        else
          if candidate & guess == candidate
            subset_of_guess += 1
          elsif candidate & guess == guess
            superset_of_guess += 1
          else
            neither += 1
          end
          if candidate > guess
            greater_than_guess += 1
          else
            less_than_guess += 1
          end
        end
      }

      eq + greater_than_guess * (@possible.size - subset_of_guess) + less_than_guess * (@possible.size - superset_of_guess)
    }
  end
end

# Goes to show that if you try to use a comparison but you don't know the real weights,
# you will assign incorrect probabilities and cost a lot of guesses.
class MinEntropyRevCheater < Possibilities
  def guess
    return @possible[0] if @possible.size == 1

    @guesses.keys.min_by { |guess|
      eq = 0
      subset_of_guess = 0
      superset_of_guess = 0
      greater_than_guess = 0
      less_than_guess = 0
      neither = 0
      @possible.each { |candidate|
        if candidate == guess
          eq += 1
        else
          if candidate & guess == candidate
            subset_of_guess += 1
          elsif candidate & guess == guess
            superset_of_guess += 1
          else
            neither += 1
          end
          if candidate > guess
            greater_than_guess += 1
          else
            less_than_guess += 1
          end
        end
      }

      eq + less_than_guess * (@possible.size - subset_of_guess) + greater_than_guess * (@possible.size - superset_of_guess)
    }.tap { |g| @guesses.delete(g) }
  end
end

class MinMaxSize < Possibilities
  def guess
    return @possible[0] if @possible.size == 1

    (0...(1 << @n)).min_by { |guess|
      remain_if_too_light = remain_if_too_heavy = @possible.size
      @possible.each { |candidate|
        # If this is oo light, any subset is also too light.
        remain_if_too_light -= 1 if candidate & guess == candidate
        # If this is too heavy, any superset is also too heavy.
        remain_if_too_heavy -= 1 if candidate & guess == guess
      }
      [remain_if_too_light, remain_if_too_heavy].max
    }
  end
end

#play_game(256, 0b01010101, MinEntropyHalf.new(8, verbose: true))
#exit 0

[
  Seq,
  IncludeThenExclude,
  ExcludeThenInclude,
  MinEntropy,
  MinEntropyNoTrivial,
  MinEntropyHalf,
  MinEntropyHalfGuessPossible,
  MinEntropyCheater,
  MinMaxSize,
  MinEntropyRevCheater,
].each { |c|
  #puts "#{c}: #{rate_guesser(8, method(:powerset), c.method(:new))}"
  puts "#{c}: #{rate_guesser(8, method(:half_bits), c.method(:new))}"
  #puts "#{c}: #{rate_guesser(3, method(:powerset), c.method(:new))}"
  #puts "#{c}: #{rate_guesser(4, method(:powerset), c.method(:new))}"
}
