require 'logger'
require 'stringio'

require 'madvertise/logging/improved_io'

class String
  def clean_quote
    if index(/["\s]/)
      %{"#{tr('"', "'")}"}
    else
      self
    end
  end
end

module Madvertise
  module Logging

    ##
    # ImprovedLogger is an enhanced version of DaemonKits AbstractLogger class
    # with token support, buffer backend and more.
    #
    class ImprovedLogger < ImprovedIO

      # Program name prefix. Used as ident for syslog backends.
      attr_accessor :progname

      # Arbitrary token to prefix log messages with.
      attr_accessor :token

      # Log filename for file backend.
      attr_reader :logfile

      @severities = {
        :debug   => Logger::DEBUG,
        :info    => Logger::INFO,
        :warn    => Logger::WARN,
        :error   => Logger::ERROR,
        :fatal   => Logger::FATAL,
        :unknown => Logger::UNKNOWN
      }

      @silencer = true

      class << self
        # Hash of Symbol/Fixnum pairs to map Logger levels.
        attr_reader :severities

        # Enable/disable the silencer on a global basis. Useful for debugging
        # otherwise silenced code blocks.
        attr_accessor :silencer
      end

      def initialize(backend = STDERR, progname = nil)
        self.progname = progname || File.basename($0)
        self.logger = backend
      end

      # Get the backend logger.
      #
      # @return [Logger] The currently active backend logger object.
      def logger
        @logger ||= create_backend
      end

      # Set a different backend.
      #
      # @param [Symbol, String, IO, Logger] value  The new logger backend. Either a
      #   Logger object, an IO object, a String containing the logfile path or a Symbol to
      #   create a default backend for :syslog or :buffer
      # @return [Logger] The newly created backend logger object.
      def logger=(value)
        @backend = value
        @logger = create_backend
        define_level_methods
      end

      # Close any connections/descriptors that may have been opened by the
      # current backend.
      def close
        @logger.close rescue nil
        @logger = nil
      end

      # Retrieve the current buffer in case this instance is a buffered logger.
      #
      # @return [String] Contents of the buffer.
      def buffer
        @logfile.string if @backend == :buffer
      end

      # Get the current logging level.
      #
      # @return [Symbol] Current logging level.
      def level
        @severities_inverted ||= self.class.severities.invert
        @level ||= @severities_inverted[@logger.level]
      end

      # Set the logging level.
      #
      # @param [Symbol, Fixnum] level  New level as Symbol or Fixnum from Logger class.
      # @return [Fixnum] New level converted to Fixnum from Logger class.
      def level=(level)
        logger.level = level.is_a?(Symbol) ? self.class.severities[level] : level
        define_level_methods
      end

      # @private
      def define_level_methods
        # We do this dynamically here, so we can implement a no-op for levels
        # which are disabled.
        self.class.severities.each do |severity, num|
          if num >= logger.level
            instance_eval(<<-EOM, __FILE__, __LINE__)
              def #{severity}(*args, &block)
                if block_given?
                  add(:#{severity}, yield, *args)
                else
                  add(:#{severity}, *args)
                end
              end
            EOM
          else
            instance_eval("def #{severity}(*args); end", __FILE__, __LINE__)
          end
        end
      end

      # Compatibility method
      # @private
      def <<(msg)
        add(:info, msg)
      end

      alias write <<

      # Log an exception with fatal level.
      #
      # @param [Exception, String] exc  The exception to log. If exc is a
      #   String no backtrace will be generated.
      # @param [String] prefix  Additional message to log.
      def exception(exc, prefix=nil)
        msg = "EXCEPTION"
        msg << ": #{prefix}" if prefix
        msg << ": #{exc.message}: #{clean_trace(exc.backtrace)}" if exc.is_a?(::Exception)
        fatal(msg)
      end

      # Save the current token and associate it with obj#object_id.
      def save_token(obj)
        if @token
          @tokens ||= {}
          @tokens[obj.object_id] = @token
        end
      end

      # Restore the token that has been associated with obj#object_id.
      def restore_token(obj)
        @tokens ||= {}
        @token = @tokens.delete(obj.object_id)
      end

      # Silence the logger for the duration of the block.
      def silence(temporary_level = :error)
        if self.class.silencer
          begin
            old_level, self.level = self.level, temporary_level
            yield self
          ensure
            self.level = old_level
          end
        else
          yield self
        end
      end

      # Remove references to the madvertise-logging gem from exception
      # backtraces.
      #
      # @private
      def clean_trace(trace)
        trace.reject do |line|
          line =~ /(gems|vendor)\/madvertise-logging/
        end
      end

      private

      # Return the first callee outside the madvertise-logging gem. Used in add
      # to figure out where in the source code a message has been produced.
      def called_from
        location = caller.detect('unknown:0') do |line|
          line.match(/(improved_logger|multi_logger)\.rb/).nil?
        end

        file, num, discard = location.split(':')
        [ File.basename(file), num ].join(':')
      end

      def add(severity, message, attribs={})
        severity = self.class.severities[severity]
        message = "#{called_from}: #{message}"
        message = "[#{@token}] #{message}" if @token
        message = "#{message} #{attribs.map{|k,v| "#{k}=#{v.clean_quote}"}.join(' ')}" if attribs.any?
        logger.add(severity) { message }
        return nil
      end

      def create_backend
        self.close

        case @backend
        when :syslog
          create_syslog_backend
        when :buffer
          create_buffer_backend
        when String
          create_file_backend
        when IO
          create_io_backend
        when Logger
          @backend
        else
          raise "unknown backend: #{@backend.inspect}"
        end
      end

      def create_syslog_backend
        begin
          require 'syslogger'
          Syslogger.new(progname, Syslog::LOG_PID, Syslog::LOG_LOCAL1)
        rescue LoadError
          self.logger = $stderr
          error("Couldn't load syslogger gem, reverting to STDERR for logging")
        end
      end

      def create_buffer_backend
        @logfile = StringIO.new
        create_logger
      end

      def create_io_backend
        @logfile = @backend
        create_logger
      end

      def create_file_backend
        @logfile = @backend

        begin
          FileUtils.mkdir_p(File.dirname(@logfile))
        rescue
          self.logger = $stderr
          error("#{@logfile} not writable, using STDERR for logging")
        else
          create_logger
        end
      end

      def create_logger
        Logger.new(@logfile).tap do |logger|
          logger.formatter = Formatter.new
          logger.progname = progname
        end
      end

      ##
      # The Formatter class is responsible for formatting log messages. The
      # default format is:
      #
      #   YYYY:MM:DD HH:MM:SS.MS daemon_name(pid) level: message
      #
      class Formatter

        @format = "%s %s(%d) [%s] %s\n"

        class << self
          # Format string for log messages.
          attr_accessor :format
        end

        # @private
        def call(severity, time, progname, msg)
          time = time.strftime("%Y-%m-%d %H:%M:%S.%N")
          self.class.format % [time, progname, $$, severity, msg.to_s]
        end
      end

      # @private
      module IOCompat
        def close_read
          nil
        end

        def close_write
          close
        end

        def closed?
          raise NotImplementedError
        end

        def sync
          @backend != :buffer
        end

        def sync=(value)
          raise NotImplementedError, "#{self} cannot change sync mode"
        end

        # ImprovedLogger is write-only
        def _raise_write_only
          raise IOError, "#{self} is a buffer-less, write-only, non-seekable stream."
        end

        [
          :bytes,
          :chars,
          :codepoints,
          :lines,
          :eof?,
          :getbyte,
          :getc,
          :gets,
          :pos,
          :pos=,
          :read,
          :readlines,
          :readpartial,
          :rewind,
          :seek,
          :ungetbyte,
          :ungetc
        ].each do |meth|
          alias_method meth, :_raise_write_only
        end
      end

      include IOCompat
    end
  end
end
