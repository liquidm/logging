require 'madvertise-logging'
require 'benchmark'

GC.disable

$log = Madvertise::Logging::ImprovedLogger.new("/dev/null")

STRING_A = "a string".freeze
STRING_B = "b string".freeze

puts ">>> Testing String interpolation vs. concatenation"

n = 2000000
Benchmark.bm do |x|
  x.report("concat double") { n.times do; STRING_A + STRING_B; end }
  x.report("concat interp") { n.times do; "#{STRING_A}#{STRING_B}"; end }
end

puts
puts ">>> Testing log.debug with debug disabled"

$debug = false
$log.level = :info

n = 1000000
Benchmark.bm do |x|
  x.report("debug w/o guard") { n.times do; $log.debug(STRING_A); end }
  x.report("debug w/  guard") { n.times do; $log.debug(STRING_A) if $debug; end }
end

puts
puts ">>> Testing log.debug with debug enabled"

$debug = true
$log.level = :debug

n = 10000
Benchmark.bm do |x|
  x.report("debug w/o guard") { n.times do; $log.debug(STRING_A); end }
  x.report("debug w/  guard") { n.times do; $log.debug(STRING_A) if $debug; end }
end
