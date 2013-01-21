require 'airbrake'

module Madvertise
  module Logging
    class ImprovedLogger
      # Log an exception with airbrake.
      #
      # @param [Exception] exc  The exception to log.
      # @param [String] message  Additional reason to log.
      def exception(exc, message = nil, attribs = {})
        Airbrake.notify_or_ignore(exc, attribs.merge({
          error_class: exc.class,
          error_message: message,
          reason: exc.message,
          backtrace: clean_trace(exc.backtrace)
        }))
      end
    end
  end
end
