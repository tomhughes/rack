# frozen_string_literal: true

require_relative 'helper'

separate_testing do
  require_relative '../lib/rack/rewindable_input'
end

module RewindableTest
  extend Minitest::Spec::DSL

  def setup
    @rio = Rack::RewindableInput.new(@io)
  end

  it "be able to handle to read()" do
    @rio.read.must_equal "hello world"
  end

  it "be able to handle to read(nil)" do
    @rio.read(nil).must_equal "hello world"
  end

  it "be able to handle to read(length)" do
    @rio.read(1).must_equal "h"
  end

  it "be able to handle to read(length, buffer)" do
    buffer = "".dup
    result = @rio.read(1, buffer)
    result.must_equal "h"
    result.object_id.must_equal buffer.object_id
  end

  it "be able to handle to read(nil, buffer)" do
    buffer = "".dup
    result = @rio.read(nil, buffer)
    result.must_equal "hello world"
    result.object_id.must_equal buffer.object_id
  end

  it "rewind to the beginning when #rewind is called" do
    @rio.rewind
    @rio.read(1).must_equal 'h'
    @rio.rewind
    @rio.read.must_equal "hello world"
  end

  it "be able to handle gets" do
    @rio.gets.must_equal "hello world"
    @rio.rewind
    @rio.gets.must_equal "hello world"
  end

  it "be able to handle size" do
    @rio.size.must_equal "hello world".size
    @rio.size.must_equal "hello world".size
    @rio.rewind
    @rio.gets.must_equal "hello world"
  end

  it "be able to handle each" do
    array = []
    @rio.each do |data|
      array << data
    end
    array.must_equal ["hello world"]

    @rio.rewind
    array = []
    @rio.each do |data|
      array << data
    end
    array.must_equal ["hello world"]
  end

  it "not buffer into a Tempfile if no data has been read yet" do
    @rio.instance_variable_get(:@rewindable_io).must_be_nil
  end

  it "buffer into a Tempfile when data has been consumed for the first time" do
    @rio.read(1)
    tempfile = @rio.instance_variable_get(:@rewindable_io)
    tempfile.wont_be :nil?
    @rio.read(1)
    tempfile2 = @rio.instance_variable_get(:@rewindable_io)
    tempfile2.path.must_equal tempfile.path
  end

  it "close the underlying tempfile upon calling #close" do
    @rio.read(1)
    tempfile = @rio.instance_variable_get(:@rewindable_io)
    @rio.close
    tempfile.must_be :closed?
  end

  it "handle partial writes to tempfile" do
    def @rio.filesystem_has_posix_semantics?
      def @rewindable_io.write(buffer)
        super(buffer[0..1])
      end
      super
    end
    @rio.read(1)
    tempfile = @rio.instance_variable_get(:@rewindable_io)
    @rio.close
    tempfile.must_be :closed?
  end

  it "close the underlying tempfile upon calling #close when not using posix semantics" do
    def @rio.filesystem_has_posix_semantics?; false end
    @rio.read(1)
    tempfile = @rio.instance_variable_get(:@rewindable_io)
    @rio.close
    tempfile.must_be :closed?
  end

  it "be possible to call #close when no data has been buffered yet" do
    @rio.close.must_be_nil
  end

  it "be possible to call #close multiple times" do
    @rio.close.must_be_nil
    @rio.close.must_be_nil
  end

  after do
  @rio.close
  @rio = nil
  end
end

describe Rack::RewindableInput do
  describe "given an IO object that is already rewindable" do
    def setup
      @io = StringIO.new("hello world".dup)
      super
    end

    include RewindableTest
  end

  describe "given an IO object that is not rewindable" do
    def setup
      @io = StringIO.new("hello world".dup)
      @io.instance_eval do
        undef :rewind
      end
      super
    end

    include RewindableTest
  end

  describe "given an IO object whose rewind method raises Errno::ESPIPE" do
    def setup
      @io = StringIO.new("hello world".dup)
      def @io.rewind
        raise Errno::ESPIPE, "You can't rewind this!"
      end
      super
    end

    include RewindableTest
  end
end

describe Rack::RewindableInput::Middleware do
  it "wraps rack.input in RewindableInput" do
    app = proc{|env| [200, {}, [env['rack.input'].class.to_s]]}
    app.call('rack.input'=>StringIO.new(''))[2].must_equal ['StringIO']
    app = Rack::RewindableInput::Middleware.new(app)
    app.call('rack.input'=>StringIO.new(''))[2].must_equal ['Rack::RewindableInput']
  end

  it "preserves a nil rack.input" do
    app = proc{|env| [200, {}, [env['rack.input'].class.to_s]]}
    app.call('rack.input'=>nil)[2].must_equal ['NilClass']
    app = Rack::RewindableInput::Middleware.new(app)
    app.call('rack.input'=>nil)[2].must_equal ['NilClass']
  end
end
