require 'logger'
require 'stringio'
require 'benchmark'

require 'madvertise/logging/improved_io'
require 'madvertise/logging/document_logger'

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

      # Log the file/line where the message came from
      attr_accessor :log_caller

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
        self.log_caller = false
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

      # Retrieve collected messages in case this instance is a document logger.
      #
      # @return [Array] An array of logged messages.
      def messages
        logger.messages if @backend == :document
      end

      # Get the current logging level.
      #
      # @return [Symbol] Current logging level.
      def level
        logger.level
      end

      # Set the logging level.
      #
      # @param [Symbol, Fixnum] level  New level as Symbol or Fixnum from Logger class.
      # @return [Fixnum] New level converted to Fixnum from Logger class.
      def level=(level)
        logger.level = level.is_a?(Symbol) ? self.class.severities[level] : level
        configure_log4j(logger)
        define_level_methods
      end

      # @private
      def define_level_methods
        # We do this dynamically here, so we can implement a no-op for levels
        # which are disabled.
        self.class.severities.each do |severity, num|
          if num >= level
            instance_eval(<<-EOM, __FILE__, __LINE__)
              def #{severity}(*args, &block)
                if block_given?
                  add(:#{severity}, *yield)
                else
                  add(:#{severity}, *args)
                end
              end

              def #{severity}?
                true
              end
            EOM
          else
            instance_eval("def #{severity}(*args); end", __FILE__, __LINE__)
            instance_eval("def #{severity}?; false; end", __FILE__, __LINE__)
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
      # @param [Exception] exc  The exception to log.
      # @param [String] message  Additional reason to log.
      def exception(exc, message = nil, attribs = {})
        fatal("exception", {
          class: exc.class,
          reason: exc.message,
          message: message,
          backtrace: clean_trace(exc.backtrace)
        }.merge(attribs).merge(called_from))
      end

      # Log a realtime benchmark
      #
      # @param [String] msg  The log message
      # @param [String,Symbol] key The realtime key
      def realtime(severity, msg, attribs = {}, &block)
        result = nil
        rt = Benchmark.realtime { result = yield }
        add(severity, msg, attribs.merge({rt: rt}))
        return result
      end

      def add(severity, message, attribs = {})
        severity = severity.is_a?(Symbol) ? severity : self.class.severities.key(severity)

        attribs.merge!(called_from) if @log_caller
        attribs.merge!(token: @token) if @token
        attribs = attribs.map do |k,v|
          "#{k}=#{v.to_s.clean_quote}"
        end.join(' ')

        message = "#{message} #{attribs}" if attribs.length > 0
        logger.send(severity) { message }

        return nil
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
        return unless trace
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

        file, line, _ = location.split(':')
        { :file => file, :line => line }
      end

      def create_backend
        self.close

        case @backend
        when :log4j
          create_log4j_backend
        when :ruby
          create_ruby_logger(STDOUT)
        when :stdout
          create_io_backend(STDOUT)
        when :stderr
          create_io_backend(STDERR)
        when :syslog
          create_syslog_backend
        when :buffer
          create_buffer_backend
        when :document
          create_document_backend
        when String
          create_file_backend
        when IO
          create_io_backend(@backend)
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

      def create_document_backend
        DocumentLogger.new.tap do |logger|
          logger.formatter = Formatter.new
          logger.progname = progname
        end
      end

      def create_io_backend(backend)
        @logfile = backend
        @logfile.sync = true
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
        case RUBY_PLATFORM
        when 'java'
          create_log4j_logger
        else
          create_ruby_logger(@logfile)
        end
      end

      def create_log4j_logger
        begin
          require 'log4j'
          require 'log4jruby'
          Log4jruby::Logger.get($0).tap do |logger|
            @backend = :log4j
            configure_log4j(logger)
          end
        rescue LoadError
          self.logger = :ruby
          error("Couldn't load log4jruby gem, falling back to pure ruby Logger")
        end
      end

      def configure_log4j(logger)
        return unless @backend == :log4j

        @console = org.apache.log4j.ConsoleAppender.new
        @console.setLayout(org.apache.log4j.PatternLayout.new(Formatter.log4j_format))
        @console.setThreshold(org.apache.log4j.Level.const_get(self.class.severities.key(logger.level).to_s.upcase.to_sym))
        @console.activateOptions

        org.apache.log4j.Logger.getRootLogger.tap do |root|
          root.getLoggerRepository.resetConfiguration
          root.addAppender(@console)
        end
      end

      def create_ruby_logger(io)
        Logger.new(io).tap do |logger|
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

        @format = "%{time} %{progname}(%{pid}) [%{severity}] %{msg}\n"
        @log4j_format = "%d %c(%t) [%p] %m%n"
        @time_format = "%Y-%m-%d %H:%M:%S.%N"

        class << self
          # Format string for log messages.
          attr_accessor :format
          attr_accessor :log4j_format

          # Format string for timestamps in log messages.
          attr_accessor :time_format
        end

        RUBY2SYSLOG = {
          :debug => 7,
          :info => 6,
          :warn => 4,
          :error => 3,
          :fatal => 2,
          :unknown => 3,
        }

        # @private
        def call(severity, time, progname, msg)
          self.class.format % {
            :time => time.strftime(self.class.time_format),
            :progname => progname,
            :pid => $$,
            :severity => severity,
            :syslog_severity => RUBY2SYSLOG[severity.downcase.to_sym],
            :msg => msg.to_s,
          }
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
