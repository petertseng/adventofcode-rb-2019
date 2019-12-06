require_relative 'lib/search'

orbit = {}
transfer = Hash.new { |h, k| h[k] = [] }

ARGF.each { |x|
  a, b = x.chomp.split(?))
  orbit[b] = a
  transfer[a] << b
  transfer[b] << a
}

orbit.freeze
transfer.freeze

# Not convinced the cache makes that big of a difference, but sure.
cache = {}
depth = ->x { cache[x] ||= (orbiting = orbit[x]) ? 1 + depth[orbiting] : 0 }

puts orbit.keys.sum(&depth)

unless (youOrbit = orbit['YOU']) && (sanOrbit = orbit['SAN'])
  puts 'nonexistent'
  exit 0
end

result = Search.bfs(youOrbit, neighbours: transfer, goal: {sanOrbit => true})
puts result[:goals].empty? ? 'impossible' : result[:gen]
