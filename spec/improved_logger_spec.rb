require File.dirname(__FILE__) + '/spec_helper'

include Madvertise::Logging

RSpec::Matchers.define :have_received_message do |expected|
  match do |actual|
    IO.readlines(actual).last.match(Regexp.new(expected))
  end
end

describe ImprovedLogger do

  before(:each) do
    @logfile = "#{ROOT}/log/spec.log"
    @logger = ImprovedLogger.new(@logfile)
    @logger.level = :debug
  end

  it "should be an IO object" do
    @logger.should be_a(IO)
  end

  it "should have a backend logger" do
    @logger.logger.should_not be_nil
  end

  it "should accept a different backend" do
    l = Logger.new('/dev/null')
    @logger.logger = l
    @logger.logger.should == l
  end

  it "should support reopening log files" do
    @logger.close

    FileUtils.rm(@logfile)

    @logger.info('Reopen')
    @logfile.should have_received_message("Reopen")
  end

  it "should be able to log to stdout as well" do
    @logger.copy_to_stdout = true
    $stdout.should_receive(:puts).with(/test/)

    @logger.debug "test"
    @logfile.should have_received_message("test")
  end

  it "should log debug level messages" do
    @logger.debug("Debug test")
    @logfile.should have_received_message(/\[DEBUG\].*Debug test/)
  end

  it "should log info level messages" do
    @logger.info("Info test")
    @logfile.should have_received_message(/\[INFO\].*Info test/)
  end

  it "should log info level messages with write and << compat methods" do
    @logger << "Info test1"
    @logfile.should have_received_message(/\[INFO\].*Info test1/)
    @logger.write("Info test2")
    @logfile.should have_received_message(/\[INFO\].*Info test2/)
  end

  it "should log warn level messages" do
    @logger.warn("Warn test")
    @logfile.should have_received_message(/\[WARN\].*Warn test/)
  end

  it "should log error level messages" do
    @logger.error("Err test")
    @logfile.should have_received_message(/\[ERROR\].*Err test/)
  end

  it "should log fatal level messages" do
    @logger.fatal("Fatal test")

    @logfile.should have_received_message(/\[FATAL\].*Fatal test/)
  end

  it "should log unknown level messages" do
    @logger.unknown("Unknown test")
    @logfile.should have_received_message(/\[ANY\].*Unknown test/)
  end

  it "should log the caller file and line number" do
    f = File.basename(__FILE__)
    l = __LINE__ + 2

    @logger.info("Caller test")
    @logfile.should have_received_message("#{f}:#{l}:")
  end

  it "should log exceptions with daemon traces" do
    fake_trace = [
                  "/home/jdoe/app/libexec/app.rb:1:in `foo'",
                  "/usr/lib/ruby/gems/1.8/gems/madvertise-logging-0.1.0/lib/madvertise/logging/improved_logger.rb:42: in `info'"
                 ]

    e = RuntimeError.new('Test error')
    e.set_backtrace(fake_trace)

    @logger.exception(e)
    @logfile.should have_received_message("EXCEPTION: Test error")
  end

  it "should log exceptions without framework traces" do
    fake_trace = [
                  "/home/jdoe/app/libexec/app.rb:1:in `foo'",
                  "/usr/lib/ruby/gems/1.8/gems/madvertise-logging-0.1.0/lib/madvertise/logging/improved_logger.rb:42: in `info'"
                 ]

    clean_trace = @logger.clean_trace(fake_trace)
    clean_trace.should include("/home/jdoe/app/libexec/app.rb:1:in `foo'")
    clean_trace.should_not include("/usr/lib/ruby/gems/1.8/gems/madvertise-logging-0.1.0/lib/madvertise/logging/improved_logger.rb:42: in `info'")
  end

  it "should not handle a backtrace if object is not an exception" do
    @logger.exception("not an exception object")
    @logfile.should_not have_received_message("EXCEPTION:")
  end

  it "should support silencing" do
    @logger.silence do |logger|
      logger.info "This should never be logged"
    end

    @logfile.should_not have_received_message("This should never be logged")

    @logger.info "This should be logged"
    @logfile.should have_received_message("This should be logged")
  end

  it "should not discard messages if silencer is disabled globally" do
    ImprovedLogger.silencer = false

    @logger.silence do |logger|
      logger.info "This should actually be logged"
    end

    @logfile.should have_received_message("This should actually be logged")

    ImprovedLogger.silencer = true
  end

  it "should support a token" do
    token = "3d5e27f7-b97c-4adc-b1fd-adf1bd4314e0"

    @logger.token = token
    @logger.info "This should include a token"
    @logfile.should have_received_message(token)

    @logger.token = nil
    @logger.info "This should not include a token"
    @logfile.should_not have_received_message(token)
  end

  it "should support save/restore on tokens" do
    token1 = "3d5e27f7-b97c-4adc-b1fd-adf1bd4314e0"
    token2 = "1bdef605-34b9-4ec7-9a1c-cb58efc8a635"

    obj = Object.new

    @logger.token = token1
    @logger.info "This should include token1"
    @logfile.should have_received_message(token1)

    @logger.save_token(obj)
    @logger.token = token2
    @logger.info "This should include token2"
    @logfile.should have_received_message(token2)

    @logger.restore_token(obj)
    @logger.info "This should include token1"
    @logfile.should have_received_message(token1)

    @logger.token = nil
    @logger.info "This should not include a token"
    @logfile.should_not have_received_message(token1)
    @logfile.should_not have_received_message(token2)
  end

  it "should fall back to stderr if logfile is not writable" do
    $stderr.should_receive(:puts).with(/not writable.*stderr/)

    @logfile = "/not/writable/spec.log"
    @logger = ImprovedLogger.new(@logfile)
    @logger.level = :debug

    $stderr.should_receive(:write).with(/test/)
    @logger.info "test"
  end

  it "should fallback to standard logger if syslogger gem is missing" do
    syslogger_paths = $:.select { |p| p.match(/gems\/.*syslogger-/) }
    $:.replace($: - syslogger_paths)

    $stderr.should_receive(:puts).with(/using stderr for logging/)
    $stderr.should_receive(:write).with(/reverting to standard logger/)
    @logger = ImprovedLogger.new(:syslog)
    @logger.logger.should be_instance_of(Logger)

    $:.replace($: + syslogger_paths)
  end

  context "should behave like write-only IO and" do
    it "should close on close_write" do
      @logger.should_receive(:close)
      @logger.close_write
    end

    it "should be in sync mode" do
      @logger.sync.should == true
    end

    it "should return self on flush" do
      @logger.flush.should == @logger
    end

    it "should return self on set_encoding" do
      @logger.set_encoding.should == @logger
    end

    it "should ne be a tty" do
      @logger.tty?.should == false
    end

    it "should support printf" do
      @logger.printf("%.2f %s", 1.12345, "foo")
      @logfile.should have_received_message("1.12 foo")
    end

    it "should support print" do
      $,, old = ' ', $,
      @logger.print("foo", "bar", 123, ["baz", 345])
      @logfile.should have_received_message("foo bar 123 baz 345")
      $, = old
    end

    it "should support puts" do
      @logger.puts("a", "b")
      @logfile.should have_received_message("b")
      @logger.puts(["c", "d"])
      @logfile.should have_received_message("b")
      @logger.puts(1, 2, 3)
      @logfile.should have_received_message("3")
    end

    it "should implement readbyte, readchar, readline" do
      {
        :readbyte => :getbyte,
        :readchar => :getc,
        :readline => :gets,
      }.each do |m, should|
        @logger.should_receive(should)
        lambda {
          @logger.send(m)
        }.should raise_error(IOError)
      end
    end

    it "should not implement closed?" do
      lambda {
        @logger.closed?
      }.should raise_error(NotImplementedError)
    end

    it "should not implement sync=" do
      lambda {
        @logger.sync = false
      }.should raise_error(NotImplementedError)
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
    ].each do |m|
      it "should raise IOError for method #{m}" do
        lambda {
          @logger.send(m)
        }.should raise_error(IOError)
      end
    end
  end

  context "buffer backend" do
    before(:each) do
      @logger = ImprovedLogger.new(:buffer)
      @logger.level = :debug
    end

    it "should support a buffered logger" do
      @logger.info "test"
      @logger.buffer.should match(/test/)
    end

    it "should not be in sync mode" do
      @logger.sync.should == false
    end
  end

  context "syslog backend" do
    before(:each) do
      @logger = ImprovedLogger.new(:syslog)
      @logger.level = :debug
    end

    it "should have a syslog backend" do
      @logger.logger.should be_instance_of(Syslogger)
    end

    it "should be in sync mode" do
      @logger.sync.should == true
    end
  end

end
