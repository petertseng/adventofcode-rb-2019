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

def binom(n, k)
  k == 0 ? 1 : n * binom(n - 1, k - 1) / k
end

def binom_mod(n, k, m)
  # Assumes (without checking) that m is prime
  # Lucas's Theorem
  return 1 if k == 0

  r = binom(n % m, k % m) % m
  return r if n < m

  # zero times anything is zero, no need to spawn more recursive calls.
  return 0 if r == 0

  (r * binom_mod(n / m, k / m, m)) % m
end

def binom_mod_10(n, k)
  # Chinese Remainder Theorem
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
  #(binom_mod(n, k, 2) * 5 + binom_mod(n, k, 5) * 6) % 10
  # By Lucas's Theorem, binom(n, k) % 2 is equal to (n & k == k ? 1 : 0).
  #((n & k == k ? 1 : 0) * 5 + binom_mod(n, k, 5) * 6) % 10
  ((n & k == k ? 5 : 0) + binom_mod(n, k, 5) * 6) % 10
end

big_size = input.size * 10000 - offset
rsize = 8

result = [0] * rsize
big_size.times { |i|
  bin = binom_mod_10(99 + i, i)
  # No point doing array reads/writes if they're going to be multiplied by zero.
  # Saves a decent chunk of time since about 92.25% of the coefficients are zero...
  next if bin == 0

  dist_from_end = big_size - i
  [dist_from_end, rsize].min.times { |j|
    result[j] += input[(offset + i + j) % input.size] * bin
  }
}
puts result.map { |x| x % 10 }.join
