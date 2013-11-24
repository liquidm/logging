module Liquid
  module Logging

    ##
    # MultiLogger is a simple class for multiplexing ImprovedLogger objects. It
    # support attach/detach to send messages to any number of loggers.

    class MultiLogger
      def initialize(*loggers)
        @loggers = loggers
      end

      # Attach an ImprovedLogger object.
      def attach(logger)
        logger.token = @loggers.first.token rescue nil
        @loggers << logger
      end

      # Detach an ImprovedLogger object.
      def detach(logger)
        @loggers.delete(logger)
      end

      # Delegate all method calls to all attached loggers.
      #
      # @private
      def method_missing(name, *args, &block)
        @loggers.map do |logger|
          logger.send(name, *args, &block)
        end.first
      end
    end
  end
end
