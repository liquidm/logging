begin
  require 'reek/rake/task'
  Reek::Rake::Task.new do |t|
    t.fail_on_error = false
  end
rescue LoadError
  STDERR.puts "failed to load reek. please add gem 'reek' to your Gemfile in order to use reek"
end
