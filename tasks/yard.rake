begin
  require 'yard'

  YARD::Rake::YardocTask.new do |t|
    t.files = ['lib/**/*.rb', 'README.rdoc']
  end
rescue LoadError
  STDERR.puts "failed to load yard. please add gem 'yard' to your Gemfile in order to use yard"
end
