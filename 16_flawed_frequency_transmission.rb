def fft(digits)
  sum = 0
  sum_left = digits.map { |d| sum += d }
  sum_left.unshift(0)

  digits.each_index { |i|
    n = i + 1
    sign = 1
    base = i
    total = 0
    while base < digits.size
      total += ((sum_left[base + n] || sum_left[-1]) - sum_left[base]) * sign
      base += n * 2
      sign *= -1
    end
    digits[i] = total.abs % 10
  }
end

input = ARGF.read.chomp.chars.map(&method(:Integer)).freeze

digits = input.dup
100.times { fft(digits) }
puts digits.take(8).join

offset = Integer(input.take(7).join, 10)

raise "Can't do it the fast way" unless offset * 2 >= input.size * 10000

# As long as we are in the latter half of the list,
# each value is just the sum of all values coming after it.
# Just going right-to-left with a running sum is sufficient to solve this relatively quickly.
# But let's do slightly better.
# Observe the contribution of a lone 1.
# It's binomial coefficients.
# Going left adds 1 to n and k, going down (one iteration) adds 1 to n.
# The coefficients for the 100th iteration can be calculated and reused.
# They would otherwise be very large, but all operations are modulo 10.
# So a few theorems can help make it easier.
#
# We want we're going to want binom(99 + i, i) % 10.
# Because binom(n, k) == binom(n, n - k), that's equal to:
# binom(99 + i, 99) % 10.

# Calculates binom(99 + i, 99) % 10.
def binom_99_mod_10(i)
  # By Chinese Remainder Theorem...
  #
  # x congruent to a_i mod n_i
  # x = sum a_i y_i z_i
  # y_i is the product of all other moduli
  # z_i is the modular inverse of y_i mod n_i
  #
  # Modular inverse of 5 mod 2 is 1
  # Modular inverse of 2 mod 5 is 3
  #
  # 1 * 5 = 5
  # 2 * 3 = 6
  #
  # So that tells us we want:
  # (binom(99 + i, 99) % 2) * 5 + (binom(99 + i, 99) % 5) * 6
  #
  # By Lucas's Theorem, binom(n, k) % 2 depends on the base-2 expansion of n and k.
  # It's only nonzero if all digits of the expansions paired together are nonzero,
  # Therefore, is equal to (n & k == k ? 1 : 0).
  #
  # So (binom(99 + i, 99) % 2) * 5 is rewritten as:
  # ((99 + i) & 99 == 99 ? 1 : 0) * 5, or:
  mod_2_term = (99 + i) & 99 == 99 ? 5 : 0

  # In the same way, binom(n, k) % 5 depends on the base-5 expansion of n and k.
  # The base-5 expansion of 99 is 344_5.
  # If any base-5 digit of 99 + i is less than the corresponding base-5 digit in 344_5,
  # then that contributes binom(n, k) for n < k, which is always 0
  # (e.g. 2 choose 4 == 0).
  # So the only possibilities for last three base-5 digits of base-5 expansion for n must be 344_5 or 444_5.
  # For 344_5, result is binom(3, 3) * binom(4, 4) * binom(4, 4) = 1 * 1 * 1 = 1.
  # For 444_5, result is binom(4, 3) * binom(4, 4) * binom(4, 4) = 4 * 1 * 1 = 4.
  # Multiply by 6 to get 6 and 24, mod by 10 to get 6 and 4.
  #
  # These cases happen when (99 + i) % 125 == 99 and (99 + i) % 125 == 124.
  # Subtract 99 from both sides to get i % 125 == 0 and i % 125 == 25.
  mod_5_term = case i % 125
  when 0; 6
  when 25; 4
  else; 0
  end

  (mod_2_term + mod_5_term) % 10
end

big_size = input.size * 10000 - offset
rsize = 8

result = [0] * rsize
big_size.times { |i|
  bin = binom_99_mod_10(i)
  # No point doing array reads/writes if they're going to be multiplied by zero.
  # Saves a decent chunk of time since about 92.25% of the coefficients are zero...
  next if bin == 0

  dist_from_end = big_size - i
  [dist_from_end, rsize].min.times { |j|
    result[j] += input[(offset + i + j) % input.size] * bin
  }
}
puts result.map { |x| x % 10 }.join
