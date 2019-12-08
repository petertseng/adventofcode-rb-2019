verbose = ARGV.delete('-v')

width = 25
layer = width * 6

input = ARGF.read.chomp

layers = input.each_char.each_slice(layer).to_a

min_layer = layers.min_by { |x| x.count(?0) }
p min_layer.tally if verbose
puts min_layer.count(?1) * min_layer.count(?2)

pixels = layers.transpose.map { |pixel| pixel.find { |layer| layer != ?2 } }
disp = {?1 => ?#, ?0 => ' '}.freeze
pixels.each_slice(width) { |row| puts row.map { |pixel| disp.fetch(pixel) }.join }
