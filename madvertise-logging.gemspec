# encoding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "madvertise-logging"
  spec.version       = "1.2.1"
  spec.authors       = ["madvertise Mobile Advertising GmbH"]
  spec.email         = ["tech@madvertise.com"]
  spec.description   = %q{Advanced logging classes with buffer backend, transactions, multi logger, etc}
  spec.summary       = %q{Advanced logging classes with buffer backend, transactions, multi logger, etc}
  spec.homepage      = "https://github.com/madvertise/logging"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  if RUBY_PLATFORM == "java"
    spec.platform = 'java'
    spec.add_dependency "log4jruby", "~> 1.0.0.rc1"
    spec.add_dependency "slyphon-log4j", "~> 1.2.15"
  end
end
