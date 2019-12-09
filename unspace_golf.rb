code = File.readlines('golf9_spaced.rb').map(&:strip).grep_v(/^ *#/).join

File.open('golf9.rb', ?w) { |f| f.write(code) }

def run(script, day, input)
  `echo #{input} | ruby #{script} $(tail -1 #{day}*.rb)`
end

def compare(in1, in2, day)
  ps1 = run('golf9_spaced.rb', day, in1).lines.drop_while { |x| x == "0\n" }.join
  ps2 = run('golf9_spaced.rb', day, in2)
  p1 = run('golf9.rb', day, in1).lines.drop_while { |x| x == "0\n" }.join
  p2 = run('golf9.rb', day, in2)

  puts "huh? outputs not the same for compacted version, #{ps1} vs #{p1}" if ps1 != p1
  puts "huh? outputs not the same for compacted version, #{ps2} vs #{p2}" if ps2 != p2
  raise 'bad' if ps1 != p1 || ps2 != p2

  puts p1
  puts p2
  answer = "#{p1.chomp}\n#{p2.chomp}"
  system("echo '#{answer}' | diff -su - expected_output/#{day}")
end

compare(1, 5, '05')
compare(1, 2, '09')

system('wc -c golf9.rb')
