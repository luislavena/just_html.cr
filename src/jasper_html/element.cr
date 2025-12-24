require "./node"

module JasperHTML
  class Element < Node
    getter name : String
    getter namespace : String
    property attrs : Hash(String, String?)

    def initialize(@name : String, @namespace : String = "html")
      super()
      @attrs = {} of String => String?
    end

    def initialize(@name : String, attrs, @namespace : String = "html")
      super()
      @attrs = {} of String => String?
      attrs.each do |key, value|
        @attrs[key] = value
      end
    end

    def [](attr : String) : String?
      @attrs[attr]?
    end

    def []=(attr : String, value : String?) : String?
      @attrs[attr] = value
    end

    def has_attribute?(attr : String) : Bool
      @attrs.has_key?(attr)
    end

    def id : String?
      @attrs["id"]?
    end

    def classes : Array(String)
      if class_attr = @attrs["class"]?
        class_attr.split
      else
        [] of String
      end
    end

    def has_class?(name : String) : Bool
      classes.includes?(name)
    end

    def clone(deep : Bool = false) : Element
      cloned = Element.new(@name, @attrs.dup, @namespace)
      if deep
        @children.each do |child|
          cloned.append_child(child.clone(deep: true))
        end
      end
      cloned
    end

    # Query for the first matching element using CSS selector
    def query_selector(selector_string : String) : Element?
      if selector = Selector.parse(selector_string)
        selector.query(self)
      end
    end

    # Query for all matching elements using CSS selector
    def query_selector_all(selector_string : String) : Array(Element)
      if selector = Selector.parse(selector_string)
        selector.query_all(self)
      else
        [] of Element
      end
    end
  end

  class Text < Node
    getter data : String

    def initialize(@data : String)
      super()
    end

    def name : String
      "#text"
    end

    def clone(deep : Bool = false) : Text
      Text.new(@data)
    end
  end

  class Comment < Node
    getter data : String

    def initialize(@data : String)
      super()
    end

    def name : String
      "#comment"
    end

    def clone(deep : Bool = false) : Comment
      Comment.new(@data)
    end
  end

  class DoctypeNode < Node
    getter doctype_name : String?
    getter public_id : String?
    getter system_id : String?

    def initialize(@doctype_name : String? = nil, @public_id : String? = nil, @system_id : String? = nil)
      super()
    end

    def name : String
      "!doctype"
    end

    def clone(deep : Bool = false) : DoctypeNode
      DoctypeNode.new(@doctype_name, @public_id, @system_id)
    end
  end

  class Document < Node
    property encoding : String?
    property errors : Array(ParseError)

    def initialize(@encoding : String? = nil)
      super()
      @errors = [] of ParseError
    end

    def name : String
      "#document"
    end

    def clone(deep : Bool = false) : Document
      cloned = Document.new(@encoding)
      if deep
        @children.each do |child|
          cloned.append_child(child.clone(deep: true))
        end
      end
      cloned
    end

    # Serialize document to HTML string
    def to_html : String
      Serializer.to_html(self)
    end

    # Extract text content from document
    def to_text : String
      Serializer.to_text(self)
    end

    # Query for the first matching element using CSS selector
    def query_selector(selector_string : String) : Element?
      if selector = Selector.parse(selector_string)
        selector.query(self)
      end
    end

    # Query for all matching elements using CSS selector
    def query_selector_all(selector_string : String) : Array(Element)
      if selector = Selector.parse(selector_string)
        selector.query_all(self)
      else
        [] of Element
      end
    end
  end

  class DocumentFragment < Node
    def initialize
      super()
    end

    def name : String
      "#document-fragment"
    end

    def clone(deep : Bool = false) : DocumentFragment
      cloned = DocumentFragment.new
      if deep
        @children.each do |child|
          cloned.append_child(child.clone(deep: true))
        end
      end
      cloned
    end

    # Serialize fragment to HTML string
    def to_html : String
      Serializer.to_html(self)
    end

    # Extract text content from fragment
    def to_text : String
      Serializer.to_text(self)
    end

    # Query for the first matching element using CSS selector
    def query_selector(selector_string : String) : Element?
      if selector = Selector.parse(selector_string)
        selector.query(self)
      end
    end

    # Query for all matching elements using CSS selector
    def query_selector_all(selector_string : String) : Array(Element)
      if selector = Selector.parse(selector_string)
        selector.query_all(self)
      else
        [] of Element
      end
    end
  end
end
