require "./node"

module JustHTML
  class Element < Node
    getter name : String
    getter namespace : String
    property attrs : Hash(String, String?)
    property template_contents : DocumentFragment?

    def initialize(@name : String, @namespace : String = "html")
      super()
      @attrs = {} of String => String?
      @template_contents = @name == "template" ? DocumentFragment.new : nil
    end

    def initialize(@name : String, attrs, @namespace : String = "html")
      super()
      @attrs = {} of String => String?
      attrs.each do |key, value|
        @attrs[key] = value
      end
      @template_contents = @name == "template" ? DocumentFragment.new : nil
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

    # Returns the text content of this element and its descendants
    def text_content : String
      builder = String::Builder.new
      Element.collect_text_from(self, builder)
      builder.to_s
    end

    protected def self.collect_text_from(element : Element, builder : String::Builder) : Nil
      element.children.each do |child|
        case child
        when Text
          builder << child.data
        when Element
          collect_text_from(child, builder)
        end
      end
    end

    # Returns the HTML content of this element's children
    def inner_html : String
      builder = String::Builder.new
      @children.each do |child|
        Serializer.serialize_child(child, builder)
      end
      builder.to_s
    end

    # Returns the HTML of this element including itself
    def outer_html : String
      Serializer.to_html(self)
    end

    # Returns a list of ancestor elements, from parent to root
    def ancestors : Array(Element)
      result = [] of Element
      current = @parent
      while current
        result << current if current.is_a?(Element)
        current = current.parent
      end
      result
    end

    # Returns the next sibling element, skipping text and comment nodes
    def next_element_sibling : Element?
      parent = @parent
      return nil unless parent

      found_self = false
      parent.children.each do |sibling|
        if sibling == self
          found_self = true
          next
        end
        return sibling if found_self && sibling.is_a?(Element)
      end
      nil
    end

    # Returns the previous sibling element, skipping text and comment nodes
    def previous_element_sibling : Element?
      parent = @parent
      return nil unless parent

      previous : Element? = nil
      parent.children.each do |sibling|
        return previous if sibling == self
        previous = sibling if sibling.is_a?(Element)
      end
      nil
    end

    def clone(deep : Bool = false) : Element
      cloned = Element.new(@name, @attrs.dup, @namespace)
      if deep
        @children.each do |child|
          cloned.append_child(child.clone(deep: true))
        end
        if @template_contents && cloned.template_contents
          @template_contents.not_nil!.children.each do |child|
            cloned.template_contents.not_nil!.append_child(child.clone(deep: true))
          end
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
