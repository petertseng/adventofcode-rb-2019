def increasing_between(min, max)
  max_digits = max.digits.reverse
  digits = min.digits.reverse

  _, decrease = digits.each_cons(2).with_index.find { |(a, b), i|
    a > b
  }
  # If min doesn't already meet criteria,
  # construct the first number that does.
  # For example 123411 would turn into 123444
  if decrease
    digits = digits.take(decrease) + [digits[decrease]] * (digits.size - decrease)
  end

  Enumerator.new { |y|
    # You can't use > to compare arrays, but you can <=> them.
    until (digits <=> max_digits) > 0
      y << digits.dup

      # Increasing digits never jeopardises increasing status,
      # unless nines roll over into zeroes.
      # Check for nines, and change them to the next increasing.
      # For example, 123999 would turn into 124444
      non_nine = -1
      non_nine -= 1 while digits[non_nine] == 9
      new_digit = digits[non_nine] + 1
      (non_nine..-1).each { |i| digits[i] = new_digit }
    end
  }
end

range = case ARGV.size
when 0
  ARGF.read.split(?-)
when 1
  (/^\d+-\d+$/.match?(ARGV[0]) ? ARGV[0] : ARGF.read).split(?-)
else
  ARGV
end

min, max = range.map(&method(:Integer))

# We already know digits are non-decreasing,
# so we can just count the occurrences of each digit,
# and not worry about occurrences being separated!
increasing = increasing_between(min, max).map { |x|
  x.tally.values
}

puts increasing.count { |d| d.any? { |x| x >= 2 } }
puts increasing.count { |d| d.include?(2) }
