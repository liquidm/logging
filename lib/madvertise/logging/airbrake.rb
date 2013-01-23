require 'airbrake'

module Madvertise
  module Logging
    class ImprovedLogger
      # Log an exception with airbrake.
      #
      # @param [Exception] exc  The exception to log.
      # @param [String] message  Additional reason to log.
      def exception(exc, message = nil, attribs = {})
        Airbrake.notify_or_ignore(exc, {
          :error_message => message,
          :cgi_data => ENV.to_hash,
        }.merge(attribs))
      end
    end
  end
end
