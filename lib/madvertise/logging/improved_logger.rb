require 'logger'
require 'stringio'

module Madvertise
  module Logging
    class ImprovedLogger

      attr_accessor :copy_to_stdout
      attr_accessor :transaction_token
      attr_accessor :progname

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
        attr_reader :severities
        attr_accessor :silencer
      end

      def initialize(logfile = nil, progname = nil)
        @copy_to_stdout = false
        @progname = progname || File.basename($0)
        self.logger = logfile || STDERR
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

      def debug(msg)
        add(:debug, msg)
      end

      def debug?
        self.level == :debug
      end

      def info(msg)
        add(:info, msg)
      end

      def info?
        self.level == :info
      end

      def warn(msg)
        add(:warn, msg)
      end

      def warn?
        self.level == :warn
      end

      def error(msg)
        add(:error, msg)
      end

      def error?
        self.level == :error
      end

      def fatal(msg)
        add(:fatal, msg)
      end

      def fatal?
        self.level == :fatal
      end

      def unknown(msg)
        add(:unknown, msg)
      end

      def unknown?
        self.level == :unknown
      end

      def exception(e)
        if e.is_a?(::Exception)
          message = "EXCEPTION: #{e.message}: #{clean_trace(e.backtrace)}"
        else
          message = e
        end
        add(:error, message, true)
      end

      def add(severity, message, skip_caller = false)
        message = "#{called(caller)}: #{message}" unless skip_caller
        message = "[#{@transaction_token}] #{message}" if @transaction_token

        self.logger.add(self.class.severities[severity]) { message }

        STDOUT.puts(message) if self.copy_to_stdout && self.class.severities[severity] >= self.logger.level
      end

      def level
        self.class.severities.invert[@logger.level]
      end

      def level=(level)
        level = (Symbol === level ? self.class.severities[level] : level)
        self.logger.level = level
      end

      def new_transaction(v)
        @transaction_token = v
      end

      def end_transaction
        @transaction_token = nil
      end

      def save_transaction(obj)
        if @transaction_token && obj
          @transactions ||= {}
          @transactions[obj.object_id] = @transaction_token
        end
      end

      def restore_transaction(obj)
        @transactions ||= {}
        @transaction_token = @transactions.delete(obj.object_id) if obj
      end

      def logger
        @logger ||= create_logger
      end

      def logger=(value)
        @logger.close rescue nil

        if value.is_a?(Logger)
          @backend = :logger
          @logger = value
        elsif value.is_a?(Symbol)
          @backend = value
          @logger = create_logger
        else
          @backend = :logger
          @logfile = value
          @logger = create_logger
        end
      end

      def clean_trace(trace)
        trace = trace.map { |l| l.gsub(ROOT, '') }
        trace = trace.reject { |l| l =~ /gems\/madvertise-logging/ }
        trace = trace.reject { |l| l =~ /vendor\/madvertise-logging/ }
        trace
      end

      def close
        case @backend
        when :logger
          self.logger.close
          @logger = nil
        end
      end

      def buffer
        if @backend == :buffer && @buffer
          @buffer.string
        end
      end

      private

      def called(trace)
        l = trace.detect('unknown:0') do |l|
          l.index(File.basename(__FILE__)).nil?
        end

        file, num, _ = l.split(':')
        [ File.basename(file), num ].join(':')
      end

      def create_logger
        case @backend
        when :buffer
          create_buffering_logger
        when :syslog
          create_syslog_logger
        else
          create_standard_logger
        end
      end

      def create_buffering_logger
        @buffer = StringIO.new
        Logger.new(@buffer).tap do |l|
          l.formatter = Formatter.new
          l.progname = progname
        end
      end

      def create_standard_logger
        @logfile ||= STDERR

        if @logfile.is_a?(String)
          logdir = File.dirname(@logfile)

          begin
            FileUtils.mkdir_p(logdir)
          rescue
            STDERR.puts "#{logdir} not writable, using STDERR for logging"
            @logfile = STDERR
          end
        end

        Logger.new(@logfile).tap do |l|
          l.formatter = Formatter.new
          l.progname = progname
        end
      end

      def create_syslog_logger
        begin
          require 'syslogger'
          Syslogger.new(progname, Syslog::LOG_PID, Syslog::LOG_LOCAL1)
        rescue LoadError
          self.logger = :logger
          self.error("Couldn't load syslogger gem, reverting to standard logger")
        end
      end

      class Formatter

        # YYYY:MM:DD HH:MM:SS.MS daemon_name(pid) level: message
        @format = "%s %s(%d) [%s] %s\n"

        class << self
          attr_accessor :format
        end

        def call(severity, time, progname, msg)
          self.class.format % [format_time( time ), progname, $$, severity, msg.to_s]
        end

        private

        def format_time(time)
          time.strftime("%Y-%m-%d %H:%M:%S.") + time.usec.to_s
        end
      end
    end
  end
end
