require 'airbrake'

module Liquid
  module Logging
    class ImprovedLogger
      # Log an exception with airbrake.
      #
      # @param [Exception] exc  The exception to log.
      # @param [String] message  Additional reason to log.
      def exception_with_airbrake(exc, message = nil, attribs = {})
        Airbrake.notify_or_ignore(exc, {
          :error_message => message,
          :cgi_data => ENV.to_hash,
        }.merge(attribs))
      end

      alias_method :exception_without_airbrake, :exception
      alias_method :exception, :exception_with_airbrake
    end
  end
end
