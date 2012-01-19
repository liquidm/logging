module Madvertise
  module Logging
    class MultiLogger
      def initialize(*loggers)
        @loggers = loggers
      end

      def attach(logger)
        logger.new_transaction(@loggers.first.transaction_token)
        @loggers << logger
      end

      def detach(logger)
        @loggers.delete(logger)
      end

      def method_missing(name, *args)
        @loggers.each do |l|
          l.send(name, *args)
        end
      end
    end
  end
end
