require File.dirname(__FILE__) + '/spec_helper'

include Liquid::Logging

describe MultiLogger do

  before(:each) do
    @logger = ImprovedLogger.new
    @logger.level = :debug
    @ml = MultiLogger.new(@logger)
  end

  it "should support attach/detach of loggers" do
    buflog = ImprovedLogger.new(:buffer)
    @ml.attach(buflog)

    $stderr.should_receive(:write).with(/test1/)
    @ml.info("test1")
    buflog.buffer.should match(/test1/)

    @ml.detach(buflog)

    $stderr.should_receive(:write).with(/test2/)
    @ml.info("test2")
    buflog.buffer.should_not match(/test2/)
  end
end
