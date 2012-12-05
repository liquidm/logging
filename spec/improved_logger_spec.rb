require File.dirname(__FILE__) + '/spec_helper'

require 'tempfile'

include Madvertise::Logging

RSpec::Matchers.define :have_received_message do |expected|
  match do |actual|
    @last = IO.readlines(actual).last rescue nil
    @last ? @last.match(Regexp.new(expected)) : false
  end

  failure_message_for_should do |actual|
    "expected #{@last.inspect} to contain #{expected}"
  end

  failure_message_for_should_not do |actual|
    "expected #{@last.inspect} to not contain #{expected}"
  end
end

describe ImprovedLogger do

  before(:all) do
    Tempfile.new("spec").tap do |tmpfile|
      @logfile = tmpfile.path
      tmpfile.close
    end
  end

  after(:all) do
    File.unlink(@logfile) rescue nil
  end

  before(:each) do
    File.unlink(@logfile) rescue nil
    @logger = ImprovedLogger.new(@logfile)
    @logger.level = :debug
  end

  subject { @logger }

  it { should be_a IO }
  its(:logger) { should_not be_nil }

  ImprovedLogger.severities.keys.each do |level|
    describe level do
      subject { @logfile }
      before { @logger.send(level, "test") }
      let(:prefix) { level == :unknown ? "ANY" : level.to_s.upcase }
      it { should have_received_message(/\[#{prefix}\].*test/) }
    end
  end

  it "should log info level messages with write and << compat methods" do
    @logger << "Info test1"
    @logfile.should have_received_message(/\[INFO\].*Info test1/)
    @logger.write("Info test2")
    @logfile.should have_received_message(/\[INFO\].*Info test2/)
  end

  it "should support additional attributes" do
    @logger.info("foo", key: "value", test: "with space")
    @logfile.should have_received_message(/key=value test="with space"/)
  end

  it "should support lazy-evaluation via blocks" do
    @logger.debug { "debug message" }
    @logfile.should have_received_message(/debug message/)
    @logger.debug { ["debug message", {key: "value"}] }
    @logfile.should have_received_message(/debug message.*key=value/)
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

  describe :log_caller do
    it "should log the caller file and line number" do
      f = File.basename(__FILE__)
      l = __LINE__ + 3

      @logger.log_caller = true
      @logger.info("Caller test")
      @logfile.should have_received_message("#{f}:#{l}:")
    end

    it "should not log the caller file and line number" do
      f = File.basename(__FILE__)
      l = __LINE__ + 3

      @logger.log_caller = false
      @logger.info("Caller test")
      @logfile.should_not have_received_message("#{f}:#{l}:")
    end
  end

  let(:fake_trace) do
    [
      "/home/jdoe/app/libexec/app.rb:1:in `foo'",
      "/usr/lib/ruby/gems/1.8/gems/madvertise-logging-0.1.0/lib/madvertise/logging/improved_logger.rb:42: in `info'"
    ]
  end

  describe :exceptions do
    let(:exc) do
      RuntimeError.new('Test error').tap do |exc|
        exc.set_backtrace(fake_trace)
      end
    end

    subject { @logfile }

    context "with exception object" do
      before { @logger.exception(exc) }
      it { should have_received_message("exception class=RuntimeError reason=\"Test error\"") }
    end

    context "with exception object and prefix" do
      before { @logger.exception(exc, "app failed to foo") }
      it { should have_received_message("app failed to foo") }
    end
  end

  describe :clean_trace do
    subject { @logger.clean_trace(fake_trace) }
    it { should include("/home/jdoe/app/libexec/app.rb:1:in `foo'") }
    it { should_not include("/usr/lib/ruby/gems/1.8/gems/madvertise-logging-0.1.0/lib/madvertise/logging/improved_logger.rb:42: in `info'") }
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
    $stderr.should_receive(:write).with(/not writable.*STDERR/)

    @logfile = "/not/writable/spec.log"
    @logger = ImprovedLogger.new(@logfile)
    @logger.level = :debug

    $stderr.should_receive(:write).with(/test/)
    @logger.info "test"
  end

  it "should fallback to standard logger if syslogger gem is missing" do
    syslogger_paths = $:.select { |p| p.match(/gems\/.*syslogger-/) }
    $:.replace($: - syslogger_paths)

    $stderr.should_receive(:write).with(/reverting to STDERR/)
    @logger = ImprovedLogger.new(:syslog)
    @logger.logger.should be_instance_of(Logger)

    $:.replace($: + syslogger_paths)
  end

  context "should behave like write-only IO and" do
    it "should close on close_write" do
      @logger.should_receive(:close)
      @logger.close_write
    end

    its(:flush) { should == @logger }
    its(:set_encoding) { should == @logger }
    its(:sync) { should == true }
    its(:tty?) { should == false }

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
      @logfile.should have_received_message("d")
      @logger.puts(1, 2, 3)
      @logfile.should have_received_message("3")
    end

    it "should not implement closed?" do
      expect { @logger.closed? }.to raise_error(NotImplementedError)
    end

    it "should not implement sync=" do
      expect { @logger.sync = false }.to raise_error(NotImplementedError)
    end

    it "should implement readbyte, readchar, readline" do
      {
        :readbyte => :getbyte,
        :readchar => :getc,
        :readline => :gets,
      }.each do |m, should|
        @logger.should_receive(should)
        expect { @logger.send(m) }.to raise_error(IOError)
      end
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
        expect { @logger.send(m) }.to raise_error(IOError)
      end
    end
  end

  context "buffer backend" do
    before { @logger = ImprovedLogger.new(:buffer) }
    its(:sync) { should == false }

    it "should support a buffered logger" do
      @logger.info "test"
      @logger.buffer.should match(/test/)
    end
  end

  context "document backend" do
    before { @logger = ImprovedLogger.new(:document) }

    before do
      @msg = "test"

      @now = Time.now
      Time.stub(:now).and_return(@now)

      @expected = {
        severity: Logger::INFO,
        time: @now,
        progname: "rspec",
        message: @msg
      }
    end

    it "should store all messages as documents" do
      @logger.info(@msg)
      @logger.messages.first.should == @expected
    end

    it "should add custom attributes" do
      attrs = {txid: 1234}
      @logger.logger.attrs = attrs
      @logger.info(@msg)
      @logger.messages.first.should == attrs.merge(@expected)
    end

  end

  context "syslog backend" do
    before { @logger = ImprovedLogger.new(:syslog) }
    its(:sync) { should == true }
    its(:logger) { should be_instance_of(Syslogger) }
  end

  context "unknown backend" do
    it "should raise for unknown backends " do
      expect { ImprovedLogger.new(:unknown_logger) }.to raise_error(RuntimeError)
    end
  end

end
