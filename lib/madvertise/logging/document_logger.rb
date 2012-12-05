require 'logger'

module Madvertise
  module Logging

    ##
    # DocumentLogger is a Logger compliant class that keeps a structured
    # document per log message in memory.
    #
    class DocumentLogger < ::Logger

      attr_accessor :attrs
      attr_accessor :messages

      def initialize
        super(nil)
        @messages = []
        @attrs = {}
      end

      def add(severity, message = nil, progname = nil, &block)
        severity ||= UNKNOWN
        if severity < @level
          return true
        end

        progname ||= @progname

        if message.nil?
          if block_given?
            message = yield
          else
            message = progname
            progname = @progname
          end
        end

        @messages << @attrs.merge({
          severity: severity,
          time: Time.now,
          progname: progname,
          message: message,
        })

        true
      end
    end
  end
end
