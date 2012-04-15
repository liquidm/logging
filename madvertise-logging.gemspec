# -*- encoding: utf-8 -*-
require File.expand_path('../lib/madvertise/logging/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "madvertise-logging"
  gem.version       = Madvertise::Logging::VERSION
  gem.authors       = ["Benedikt Böhm"]
  gem.email         = ["benedikt.boehm@madvertise.com"]
  gem.description   = %q{Advanced logging classes with buffer backend, transactions, multi logger, etc}
  gem.summary       = %q{Advanced logging classes with buffer backend, transactions, multi logger, etc}
  gem.homepage      = "https://github.com/madvertise/logging"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_paths = ["lib"]
end
