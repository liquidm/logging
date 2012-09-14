require 'bundler/setup'
require 'madvertise-logging'
require 'benchmark'

$log = Madvertise::Logging::ImprovedLogger.new(:buffer)

STRING_A = ("a string"*10).freeze
STRING_B = ("b string"*10).freeze

puts ">>> Testing String interpolation vs. concatenation"

n = 2000000
Benchmark.bmbm do |x|
  x.report("append double") { n.times do; "" << STRING_A << STRING_B << STRING_A; end }
  x.report("concat double") { n.times do; STRING_A + STRING_B + STRING_A; end }
  x.report("concat interp") { n.times do; "#{STRING_A}#{STRING_B}#{STRING_A}"; end }
end

n = 50000

puts
puts ">>> Testing caller"
Benchmark.bmbm do |x|
  x.report("caller") { n.times do; caller; end }
end

$debug = false
$log.level = :info

puts
puts ">>> Testing log.debug with debug disabled (n=#{n})"
Benchmark.bmbm do |x|
  x.report("debug w/  guard") { n.times do; $log.debug(STRING_A) if $debug; end }
  x.report("debug w/  block") { n.times do; $log.debug{STRING_A}; end }
  x.report("debug w/  block + concat") { n.times do; $log.debug{"#{STRING_A}#{STRING_B}#{STRING_A}"}; end }
  x.report("debug w/o guard") { n.times do; $log.debug(STRING_A); end }
  x.report("debug w/o guard + concat") { n.times do; $log.debug("#{STRING_A}#{STRING_B}#{STRING_A}"); end }
end

$debug = true
$log.level = :debug

puts
puts ">>> Testing log.debug with debug enabled (n=#{n})"
Benchmark.bmbm do |x|
  x.report("debug w/  guard") { n.times do; $log.debug(STRING_A) if $debug; end }
  x.report("debug w/o guard") { n.times do; $log.debug(STRING_A); end }
end

#require 'jruby/profiler'
#
#profile_data = JRuby::Profiler.profile do
#  n.times do; $log.debug(STRING_A); end
#end
#
#profile_printer = JRuby::Profiler::GraphProfilePrinter.new(profile_data)
#profile_printer.printProfile(STDOUT)
