def step(poses, vels)
  poses.each_with_index { |pi, i|
    # pi = 2, p = 5, we want it to increase.
    # so we do 5 <=> 2 which is 1.
    vels[i] += poses.sum { |p| p <=> pi }
  }
  vels.each_with_index { |vel, i| poses[i] += vel }
end

def run1k(moons)
  pos = moons.dup
  vel = moons.map { 0 }

  1000.times { step(pos, vel) }
  pos.zip(vel)
end

def codegen_vel_update
  i = (0...4).to_a
  i.combination(2) { |a, b|
    # among these options, this one seems to be fastest.
    puts "if p#{a} > p#{b}; v#{a} -= 1; v#{b} += 1; elsif p#{b} > p#{a}; v#{a} += 1; v#{b} -= 1; end"

    #puts "if p#{a} > p#{b}; v#{a}] -= 1; v#{b} += 1; end"
    #puts "if p#{b} > p#{a}; v#{a}] += 1; v#{b} -= 1; end"

    #puts "cmp#{a}#{b} = p#{a} <=> p#{b}"
    #puts "v#{a} -= cmp#{a}#{b}"
    #puts "v#{b} += cmp#{a}#{b}"
  }
end

def period(moons)
  raise "Can't handle anything other than four moons" if moons.size != 4

  p0, p1, p2, p3 = moons
  v0 = v1 = v2 = v3 = 0

  t = 0

  # A lot of code duplication, but this otherwise runs slow (> 1 second).
  # I probably just should use a compiled language.
  # It's not like I wrote this by hand though, codegen saves the day.
  while true
    if p0 > p1; v0 -= 1; v1 += 1; elsif p1 > p0; v0 += 1; v1 -= 1; end
    if p0 > p2; v0 -= 1; v2 += 1; elsif p2 > p0; v0 += 1; v2 -= 1; end
    if p0 > p3; v0 -= 1; v3 += 1; elsif p3 > p0; v0 += 1; v3 -= 1; end
    if p1 > p2; v1 -= 1; v2 += 1; elsif p2 > p1; v1 += 1; v2 -= 1; end
    if p1 > p3; v1 -= 1; v3 += 1; elsif p3 > p1; v1 += 1; v3 -= 1; end
    if p2 > p3; v2 -= 1; v3 += 1; elsif p3 > p2; v2 += 1; v3 -= 1; end

    p0 += v0
    p1 += v1
    p2 += v2
    p3 += v3

    t += 1

    # Given each state, there is only one previous state that could have led to it.
    # Because of this, the initial state is guaranteed to be the first repeat state.

    # Further, consider any state with velocities all 0:
    # t-1: [(p0   , ?),  (p1   , ?),  (p2,    0),  (p3   , ?)]
    # t  : [(p0   , 0),  (p1   , 0),  (p2,    0),  (p3   , 0)]
    # t+1: [(p0+v0, v0), (p1+v1, v1), (p2+v2, v2), (p3+v3, v3)]
    #
    # We see that positions at t-1 must be equal to positions at t, because velocities ended at 0.
    # Since positions are the same, velocity deltas are the same, which means we know more:
    #
    # t-2: [(p0+v0,   ?), (p1+v1, ?),   (p2+v2, ?),   (p3+v3, ?)]
    # t-1: [(p0   , -v0), (p1   , -v1), (p2,    -v2), (p3   , -v3)]
    # t  : [(p0   , 0),   (p1   , 0),   (p2,    0),   (p3   , 0)]
    # t+1: [(p0+v0, v0),  (p1+v1, v1),  (p2+v2, v2),  (p3+v3, v3)]
    #
    # Denoting the delta in velocity at times t+1 and t-2 (which are the same) as a0, a1, a2, a3, then we have:
    #
    # t-3: [(p0+2*v0+a0,     ?), (p1+2*v1+a1,     ?), (p2+2*v2+a2,     ?), (p3+2*v3+a3,     ?)]
    # t-2: [(p0+v0,     -v0-a0), (p1+v1,     -v1-a1), (p2+v2,     -v2-a2), (p3+v3,     -v3-a3)]
    # ...
    # t+2: [(p0+2*v0+a0, v0+a0), (p1+2*v1+a1, v1+a1), (p2+2*v2+a2, v2+a2), (p3+2*v3+a3, v3+a3)]
    #
    # This process continues to repeat.
    # So we have this symmetry in velocities on either side of v=0.
    # So, if we ever reach a position with velocities 0, we certainly return to the initial state in t*2.
    # We could just continue to run the simulation to be sure, but might as well cut runtime in half, right?
    return t * 2 if v0 == 0 && v1 == 0 && v2 == 0 && v3 == 0
  end
end

verbose = ARGV.delete('-v')

coordinates = ARGF.map { |l| l.scan(/-?\d+/).map(&method(:Integer)) }.transpose.map(&:freeze).freeze

moons1k = coordinates.map(&method(:run1k)).transpose
puts moons1k.sum { |moon| moon.transpose.map { |c| c.sum(&:abs) }.reduce(:*) }

periods = coordinates.map(&method(:period))
p periods if verbose
puts periods.reduce(1) { |a, b| a.lcm(b) }
