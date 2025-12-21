module JasperHTML
  class Error < Exception
  end

  class ParseError < Error
    getter code : String
    getter line : Int32?
    getter column : Int32?

    def initialize(@code : String, @line : Int32? = nil, @column : Int32? = nil, message : String? = nil)
      @message = message || @code
      super(@message)
    end

    def to_s(io : IO) : Nil
      if line = @line
        if column = @column
          io << "(#{line},#{column}): "
        end
      end
      io << @code
      if @message != @code
        io << " - " << @message
      end
    end
  end

  class SelectorError < Error
  end

  class EncodingError < Error
  end
end
