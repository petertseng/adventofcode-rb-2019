# adventofcode-rb-2019

[![Build Status](https://travis-ci.org/petertseng/adventofcode-rb-2019.svg?branch=master)](https://travis-ci.org/petertseng/adventofcode-rb-2019)

For the fifth year in a row, it's the time of the year to do [Advent of Code](http://adventofcode.com) again.

When will it end?

The solutions are written with the following goals, with the most important goal first:

1. **Speed**.
   Where possible, use efficient algorithms for the problem.
   Solutions that take more than a second to run are treated with high suspicion.
   This need not be overdone; micro-optimisation is not necessary.
2. **Readability**.
3. **Less is More**.
   Whenever possible, write less code.
   Especially prefer not to duplicate code.
   This helps keeps solutions readable too.

All solutions are written in Ruby.
Features from 2.6.x will be used, with no regard for compatibility with past versions.
`Enumerable#to_h` with block is anticipated to be the most likely reason for incompatibility.

# Input

In general, all solutions can be invoked in both of the following ways:

* Without command-line arguments, takes input on standard input.
* With command-line arguments, reads input from the named files (- indicates standard input).

Some may additionally support other ways:

* All intcode days: May pass the intcode in ARGV as a single argument separated by commas.
* Day 04 (Password): May pass min and max in ARGV (as two args, or as one arg joined by a hyphen).

# Highlights

Favourite problems:

* Day 10 (Monitoring Station): Interesting novel problem I hadn't seen before, and fun to think about asteroids being destroyed. Interesting educational value as well (reminder that atan2 exists).
* Day 13 (Breakout): The first of the days where we saw some "creative" solutions since we have full control of the computer the Intcode program is running on. Some participants extended their paddle, some added walls at the bottom, some modified the code so that the bottom allows the ball to bounce, etc.

Interesting approaches:

* Day 02 (Intcode): Assume linearity, determine coefficients with a few runs, determine noun and verb.
* Day 03 (Crossed Wires): Storing segment endpoints is faster than storing every point touched by the wires.
* Day 04 (Password): Skip over entire swaths of non-increasing passwords. If considering 341234, skip straight to 344444.
* Day 07 (Amplification Circuit): Assume all amplifiers perform a linear transform mx+b and determine m and b to reduce the number of times the amplifiers need to be run.
* Day 09 (Intcode Relative): Function call optimisation. If a function is called multiple times with the same argument(s), immediately place the correct return value (from previous call) onto the stack and return. Turns the `f(n - 1) + f(n - 3)` recurrence runtime from exponential to linear.
* Day 11 (Intcode Langton's Ant): Determine ant's periodicity by exmaining its program counter, then reimplement the logic natively to avoid calling the ant so many times.
* Day 13 (Breakout): Hijack execution and call the function for when a block gets broken, passing it all block locations. Could do even better by extracting the affine transform constants (for score calculation) out of the program, but this seemed good enough.
* Day 15 (Intcode Search): Intcode machine can duplicate its state and return to it later. Multiverse repair droids.
* Day 16 (Flawed Frequency Transmission): Part 1: Partial sum table. Part 2: binomial coefficients, Lewis's Theorem, Chinese Remainder Theorem. If one side of a product is known to be zero, do not calculate the other side of it.
* Day 17 (Set And Forget): Teleport the robot by hijacking control.

# Takeaways

* Day 03 (Crossed Wires): A few errors when redoing multiple wire traces, by forgetting to reset the position. Would have been better to write the `trace_wire` function from the start, instead of inlining it initially as I did.

# Posting schedule and policy

Before I post my day N solution, the day N leaderboard **must** be full.
No exceptions.

Waiting any longer than that seems generally not useful since at that time discussion starts on [the subreddit](https://www.reddit.com/r/adventofcode) anyway.

Solutions posted will be **cleaned-up** versions of code I use to get leaderboard times (if I even succeed in getting them), rather than the exact code used.
This is because leaderboard-seeking code is written for programmer speed (whatever I can come up with in the heat of the moment).
This often produces code that does not meet any of the goals of this repository (seen in the introductory paragraph).

# Past solutions

The [index](https://github.com/petertseng/adventofcode-common/blob/master/index.md) lists all years/languages I've ever done (or will ever do).
