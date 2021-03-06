module AviGlitch

  # Base is the object that provides interfaces mainly used.
  # To glitch, and save file. The instance is returned through AviGlitch#open.
  #
  class Base

    # AviGlitch::Frames object generated from the +file+.
    attr_reader :frames
    # The input file (copied tempfile).
    attr_reader :file

    ##
    # Creates a new instance of AviGlitch::Base, open the file and 
    # make it ready to manipulate.
    # It requires +path+ as Pathname.
    def initialize path
      File.open(path, 'rb') do |f|
        # copy as tempfile
        @file = Tempfile.open 'aviglitch'
        f.rewind
        while d = f.read(1024) do
          @file.print d
        end
      end

      unless AviGlitch::Base.surely_formatted? @file
        raise 'Unsupported file passed.'
      end
      @frames = Frames.new @file
      # I believe Ruby's GC to close and remove the Tempfile..
    end

    ##
    # Outputs the glitched file to +path+, and close the file.
    def output path, do_file_close = true
      FileUtils.cp @file.path, path
      close if do_file_close
      self
    end

    ##
    # An explicit file close.
    def close
      @file.close!
    end

    ##
    # Glitches each frame data.
    # It is a convenient method to iterate each frame.
    #
    # The argument +target+ takes symbols listed below:
    # [<tt>:keyframe</tt> or <tt>:iframe</tt>]   select video key frames (aka I-frame)
    # [<tt>:deltaframe</tt> or <tt>:pframe</tt>] select video delta frames (difference frames)
    # [<tt>:videoframe</tt>] select both of keyframe and deltaframe
    # [<tt>:audioframe</tt>] select audio frames
    # [<tt>:all</tt>]        select all frames
    #
    # It also requires a block. In the block, you take the frame data
    # as a String parameter.
    # To modify the data, simply return a modified data.
    # It returns +self+
    def glitch target = :all, &block  # :yield: data
      @frames.each do |frame|
        if valid_target? target, frame
          frame.data = yield frame.data
        end
      end
      self
    end

    ##
    # Do glitch with index.
    def glitch_with_index target = :all, &block  # :yield: data, index
      i = 0
      @frames.each do |frame|
        if valid_target? target, frame
          frame.data = yield(frame.data, i)
          i += 1
        end
      end
      self
    end

    ##
    # Clears all (or in +range+) keyframes to deltaframes.
    # It's an alias for Frames#clear_keyframes!
    def clear_keyframes! range = nil
      self.frames.clear_keyframes! range
      self
    end

    ##
    # Check if it has keyframes.
    def has_keyframe?
      result = false
      self.frames.each do |f|
        if f.is_keyframe?
          result = true
          break
        end
      end
      result
    end

    ##
    # Swaps the frames with other Frames data.
    def frames= other
      raise TypeError unless other.kind_of?(Frames)
      @frames.clear
      @frames.concat other
    end

    alias_method :write, :output
    alias_method :has_keyframes?, :has_keyframe?

    def valid_target? target, frame #:nodoc:
      return true if target == :all
      begin
        frame.send "is_#{target.to_s.sub(/frames$/, 'frame')}?"
      rescue
        false
      end
    end

    private :valid_target?

    class << self
      ##
      # Checks if the +file+ is a correctly formetted AVI file.
      # +file+ can be String or Pathname or IO.
      def surely_formatted? file, debug = false
        answer = true
        is_io = file.respond_to?(:seek)  # Probably IO.
        file = File.open(file, 'rb') unless is_io
        begin
          file.seek 0, IO::SEEK_END
          eof = file.pos
          file.rewind
          unless file.read(4) == 'RIFF'
            answer = false
            warn 'RIFF sign is not found' if debug
          end
          len = file.read(4).unpack('V').first
          unless file.read(4) == 'AVI '
            answer = false
            warn 'AVI sign is not found' if debug
          end
          while file.read(4) =~ /^(?:LIST|JUNK)$/ do
            s = file.read(4).unpack('V').first
            file.pos += s
          end
          file.pos -= 4
          # we require idx1
          unless file.read(4) == 'idx1'
            answer = false
            warn 'idx1 is not found' if debug
          end
          s = file.read(4).unpack('V').first
          file.pos += s
        rescue => err
          warn err.message if debug
          answer = false
        ensure
          file.close unless is_io
        end
        answer
      end
    end
  end
end
