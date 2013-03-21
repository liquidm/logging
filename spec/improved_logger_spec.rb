require File.dirname(__FILE__) + '/spec_helper'

describe ImprovedLogger do

  let(:logger) { ImprovedLogger.new(:document) }

  before(:each) { logger.level = :debug }

  subject { logger.messages }

  ImprovedLogger.severities.keys.each do |level|
    describe level do
      before { logger.send(level, "testing #{level}") }
      let(:prefix) { level == :unknown ? "ANY" : level.to_s.upcase }
      it "logs #{level} messages" do
        subject.last[:message].should == "testing #{level}"
      end
    end
  end

  it "logs info level messages with <<" do
    logger << "Info test <<"
    subject.last[:message].should == "Info test <<"
  end

  it "logs info level messages with write" do
    logger.write("Info test write")
    subject.last[:message].should == "Info test write"
  end

  it "supports additional attributes" do
    logger.info("foo", key: "value", test: "with space")
    subject.last[:message].should == 'foo key=value test="with space"'
  end

  it "supports lazy-evaluation via blocks" do
    logger.debug { "debug message" }
    subject.last[:message].should == "debug message"
  end

  it "supports lazy-evaluation with attributes" do
    logger.debug { ["debug message", {key: "value"}] }
    subject.last[:message].should == "debug message key=value"
  end

  it "accepts a different backend" do
    l = Logger.new('/dev/null')
    logger.logger = l
    logger.logger.should == l
  end

  describe :log_caller do
    it "logs the caller file and line number" do
      f = __FILE__
      l = __LINE__ + 3

      logger.log_caller = true
      logger.info("Caller test")
      subject.last[:message].should == "Caller test file=#{f} line=#{l}"
    end

    it "does not log the caller file and line number" do
      f = File.basename(__FILE__)
      l = __LINE__ + 3

      logger.log_caller = false
      logger.info("Caller test")
      subject.last[:message].should_not == "Caller test file=#{f} line=#{l}"
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

    it "logs an exception object" do
      logger.exception(exc)
      subject.last[:message].should match(%r{exception class=RuntimeError reason=\"Test error\" message= backtrace=\"\['/home/jdoe/app/libexec/app\.rb:1:in `foo''\]\"})
    end

    it "logs an exception object and prefix" do
      logger.exception(exc, "app failed to foo")
      subject.last[:message].should match(%r{exception class=RuntimeError reason=\"Test error\" message=\"app failed to foo\" backtrace=\"\['/home/jdoe/app/libexec/app\.rb:1:in `foo''\]\"})
    end
  end

  describe :clean_trace do
    subject { logger.clean_trace(fake_trace) }
    it { should include("/home/jdoe/app/libexec/app.rb:1:in `foo'") }
    it { should_not include("/usr/lib/ruby/gems/1.8/gems/madvertise-logging-0.1.0/lib/madvertise/logging/improved_logger.rb:42: in `info'") }
  end

  it "should support silencing" do
    logger.silence do |logger|
      logger.info "This should never be logged"
    end

    subject.last.should be_nil
  end

  it "should not discard messages if silencer is disabled globally" do
    ImprovedLogger.silencer = false

    logger.silence do |logger|
      logger.info "This should actually be logged"
    end

    subject.last[:message].should == "This should actually be logged"

    ImprovedLogger.silencer = true
  end

  it "should support a token" do
    token = "3d5e27f7-b97c-4adc-b1fd-adf1bd4314e0"

    logger.token = token
    logger.info "This should include a token"
    subject.last[:message].should match(token)

    logger.token = nil
    logger.info "This should not include a token"
    subject.last[:message].should_not match(token)
  end

  it "should support save/restore on tokens" do
    token1 = "3d5e27f7-b97c-4adc-b1fd-adf1bd4314e0"
    token2 = "1bdef605-34b9-4ec7-9a1c-cb58efc8a635"

    obj = Object.new

    logger.token = token1
    logger.info "This should include token1"
    subject.last[:message].should match(token1)

    logger.save_token(obj)
    logger.token = token2
    logger.info "This should include token2"
    subject.last[:message].should match(token2)

    logger.restore_token(obj)
    logger.info "This should include token1"
    subject.last[:message].should match(token1)

    logger.token = nil
    logger.info "This should not include a token"
    subject.last[:message].should_not match(token1)
    subject.last[:message].should_not match(token2)
  end

  it "should fall back to stderr if logfile is not writable" do
    $stderr.should_receive(:write).with(/not writable.*STDERR/)

    @logfile = "/not/writable/spec.log"
    logger = ImprovedLogger.new(@logfile)
    logger.level = :debug

    $stderr.should_receive(:write).with(/test/)
    logger.info "test"
  end

  it "should fallback to standard logger if syslogger gem is missing" do
    syslogger_paths = $:.select { |p| p.match(/gems\/.*syslogger-/) }
    $:.replace($: - syslogger_paths)

    $stderr.should_receive(:write).with(/reverting to STDERR/)
    logger = ImprovedLogger.new(:syslog)
    logger.logger.should be_instance_of(Logger)

    $:.replace($: + syslogger_paths)
  end

  context "should behave like write-only IO and" do
    subject { logger }

    it { should be_a IO }
    its(:logger) { should_not be_nil }
    its(:flush) { should == logger }
    its(:set_encoding) { should == logger }
    its(:sync) { should == true }
    its(:tty?) { should == false }

    it "should close on close_write" do
      logger.should_receive(:close)
      logger.close_write
    end

    it "should not implement closed?" do
      expect { logger.closed? }.to raise_error(NotImplementedError)
    end

    it "should not implement sync=" do
      expect { logger.sync = false }.to raise_error(NotImplementedError)
    end

    it "should implement readbyte, readchar, readline" do
      {
        :readbyte => :getbyte,
        :readchar => :getc,
        :readline => :gets,
      }.each do |m, should|
        logger.should_receive(should)
        expect { logger.send(m) }.to raise_error(IOError)
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
        expect { logger.send(m) }.to raise_error(IOError)
      end
    end

    context "print functions" do
      subject { logger.messages }

      it "should support printf" do
        logger.printf("%.2f %s", 1.12345, "foo")
        subject.last[:message].should == "1.12 foo"
      end

      it "should support print" do
        $,, old = ' ', $,
        logger.print("foo", "bar", 123, ["baz", 345])
        subject.last[:message].should == "foo bar 123 baz 345"
        $, = old
      end

      it "should support puts" do
        logger.puts("a", "b")
        subject.last[:message].should == "b"
        logger.puts(["c", "d"])
        subject.last[:message].should == "d"
        logger.puts(1, 2, 3)
        subject.last[:message].should == "3"
      end
    end
  end

  context "buffer backend" do
    let(:logger) { ImprovedLogger.new(:buffer) }
    subject { logger }

    its(:sync) { should == false }

    it "should support a buffered logger" do
      logger.info "test"
      logger.buffer.should match(/test/)
    end
  end

  context "document backend" do
    let(:logger) { ImprovedLogger.new(:document) }

    before do
      @msg = "test"

      @now = Time.now
      Time.stub(:now).and_return(@now)

      @expected = {
        severity: Logger::INFO,
        time: @now.to_f,
        progname: "rspec",
        message: @msg
      }
    end

    it "should store all messages as documents" do
      logger.info(@msg)
      logger.messages.first.should == @expected
    end

    it "should add custom attributes" do
      attrs = {txid: 1234}
      logger.logger.attrs = attrs
      logger.info(@msg)
      logger.messages.first.should == attrs.merge(@expected)
    end

  end

  context "syslog backend" do
    let(:logger) { ImprovedLogger.new(:syslog) }
    subject { logger }
    its(:sync) { should == true }
    its(:logger) { should be_instance_of(Syslogger) }
  end

  context "unknown backend" do
    it "should raise for unknown backends " do
      expect { ImprovedLogger.new(:unknown_logger) }.to raise_error(RuntimeError)
    end
  end

end
