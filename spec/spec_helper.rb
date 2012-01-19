require 'rubygems'
require 'rspec'
require 'fileutils'

require 'simplecov'
SimpleCov.start

ROOT = "#{File.dirname(__FILE__)}/../tmp"

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'madvertise-logging'

RSpec.configure do |config|
  # == Mock Framework
  #
  # RSpec uses it's own mocking framework by default. If you prefer to
  # use mocha, flexmock or RR, uncomment the appropriate line:
  #
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr

  # setup a fake root
  config.before(:all) { File.directory?(ROOT) ? FileUtils.rm_rf("#{ROOT}/*") : FileUtils.mkdir_p(ROOT) }
  config.after(:all) { FileUtils.rm_rf("#{ROOT}/*") }
end
