module JustHTML
  struct Tag
    enum Kind
      Start
      End
    end

    getter kind : Kind
    getter name : String
    getter attrs : Hash(String, String?)
    getter? self_closing : Bool

    def initialize(@kind : Kind, @name : String, @attrs : Hash(String, String?) = {} of String => String?, @self_closing : Bool = false)
    end

    def initialize(kind : Symbol, name : String, attrs : Hash(String, String?) = {} of String => String?, self_closing : Bool = false)
      @kind = kind == :start ? Kind::Start : Kind::End
      @name = name
      @attrs = attrs
      @self_closing = self_closing
    end

    def kind : Symbol
      @kind.start? ? :start : :end
    end

    def has_attribute?(attr : String) : Bool
      @attrs.has_key?(attr)
    end
  end

  struct Doctype
    getter name : String?
    getter public_id : String?
    getter system_id : String?
    getter? force_quirks : Bool

    def initialize(@name : String? = nil, @public_id : String? = nil, @system_id : String? = nil, @force_quirks : Bool = false)
    end
  end

  struct CommentToken
    getter data : String

    def initialize(@data : String)
    end
  end

  struct EOFToken
  end
end
