module JasperHTML
  class TreeBuilder
    include TokenSink

    enum InsertionMode
      Initial
      BeforeHtml
      BeforeHead
      InHead
      InHeadNoscript
      AfterHead
      InBody
      Text
      InTable
      InTableText
      InCaption
      InColumnGroup
      InTableBody
      InRow
      InCell
      InSelect
      InSelectInTable
      InTemplate
      AfterBody
      InFrameset
      AfterFrameset
      AfterAfterBody
      AfterAfterFrameset
    end

    getter document : Document
    getter errors : Array(ParseError)

    @mode : InsertionMode
    @original_mode : InsertionMode?
    @open_elements : Array(Element)
    @head_element : Element?
    @form_element : Element?
    @frameset_ok : Bool
    @ignore_lf : Bool
    @tokenizer : Tokenizer?

    def initialize(@collect_errors : Bool = false)
      @document = Document.new
      @errors = [] of ParseError
      @mode = InsertionMode::Initial
      @original_mode = nil
      @open_elements = [] of Element
      @head_element = nil
      @form_element = nil
      @frameset_ok = true
      @ignore_lf = false
      @tokenizer = nil
    end

    def self.parse(html : String, collect_errors : Bool = false) : Document
      builder = new(collect_errors)
      tokenizer = Tokenizer.new(builder, collect_errors)
      builder.set_tokenizer(tokenizer)
      tokenizer.run(html)
      builder.document
    end

    def set_tokenizer(tokenizer : Tokenizer) : Nil
      @tokenizer = tokenizer
    end

    # TokenSink implementation

    def process_tag(tag : Tag) : Nil
      if tag.kind == :start
        process_start_tag(tag)
      else
        process_end_tag(tag)
      end
    end

    def process_comment(comment : CommentToken) : Nil
      node = Comment.new(comment.data)
      insert_node(node)
    end

    def process_doctype(doctype : Doctype) : Nil
      node = DoctypeNode.new(doctype.name, doctype.public_id, doctype.system_id)
      @document.append_child(node)

      # Move to BeforeHtml mode
      @mode = InsertionMode::BeforeHtml
    end

    def process_characters(data : String) : Nil
      return if data.empty?

      # Handle ignore_lf flag
      if @ignore_lf && data[0] == '\n'
        data = data[1..]
        return if data.empty?
      end
      @ignore_lf = false

      # Insert text into current element
      if current = current_node
        # If the last child is a text node, append to it
        if last = current.children.last?
          if last.is_a?(Text)
            # Create a new text node with combined data
            combined = last.as(Text).data + data
            current.children.pop
            current.append_child(Text.new(combined))
            return
          end
        end
        current.append_child(Text.new(data))
      else
        # Text before any element - ensure html/body exist
        ensure_body_context
        if current = current_node
          current.append_child(Text.new(data))
        end
      end
    end

    def process_eof : Nil
      # Close any remaining open elements
      @open_elements.clear
    end

    # Tag processing

    private def process_start_tag(tag : Tag) : Nil
      name = tag.name

      case @mode
      when .initial?
        # Skip whitespace, process anything else
        @mode = InsertionMode::BeforeHtml
        process_start_tag(tag)
      when .before_html?
        if name == "html"
          element = create_element(tag)
          @document.append_child(element)
          @open_elements << element
          @mode = InsertionMode::BeforeHead
        else
          # Insert implicit html element
          html = Element.new("html")
          @document.append_child(html)
          @open_elements << html
          @mode = InsertionMode::BeforeHead
          process_start_tag(tag)
        end
      when .before_head?
        if name == "head"
          element = create_element(tag)
          insert_element(element)
          @head_element = element
          @mode = InsertionMode::InHead
        elsif name == "html"
          # Add attributes to existing html element
          if html = @open_elements.first?
            tag.attrs.each do |k, v|
              html[k] = v unless html.has_attribute?(k)
            end
          end
        else
          # Insert implicit head
          head = Element.new("head")
          insert_element(head)
          @head_element = head
          @open_elements.pop # Pop head immediately
          @mode = InsertionMode::AfterHead
          process_start_tag(tag)
        end
      when .in_head?
        case name
        when "title", "style", "script", "noscript"
          element = create_element(tag)
          insert_element(element)
          if name == "script" || name == "style"
            @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
          end
          @original_mode = @mode
          @mode = InsertionMode::Text
        when "meta", "link", "base", "basefont", "bgsound"
          element = create_element(tag)
          insert_element(element)
          @open_elements.pop # Void element
        when "head"
          # Ignore duplicate head
        else
          # Pop head, move to after head
          @open_elements.pop if @open_elements.last?.try(&.name) == "head"
          @mode = InsertionMode::AfterHead
          process_start_tag(tag)
        end
      when .after_head?
        if name == "body"
          element = create_element(tag)
          insert_element(element)
          @frameset_ok = false
          @mode = InsertionMode::InBody
        elsif name == "frameset"
          element = create_element(tag)
          insert_element(element)
          @mode = InsertionMode::InFrameset
        elsif name == "html"
          # Add attributes to existing html
          if html = @open_elements.first?
            tag.attrs.each do |k, v|
              html[k] = v unless html.has_attribute?(k)
            end
          end
        elsif {"base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"}.includes?(name)
          # These go in head
          if head = @head_element
            @open_elements << head
            process_start_tag(tag)
            @open_elements.delete(head)
          end
        else
          # Insert implicit body
          body = Element.new("body")
          insert_element(body)
          @mode = InsertionMode::InBody
          process_start_tag(tag)
        end
      when .in_body?
        process_in_body_start_tag(tag)
      when .text?
        # Should not receive start tags in text mode
      when .after_body?
        if name == "html"
          # Add attributes
          if html = @open_elements.first?
            tag.attrs.each do |k, v|
              html[k] = v unless html.has_attribute?(k)
            end
          end
        else
          @mode = InsertionMode::InBody
          process_start_tag(tag)
        end
      else
        # Default: insert the element
        element = create_element(tag)
        insert_element(element)
        if Constants::VOID_ELEMENTS.includes?(name)
          @open_elements.pop
        end
      end
    end

    private def process_in_body_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "html"
        if html = @open_elements.first?
          tag.attrs.each do |k, v|
            html[k] = v unless html.has_attribute?(k)
          end
        end
      when "body"
        if @open_elements.size >= 2
          body = @open_elements[1]?
          if body && body.name == "body"
            tag.attrs.each do |k, v|
              body[k] = v unless body.has_attribute?(k)
            end
          end
        end
      when "address", "article", "aside", "blockquote", "center", "details", "dialog",
           "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header",
           "hgroup", "main", "menu", "nav", "ol", "p", "search", "section", "summary", "ul"
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
      when "h1", "h2", "h3", "h4", "h5", "h6"
        close_p_if_in_button_scope
        # Close any open heading
        if current = current_node
          if {"h1", "h2", "h3", "h4", "h5", "h6"}.includes?(current.name)
            @open_elements.pop
          end
        end
        element = create_element(tag)
        insert_element(element)
      when "pre", "listing"
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
        @ignore_lf = true
        @frameset_ok = false
      when "form"
        if @form_element.nil?
          close_p_if_in_button_scope
          element = create_element(tag)
          insert_element(element)
          @form_element = element
        end
      when "li"
        @frameset_ok = false
        # Close any open li
        @open_elements.reverse_each do |el|
          if el.name == "li"
            generate_implied_end_tags("li")
            pop_until("li")
            break
          end
          break if Constants::SPECIAL_ELEMENTS.includes?(el.name) && !{"address", "div", "p"}.includes?(el.name)
        end
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
      when "dd", "dt"
        @frameset_ok = false
        @open_elements.reverse_each do |el|
          if el.name == "dd" || el.name == "dt"
            generate_implied_end_tags(el.name)
            pop_until(el.name)
            break
          end
          break if Constants::SPECIAL_ELEMENTS.includes?(el.name) && !{"address", "div", "p"}.includes?(el.name)
        end
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
      when "a"
        # Check for existing a in active formatting elements (simplified)
        element = create_element(tag)
        insert_element(element)
      when "b", "big", "code", "em", "font", "i", "s", "small", "strike", "strong", "tt", "u"
        element = create_element(tag)
        insert_element(element)
      when "nobr"
        element = create_element(tag)
        insert_element(element)
      when "applet", "marquee", "object"
        element = create_element(tag)
        insert_element(element)
      when "table"
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
        @frameset_ok = false
        @mode = InsertionMode::InTable
      when "area", "br", "embed", "img", "keygen", "wbr"
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop # Void element
        @frameset_ok = false
      when "input"
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop # Void element
        # Only set frameset_ok to false if not hidden
        if tag.attrs["type"]?.try(&.downcase) != "hidden"
          @frameset_ok = false
        end
      when "param", "source", "track"
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop # Void element
      when "hr"
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop # Void element
        @frameset_ok = false
      when "image"
        # Parse error, treat as img
        new_tag = Tag.new(:start, "img", tag.attrs, tag.self_closing?)
        process_in_body_start_tag(new_tag)
      when "textarea"
        element = create_element(tag)
        insert_element(element)
        @ignore_lf = true
        @tokenizer.try(&.set_state(Tokenizer::State::RCDATA))
        @original_mode = @mode
        @frameset_ok = false
        @mode = InsertionMode::Text
      when "xmp"
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
        @frameset_ok = false
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
        @original_mode = @mode
        @mode = InsertionMode::Text
      when "iframe"
        @frameset_ok = false
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
        @original_mode = @mode
        @mode = InsertionMode::Text
      when "noembed"
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
        @original_mode = @mode
        @mode = InsertionMode::Text
      when "select"
        element = create_element(tag)
        insert_element(element)
        @frameset_ok = false
        @mode = InsertionMode::InSelect
      when "optgroup", "option"
        if current_node.try(&.name) == "option"
          @open_elements.pop
        end
        element = create_element(tag)
        insert_element(element)
      when "span"
        element = create_element(tag)
        insert_element(element)
      else
        # Default: insert the element
        element = create_element(tag)
        insert_element(element)
        if Constants::VOID_ELEMENTS.includes?(name)
          @open_elements.pop
        end
      end
    end

    private def process_end_tag(tag : Tag) : Nil
      name = tag.name

      case @mode
      when .initial?, .before_html?
        # Ignore
      when .before_head?
        if name == "head" || name == "body" || name == "html" || name == "br"
          # Insert implicit head, then reprocess
          head = Element.new("head")
          insert_element(head)
          @head_element = head
          @open_elements.pop
          @mode = InsertionMode::AfterHead
          process_end_tag(tag)
        end
      when .in_head?
        if name == "head"
          @open_elements.pop
          @mode = InsertionMode::AfterHead
        elsif name == "body" || name == "html" || name == "br"
          @open_elements.pop if @open_elements.last?.try(&.name) == "head"
          @mode = InsertionMode::AfterHead
          process_end_tag(tag)
        end
      when .after_head?
        if name == "body" || name == "html" || name == "br"
          body = Element.new("body")
          insert_element(body)
          @mode = InsertionMode::InBody
          process_end_tag(tag)
        end
      when .in_body?
        process_in_body_end_tag(tag)
      when .text?
        if name == "script"
          @open_elements.pop
        else
          @open_elements.pop
        end
        @mode = @original_mode || InsertionMode::InBody
      when .after_body?
        if name == "html"
          @mode = InsertionMode::AfterAfterBody
        else
          @mode = InsertionMode::InBody
          process_end_tag(tag)
        end
      else
        # Default behavior
        pop_until(name)
      end
    end

    private def process_in_body_end_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "body"
        if has_element_in_scope?("body")
          @mode = InsertionMode::AfterBody
        end
      when "html"
        if has_element_in_scope?("body")
          @mode = InsertionMode::AfterBody
          process_end_tag(tag)
        end
      when "address", "article", "aside", "blockquote", "button", "center", "details",
           "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer",
           "header", "hgroup", "listing", "main", "menu", "nav", "ol", "pre", "search",
           "section", "summary", "ul"
        if has_element_in_scope?(name)
          generate_implied_end_tags
          pop_until(name)
        end
      when "form"
        form = @form_element
        @form_element = nil
        if form && has_element_in_scope?("form")
          generate_implied_end_tags
          @open_elements.delete(form)
        end
      when "p"
        if has_element_in_button_scope?("p")
          generate_implied_end_tags("p")
          pop_until("p")
        else
          # Insert implicit p
          p = Element.new("p")
          insert_element(p)
          @open_elements.pop
        end
      when "li"
        if has_element_in_list_scope?("li")
          generate_implied_end_tags("li")
          pop_until("li")
        end
      when "dd", "dt"
        if has_element_in_scope?(name)
          generate_implied_end_tags(name)
          pop_until(name)
        end
      when "h1", "h2", "h3", "h4", "h5", "h6"
        if has_heading_in_scope?
          generate_implied_end_tags
          # Pop until any heading
          while el = @open_elements.pop?
            break if {"h1", "h2", "h3", "h4", "h5", "h6"}.includes?(el.name)
          end
        end
      when "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u"
        # Adoption agency algorithm (simplified)
        8.times do
          break unless @open_elements.any? { |el| el.name == name }
          pop_until(name)
        end
      when "applet", "marquee", "object"
        if has_element_in_scope?(name)
          generate_implied_end_tags
          pop_until(name)
        end
      when "br"
        # Parse error, treat as start tag
        process_start_tag(Tag.new(:start, "br"))
      else
        # Any other end tag
        (@open_elements.size - 1).downto(0) do |i|
          el = @open_elements[i]
          if el.name == name
            generate_implied_end_tags(name)
            # Pop up to and including the matched element
            (@open_elements.size - i).times { @open_elements.pop }
            break
          end
          break if Constants::SPECIAL_ELEMENTS.includes?(el.name)
        end
      end
    end

    # Helper methods

    private def create_element(tag : Tag) : Element
      Element.new(tag.name, tag.attrs)
    end

    private def insert_element(element : Element) : Nil
      if current = current_node
        current.append_child(element)
      else
        @document.append_child(element)
      end
      @open_elements << element
    end

    private def insert_node(node : Node) : Nil
      if current = current_node
        current.append_child(node)
      else
        @document.append_child(node)
      end
    end

    private def current_node : Element?
      @open_elements.last?
    end

    private def ensure_body_context : Nil
      return unless @open_elements.empty?

      html = Element.new("html")
      @document.append_child(html)
      @open_elements << html

      head = Element.new("head")
      html.append_child(head)
      @head_element = head

      body = Element.new("body")
      html.append_child(body)
      @open_elements << body
      @mode = InsertionMode::InBody
    end

    private def close_p_if_in_button_scope : Nil
      if has_element_in_button_scope?("p")
        generate_implied_end_tags("p")
        pop_until("p")
      end
    end

    private def generate_implied_end_tags(except : String? = nil) : Nil
      implied = {"dd", "dt", "li", "optgroup", "option", "p", "rb", "rp", "rt", "rtc"}
      while el = @open_elements.last?
        break if el.name == except
        break unless implied.includes?(el.name)
        @open_elements.pop
      end
    end

    private def pop_until(name : String) : Nil
      while el = @open_elements.pop?
        break if el.name == name
      end
    end

    private def has_element_in_scope?(name : String) : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        return false if scope_terminators.includes?(el.name)
      end
      false
    end

    private def has_element_in_button_scope?(name : String) : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "button"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        return false if scope_terminators.includes?(el.name)
      end
      false
    end

    private def has_element_in_list_scope?(name : String) : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "ol", "ul"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        return false if scope_terminators.includes?(el.name)
      end
      false
    end

    private def has_heading_in_scope? : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template"}
      @open_elements.reverse_each do |el|
        return true if {"h1", "h2", "h3", "h4", "h5", "h6"}.includes?(el.name)
        return false if scope_terminators.includes?(el.name)
      end
      false
    end
  end
end
