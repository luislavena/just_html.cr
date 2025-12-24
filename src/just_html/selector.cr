module JustHTML
  # CSS Selector parser and matcher
  class Selector
    # Selector token types
    enum TokenType
      Type        # element name like "div"
      Id          # #id
      Class       # .class
      Attribute   # [attr], [attr=value], etc
      Universal   # *
      Combinator  # space, >, +, ~
      Comma       # ,
      EOF
    end

    # Attribute selector operators
    enum AttrOp
      Exists    # [attr]
      Equals    # [attr=value]
      Prefix    # [attr^=value]
      Suffix    # [attr$=value]
      Contains  # [attr*=value]
      Word      # [attr~=value]
      Hyphen    # [attr|=value]
    end

    # Combinator types
    enum CombinatorType
      Descendant      # space
      Child           # >
      NextSibling     # +
      SubsequentSibling # ~
    end

    # A simple selector (type, id, class, or attribute)
    abstract struct SimpleSelector
      abstract def matches?(element : Element) : Bool
    end

    struct TypeSelector < SimpleSelector
      getter name : String

      def initialize(@name : String)
      end

      def matches?(element : Element) : Bool
        @name == "*" || element.name == @name
      end
    end

    struct IdSelector < SimpleSelector
      getter id : String

      def initialize(@id : String)
      end

      def matches?(element : Element) : Bool
        element.id == @id
      end
    end

    struct ClassSelector < SimpleSelector
      getter class_name : String

      def initialize(@class_name : String)
      end

      def matches?(element : Element) : Bool
        element.has_class?(@class_name)
      end
    end

    struct AttributeSelector < SimpleSelector
      getter name : String
      getter op : AttrOp
      getter value : String?

      def initialize(@name : String, @op : AttrOp = AttrOp::Exists, @value : String? = nil)
      end

      def matches?(element : Element) : Bool
        attr_value = element[@name]

        case @op
        when .exists?
          element.has_attribute?(@name)
        when .equals?
          attr_value == @value
        when .prefix?
          attr_value.try(&.starts_with?(@value.not_nil!)) || false
        when .suffix?
          attr_value.try(&.ends_with?(@value.not_nil!)) || false
        when .contains?
          attr_value.try(&.includes?(@value.not_nil!)) || false
        when .word?
          if val = attr_value
            val.split.includes?(@value.not_nil!)
          else
            false
          end
        when .hyphen?
          if val = attr_value
            val == @value || val.starts_with?("#{@value}-")
          else
            false
          end
        else
          false
        end
      end
    end

    struct UniversalSelector < SimpleSelector
      def matches?(element : Element) : Bool
        true
      end
    end

    # Pseudo-class selectors
    struct FirstChildSelector < SimpleSelector
      def matches?(element : Element) : Bool
        parent = element.parent
        return false unless parent
        element_siblings = parent.children.select { |c| c.is_a?(Element) }
        element_siblings.first? == element
      end
    end

    struct LastChildSelector < SimpleSelector
      def matches?(element : Element) : Bool
        parent = element.parent
        return false unless parent
        element_siblings = parent.children.select { |c| c.is_a?(Element) }
        element_siblings.last? == element
      end
    end

    struct NthChildSelector < SimpleSelector
      getter a : Int32
      getter b : Int32

      def initialize(@a : Int32, @b : Int32)
      end

      def matches?(element : Element) : Bool
        parent = element.parent
        return false unless parent

        element_siblings = parent.children.select { |c| c.is_a?(Element) }
        index = element_siblings.index(element)
        return false unless index

        n = index + 1 # 1-based index

        if @a == 0
          n == @b
        else
          (n - @b) % @a == 0 && (n - @b) / @a >= 0
        end
      end
    end

    struct OnlyChildSelector < SimpleSelector
      def matches?(element : Element) : Bool
        parent = element.parent
        return false unless parent
        element_siblings = parent.children.select { |c| c.is_a?(Element) }
        element_siblings.size == 1
      end
    end

    struct EmptySelector < SimpleSelector
      def matches?(element : Element) : Bool
        element.children.none? { |c| c.is_a?(Element) || (c.is_a?(Text) && !c.as(Text).data.empty?) }
      end
    end

    struct NotSelector < SimpleSelector
      getter inner : CompoundSelector

      def initialize(@inner : CompoundSelector)
      end

      def matches?(element : Element) : Bool
        !@inner.matches?(element)
      end
    end

    # A compound selector is a sequence of simple selectors
    class CompoundSelector
      getter selectors : Array(SimpleSelector)

      def initialize
        @selectors = [] of SimpleSelector
      end

      def add(selector : SimpleSelector)
        @selectors << selector
      end

      def matches?(element : Element) : Bool
        @selectors.all?(&.matches?(element))
      end

      def empty? : Bool
        @selectors.empty?
      end
    end

    # A complex selector is a chain of compound selectors with combinators
    class ComplexSelector
      getter parts : Array(Tuple(CompoundSelector, CombinatorType?))

      def initialize
        @parts = [] of Tuple(CompoundSelector, CombinatorType?)
      end

      def add(compound : CompoundSelector, combinator : CombinatorType? = nil)
        @parts << {compound, combinator}
      end

      def matches?(element : Element) : Bool
        return false if @parts.empty?

        # Start from the rightmost selector (the subject)
        match_from_end(element, @parts.size - 1)
      end

      private def match_from_end(element : Element, index : Int32) : Bool
        return true if index < 0

        compound, combinator = @parts[index]
        return false unless compound.matches?(element)

        return true if index == 0

        prev_compound, prev_combinator = @parts[index - 1]
        combinator = prev_combinator

        return true if combinator.nil?

        case combinator
        when .descendant?
          # Any ancestor must match
          ancestor = element.parent
          while ancestor
            if ancestor.is_a?(Element)
              return true if match_from_end(ancestor, index - 1)
            end
            ancestor = ancestor.parent
          end
          false
        when .child?
          # Immediate parent must match
          parent = element.parent
          if parent.is_a?(Element)
            match_from_end(parent, index - 1)
          else
            false
          end
        when .next_sibling?
          # Previous sibling must match
          prev = previous_element_sibling(element)
          if prev
            match_from_end(prev, index - 1)
          else
            false
          end
        when .subsequent_sibling?
          # Any previous sibling must match
          prev = previous_element_sibling(element)
          while prev
            return true if match_from_end(prev, index - 1)
            prev = previous_element_sibling(prev)
          end
          false
        else
          # No combinator means this is the leftmost part
          true
        end
      end

      private def previous_element_sibling(element : Element) : Element?
        parent = element.parent
        return nil unless parent

        found_self = false
        parent.children.reverse_each do |child|
          if child == element
            found_self = true
            next
          end
          return child if found_self && child.is_a?(Element)
        end
        nil
      end
    end

    # A selector list (comma-separated selectors)
    class SelectorList
      getter selectors : Array(ComplexSelector)

      def initialize
        @selectors = [] of ComplexSelector
      end

      def add(selector : ComplexSelector)
        @selectors << selector
      end

      def matches?(element : Element) : Bool
        @selectors.any?(&.matches?(element))
      end
    end

    # Parser for CSS selectors
    class Parser
      @input : String
      @pos : Int32
      @length : Int32

      def initialize(@input : String)
        @pos = 0
        @length = @input.size
      end

      def parse : SelectorList?
        list = SelectorList.new
        skip_whitespace

        while @pos < @length
          selector = parse_complex_selector
          return nil unless selector
          list.add(selector)

          skip_whitespace
          if @pos < @length && current_char == ','
            @pos += 1
            skip_whitespace
          else
            break
          end
        end

        list.selectors.empty? ? nil : list
      end

      private def parse_complex_selector : ComplexSelector?
        selector = ComplexSelector.new
        combinator : CombinatorType? = nil

        loop do
          skip_whitespace
          break if @pos >= @length || current_char == ','

          compound = parse_compound_selector
          return nil if compound.nil? || compound.empty?

          selector.add(compound, combinator)

          # Look for combinator
          had_whitespace = skip_whitespace
          break if @pos >= @length || current_char == ','

          case current_char
          when '>'
            @pos += 1
            combinator = CombinatorType::Child
          when '+'
            @pos += 1
            combinator = CombinatorType::NextSibling
          when '~'
            @pos += 1
            combinator = CombinatorType::SubsequentSibling
          else
            if had_whitespace
              combinator = CombinatorType::Descendant
            else
              break
            end
          end
        end

        selector.parts.empty? ? nil : selector
      end

      private def parse_compound_selector : CompoundSelector?
        compound = CompoundSelector.new

        loop do
          break if @pos >= @length

          case current_char
          when '*'
            @pos += 1
            compound.add(UniversalSelector.new)
          when '.'
            @pos += 1
            name = parse_identifier
            return nil if name.empty?
            compound.add(ClassSelector.new(name))
          when '#'
            @pos += 1
            name = parse_identifier
            return nil if name.empty?
            compound.add(IdSelector.new(name))
          when '['
            attr = parse_attribute_selector
            return nil unless attr
            compound.add(attr)
          when ':'
            pseudo = parse_pseudo_class
            return nil unless pseudo
            compound.add(pseudo)
          when .ascii_letter?, '-', '_'
            name = parse_identifier
            compound.add(TypeSelector.new(name)) unless name.empty?
          else
            break
          end
        end

        compound
      end

      private def parse_pseudo_class : SimpleSelector?
        return nil unless current_char == ':'
        @pos += 1

        name = parse_identifier
        return nil if name.empty?

        case name.downcase
        when "first-child"
          FirstChildSelector.new
        when "last-child"
          LastChildSelector.new
        when "only-child"
          OnlyChildSelector.new
        when "empty"
          EmptySelector.new
        when "nth-child"
          parse_nth_child
        when "not"
          parse_not_selector
        else
          nil
        end
      end

      private def parse_nth_child : NthChildSelector?
        return nil unless @pos < @length && current_char == '('
        @pos += 1
        skip_whitespace

        a = 0
        b = 0

        if @pos < @length
          case
          when current_char == 'o' || current_char == 'O'
            # odd
            word = parse_identifier
            if word.downcase == "odd"
              a = 2
              b = 1
            else
              return nil
            end
          when current_char == 'e' || current_char == 'E'
            # even
            word = parse_identifier
            if word.downcase == "even"
              a = 2
              b = 0
            else
              return nil
            end
          when current_char.ascii_number? || current_char == '-' || current_char == '+'
            # Parse number or An+B
            num_str = String::Builder.new
            if current_char == '-' || current_char == '+'
              num_str << current_char
              @pos += 1
            end
            while @pos < @length && current_char.ascii_number?
              num_str << current_char
              @pos += 1
            end
            num_result = num_str.to_s
            if num_result.empty? || num_result == "-" || num_result == "+"
              return nil
            end
            b = num_result.to_i
            a = 0
          else
            return nil
          end
        end

        skip_whitespace
        return nil unless @pos < @length && current_char == ')'
        @pos += 1

        NthChildSelector.new(a, b)
      end

      private def parse_not_selector : NotSelector?
        return nil unless @pos < @length && current_char == '('
        @pos += 1
        skip_whitespace

        # Parse inner simple selectors (compound selector)
        inner = CompoundSelector.new
        loop do
          break if @pos >= @length || current_char == ')'

          case current_char
          when '.'
            @pos += 1
            name = parse_identifier
            return nil if name.empty?
            inner.add(ClassSelector.new(name))
          when '#'
            @pos += 1
            name = parse_identifier
            return nil if name.empty?
            inner.add(IdSelector.new(name))
          when '['
            attr = parse_attribute_selector
            return nil unless attr
            inner.add(attr)
          when .ascii_letter?, '-', '_'
            name = parse_identifier
            inner.add(TypeSelector.new(name)) unless name.empty?
          else
            break
          end
        end

        return nil if inner.empty?

        skip_whitespace
        return nil unless @pos < @length && current_char == ')'
        @pos += 1

        NotSelector.new(inner)
      end

      private def parse_attribute_selector : AttributeSelector?
        return nil unless current_char == '['
        @pos += 1
        skip_whitespace

        name = parse_identifier
        return nil if name.empty?

        skip_whitespace

        if @pos >= @length || current_char == ']'
          @pos += 1 if @pos < @length
          return AttributeSelector.new(name)
        end

        # Parse operator
        op = case current_char
             when '='
               @pos += 1
               AttrOp::Equals
             when '^'
               @pos += 1
               return nil unless @pos < @length && current_char == '='
               @pos += 1
               AttrOp::Prefix
             when '$'
               @pos += 1
               return nil unless @pos < @length && current_char == '='
               @pos += 1
               AttrOp::Suffix
             when '*'
               @pos += 1
               return nil unless @pos < @length && current_char == '='
               @pos += 1
               AttrOp::Contains
             when '~'
               @pos += 1
               return nil unless @pos < @length && current_char == '='
               @pos += 1
               AttrOp::Word
             when '|'
               @pos += 1
               return nil unless @pos < @length && current_char == '='
               @pos += 1
               AttrOp::Hyphen
             else
               return nil
             end

        skip_whitespace
        value = parse_value
        skip_whitespace

        return nil unless @pos < @length && current_char == ']'
        @pos += 1

        AttributeSelector.new(name, op, value)
      end

      private def parse_identifier : String
        start = @pos
        while @pos < @length
          c = current_char
          break unless c.ascii_letter? || c.ascii_number? || c == '-' || c == '_'
          @pos += 1
        end
        @input[start...@pos]
      end

      private def parse_value : String
        if @pos < @length && (current_char == '"' || current_char == '\'')
          quote = current_char
          @pos += 1
          start = @pos
          while @pos < @length && current_char != quote
            @pos += 1
          end
          value = @input[start...@pos]
          @pos += 1 if @pos < @length
          value
        else
          # Parse unquoted value - can contain more characters
          parse_unquoted_value
        end
      end

      private def parse_unquoted_value : String
        start = @pos
        while @pos < @length
          c = current_char
          # Stop at ] or whitespace
          break if c == ']' || c.ascii_whitespace?
          @pos += 1
        end
        @input[start...@pos]
      end

      private def skip_whitespace : Bool
        had_whitespace = false
        while @pos < @length && current_char.ascii_whitespace?
          had_whitespace = true
          @pos += 1
        end
        had_whitespace
      end

      private def current_char : Char
        @input[@pos]
      end
    end

    # Main entry point
    @list : SelectorList

    def initialize(@list : SelectorList)
    end

    def self.parse(selector : String) : Selector?
      parser = Parser.new(selector)
      if list = parser.parse
        new(list)
      end
    end

    def matches?(element : Element) : Bool
      @list.matches?(element)
    end

    # Query methods for elements
    def query(root : Node) : Element?
      find_first(root)
    end

    def query_all(root : Node) : Array(Element)
      results = [] of Element
      find_all(root, results)
      results
    end

    private def find_first(node : Node) : Element?
      case node
      when Element
        return node if matches?(node)
        node.children.each do |child|
          if result = find_first(child)
            return result
          end
        end
      when Document, DocumentFragment
        node.children.each do |child|
          if result = find_first(child)
            return result
          end
        end
      end
      nil
    end

    private def find_all(node : Node, results : Array(Element)) : Nil
      case node
      when Element
        results << node if matches?(node)
        node.children.each { |child| find_all(child, results) }
      when Document, DocumentFragment
        node.children.each { |child| find_all(child, results) }
      end
    end
  end
end
