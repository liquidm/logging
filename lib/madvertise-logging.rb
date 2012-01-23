require 'madvertise/logging/version'
require 'madvertise/logging/improved_logger'
require 'madvertise/logging/multi_logger'

module Madvertise
  class << self
    # get global logger instance
    def logger
      @logger
    end

    # set global logger instance
    def logger=(logger)
      @logger = logger
    end
  end
end
