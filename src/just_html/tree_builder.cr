module JustHTML
  # Marker class for active formatting elements list scope boundaries
  class ActiveFormattingMarker
  end

  # Union type for active formatting elements list entries
  alias ActiveFormattingEntry = Element | ActiveFormattingMarker

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

    # Formatting elements that use the adoption agency algorithm
    FORMATTING_ELEMENTS = {"a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u"}

    getter document : Document
    getter errors : Array(ParseError)

    @mode : InsertionMode
    @original_mode : InsertionMode?
    @open_elements : Array(Element)
    @active_formatting_elements : Array(ActiveFormattingEntry)
    @template_insertion_modes : Array(InsertionMode)
    @head_element : Element?
    @form_element : Element?
    @frameset_ok : Bool
    @ignore_lf : Bool
    @tokenizer : Tokenizer?
    @foster_parenting : Bool

    def initialize(@collect_errors : Bool = false)
      @document = Document.new
      @errors = [] of ParseError
      @mode = InsertionMode::Initial
      @original_mode = nil
      @open_elements = [] of Element
      @active_formatting_elements = [] of ActiveFormattingEntry
      @template_insertion_modes = [] of InsertionMode
      @head_element = nil
      @form_element = nil
      @frameset_ok = true
      @ignore_lf = false
      @tokenizer = nil
      @foster_parenting = false
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
      # In foreign content (SVG/MathML), CDATA sections are tokenized as comments
      # with data like "[CDATA[content]]". Convert these to text nodes.
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "math")
        if comment.data.starts_with?("[CDATA[") && comment.data.ends_with?("]]")
          cdata_content = comment.data[7..-3]
          # Normalize line endings: CRLF -> LF, CR -> LF
          cdata_content = cdata_content.gsub("\r\n", "\n").gsub("\r", "\n")
          node = Text.new(cdata_content)
          insert_node(node)
          return
        end
      end

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

      # Handle whitespace in certain modes
      case @mode
      when .initial?, .before_html?, .before_head?, .after_head?
        # Skip leading whitespace in these modes
        data = data.lstrip
        return if data.empty?
        # If non-whitespace, need to ensure proper context
        if @mode.before_head? || @mode.after_head?
          ensure_body_context
        end
      when .in_body?
        # Reconstruct active formatting elements when in body mode
        reconstruct_active_formatting_elements
      when .in_table?, .in_table_body?, .in_row?
        # In table modes, characters need special handling
        # According to the spec, we should process using "in body" rules but with foster parenting
        @foster_parenting = true
        reconstruct_active_formatting_elements
        insert_text(data)
        @foster_parenting = false
        return
      when .in_cell?, .in_caption?
        # In cell/caption, process normally using in-body rules
        reconstruct_active_formatting_elements
      when .in_template?
        # In template mode, process as in body
        reconstruct_active_formatting_elements
      end

      # Insert text into current element
      insert_text(data)
    end

    private def insert_text(data : String) : Nil
      return if data.empty?

      if current = current_node
        # Check if foster parenting is needed for text
        if @foster_parenting && in_table_context?
          text_node = Text.new(data)
          foster_parent_node(text_node)
          return
        end

        # Determine the target container (template_contents or regular children)
        if current.name == "template" && (template_contents = current.template_contents)
          target = template_contents
        else
          target = current
        end

        # If the last child is a text node, append to it
        if last = target.children.last?
          if last.is_a?(Text)
            # Create a new text node with combined data
            combined = last.as(Text).data + data
            target.children.pop
            target.append_child(Text.new(combined))
            return
          end
        end
        target.append_child(Text.new(data))
      else
        # Text before any element - ensure html/body exist
        ensure_body_context
        if current = current_node
          current.append_child(Text.new(data))
        end
      end
    end

    private def insert_table_text(data : String) : Nil
      # Insert text for table context - may need foster parenting
      if current = current_node
        if {"table", "tbody", "tfoot", "thead", "tr"}.includes?(current.name)
          # Text needs to be foster parented
          text_node = Text.new(data)
          foster_parent_node(text_node)
        else
          current.append_child(Text.new(data))
        end
      end
    end

    def process_eof : Nil
      # Process EOF through mode-specific handling to ensure required elements exist
      loop do
        case @mode
        when .initial?
          @mode = InsertionMode::BeforeHtml
        when .before_html?
          # Create implicit html element
          html = Element.new("html")
          @document.append_child(html)
          @open_elements << html
          @mode = InsertionMode::BeforeHead
        when .before_head?
          # Create implicit head element
          head = Element.new("head")
          insert_element(head)
          @head_element = head
          @mode = InsertionMode::InHead
        when .in_head?, .in_head_noscript?
          # Pop head and move to AfterHead
          @open_elements.pop if @open_elements.last?.try(&.name) == "head"
          @mode = InsertionMode::AfterHead
        when .after_head?
          # Create implicit body element
          body = Element.new("body")
          insert_element(body)
          @mode = InsertionMode::InBody
        when .text?
          # Pop current element, return to original mode
          @open_elements.pop
          @mode = @original_mode || InsertionMode::InBody
        when .in_template?
          # Handle EOF in template - pop until template
          if @open_elements.any? { |el| el.name == "template" }
            pop_until("template")
            clear_active_formatting_elements_to_last_marker
            @template_insertion_modes.pop if @template_insertion_modes.size > 0
            reset_insertion_mode
          else
            break
          end
        when .in_body?, .in_table?, .in_table_body?, .in_row?, .in_cell?,
             .in_select?, .in_select_in_table?, .in_column_group?, .in_caption?,
             .in_frameset?, .after_frameset?, .after_after_frameset?
          # Transition to after body for final cleanup
          @mode = InsertionMode::AfterBody
        when .after_body?
          @mode = InsertionMode::AfterAfterBody
        when .after_after_body?
          # Final state - we're done
          break
        else
          break
        end
      end
      # Clear the stack at the end
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
        when "title", "style", "script", "noscript", "noframes"
          element = create_element(tag)
          insert_element(element)
          if name == "script" || name == "style" || name == "noframes"
            @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
          end
          @original_mode = @mode
          @mode = InsertionMode::Text
        when "meta", "link", "base", "basefont", "bgsound"
          element = create_element(tag)
          insert_element(element)
          @open_elements.pop # Void element
        when "template"
          element = create_element(tag)
          insert_element(element)
          push_onto_active_formatting_elements(ActiveFormattingMarker.new)
          @frameset_ok = false
          @mode = InsertionMode::InTemplate
          @template_insertion_modes << InsertionMode::InTemplate
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
          # These go in head - switch to InHead mode temporarily
          if head = @head_element
            @open_elements << head
            @mode = InsertionMode::InHead
            process_start_tag(tag)
            @open_elements.delete(head)
            # Only reset mode if we're still in InHead (script/style go to Text mode)
            @mode = InsertionMode::AfterHead if @mode.in_head?
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
      when .in_table?
        process_in_table_start_tag(tag)
      when .in_table_body?
        process_in_table_body_start_tag(tag)
      when .in_row?
        process_in_row_start_tag(tag)
      when .in_cell?
        process_in_cell_start_tag(tag)
      when .in_template?
        process_in_template_start_tag(tag)
      else
        # Default: insert the element
        element = create_element(tag)
        insert_element(element)
        if Constants::VOID_ELEMENTS.includes?(name)
          @open_elements.pop
        end
      end
    end

    private def process_in_template_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "template"
        # Process using in head insertion mode
        element = create_element(tag)
        insert_element(element)
        push_onto_active_formatting_elements(ActiveFormattingMarker.new)
        @frameset_ok = false
        @mode = InsertionMode::InTemplate
        @template_insertion_modes << InsertionMode::InTemplate
      when "col"
        @template_insertion_modes.pop if @template_insertion_modes.size > 0
        @template_insertion_modes << InsertionMode::InColumnGroup
        @mode = InsertionMode::InColumnGroup
        process_start_tag(tag)
      when "caption", "colgroup", "tbody", "tfoot", "thead"
        @template_insertion_modes.pop if @template_insertion_modes.size > 0
        @template_insertion_modes << InsertionMode::InTable
        @mode = InsertionMode::InTable
        process_start_tag(tag)
      when "tr"
        @template_insertion_modes.pop if @template_insertion_modes.size > 0
        @template_insertion_modes << InsertionMode::InTableBody
        @mode = InsertionMode::InTableBody
        process_start_tag(tag)
      when "td", "th"
        @template_insertion_modes.pop if @template_insertion_modes.size > 0
        @template_insertion_modes << InsertionMode::InRow
        @mode = InsertionMode::InRow
        process_start_tag(tag)
      else
        @template_insertion_modes.pop if @template_insertion_modes.size > 0
        @template_insertion_modes << InsertionMode::InBody
        @mode = InsertionMode::InBody
        process_start_tag(tag)
      end
    end

    private def process_in_table_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "caption"
        clear_stack_back_to_table_context
        @active_formatting_elements << ActiveFormattingMarker.new
        element = create_element(tag)
        insert_element(element)
        @mode = InsertionMode::InCaption
      when "colgroup"
        clear_stack_back_to_table_context
        element = create_element(tag)
        insert_element(element)
        @mode = InsertionMode::InColumnGroup
      when "col"
        clear_stack_back_to_table_context
        # Insert implicit colgroup
        colgroup = Element.new("colgroup")
        insert_element(colgroup)
        @mode = InsertionMode::InColumnGroup
        process_start_tag(tag)
      when "tbody", "tfoot", "thead"
        clear_stack_back_to_table_context
        element = create_element(tag)
        insert_element(element)
        @mode = InsertionMode::InTableBody
      when "td", "th", "tr"
        clear_stack_back_to_table_context
        # Insert implicit tbody
        tbody = Element.new("tbody")
        insert_element(tbody)
        @mode = InsertionMode::InTableBody
        process_start_tag(tag)
      when "table"
        # Close current table and start a new one
        if has_element_in_table_scope?("table")
          pop_until("table")
          reset_insertion_mode
          process_start_tag(tag)
        end
      when "style", "script", "template"
        # Process using "in head" rules
        @mode = InsertionMode::InHead
        process_start_tag(tag)
        @mode = InsertionMode::InTable
      when "input"
        # If type is hidden, insert it; otherwise foster parent
        if tag.attrs["type"]?.try(&.downcase) == "hidden"
          element = create_element(tag)
          insert_element(element)
          @open_elements.pop
        else
          # Foster parent
          @foster_parenting = true
          process_in_body_start_tag(tag)
          @foster_parenting = false
        end
      when "form"
        if @form_element.nil?
          @form_element = Element.new(tag.name, tag.attrs)
          foster_parent_node(@form_element.not_nil!)
        end
      else
        # Foster parent anything else
        @foster_parenting = true
        process_in_body_start_tag(tag)
        @foster_parenting = false
      end
    end

    private def process_in_table_body_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "tr"
        clear_stack_back_to_table_body_context
        element = create_element(tag)
        insert_element(element)
        @mode = InsertionMode::InRow
      when "th", "td"
        clear_stack_back_to_table_body_context
        # Insert implicit tr
        tr = Element.new("tr")
        insert_element(tr)
        @mode = InsertionMode::InRow
        process_start_tag(tag)
      when "caption", "col", "colgroup", "tbody", "tfoot", "thead"
        if has_element_in_table_scope?("tbody") || has_element_in_table_scope?("thead") || has_element_in_table_scope?("tfoot")
          clear_stack_back_to_table_body_context
          pop_current_table_body
          @mode = InsertionMode::InTable
          process_start_tag(tag)
        end
      else
        # Process using "in table" rules
        process_in_table_start_tag(tag)
      end
    end

    private def process_in_row_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "th", "td"
        clear_stack_back_to_table_row_context
        element = create_element(tag)
        insert_element(element)
        @mode = InsertionMode::InCell
        @active_formatting_elements << ActiveFormattingMarker.new
      when "caption", "col", "colgroup", "tbody", "tfoot", "thead", "tr"
        if has_element_in_table_scope?("tr")
          clear_stack_back_to_table_row_context
          @open_elements.pop # Pop tr
          @mode = InsertionMode::InTableBody
          process_start_tag(tag)
        end
      else
        # Process using "in table" rules
        process_in_table_start_tag(tag)
      end
    end

    private def process_in_cell_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"
        if has_element_in_table_scope?("td") || has_element_in_table_scope?("th")
          close_cell
          process_start_tag(tag)
        end
      else
        # Process using "in body" rules
        process_in_body_start_tag(tag)
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
        # Check for existing a in active formatting elements
        # If found, run adoption agency algorithm for it first
        @active_formatting_elements.reverse_each do |entry|
          case entry
          when ActiveFormattingMarker
            break
          when Element
            if entry.name == "a"
              run_adoption_agency_algorithm("a")
              @active_formatting_elements.reject! { |e| e == entry }
              @open_elements.delete(entry)
              break
            end
          end
        end
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        push_onto_active_formatting_elements(element)
      when "b", "big", "code", "em", "font", "i", "s", "small", "strike", "strong", "tt", "u"
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        push_onto_active_formatting_elements(element)
      when "nobr"
        reconstruct_active_formatting_elements
        # If nobr is already in scope, run AAA for it first
        if has_element_in_scope?("nobr")
          run_adoption_agency_algorithm("nobr")
          reconstruct_active_formatting_elements
        end
        element = create_element(tag)
        insert_element(element)
        push_onto_active_formatting_elements(element)
      when "applet", "marquee", "object"
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        @active_formatting_elements << ActiveFormattingMarker.new
        @frameset_ok = false
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
      when "svg"
        reconstruct_active_formatting_elements
        element = Element.new(tag.name, tag.attrs, Constants::NAMESPACE_SVG)
        insert_element(element)
      when "math"
        reconstruct_active_formatting_elements
        element = Element.new(tag.name, tag.attrs, Constants::NAMESPACE_MATHML)
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
        if name == "template"
          # Handle template end tag
          if @open_elements.any? { |el| el.name == "template" }
            generate_implied_end_tags
            pop_until("template")
            clear_active_formatting_elements_to_last_marker
            @template_insertion_modes.pop if @template_insertion_modes.size > 0
            reset_insertion_mode
          end
        elsif name == "head"
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
      when .in_template?
        # Handle end tags in template mode
        if name == "template"
          # Handle template end tag (same as in_head)
          if @open_elements.any? { |el| el.name == "template" }
            generate_implied_end_tags
            pop_until("template")
            clear_active_formatting_elements_to_last_marker
            @template_insertion_modes.pop if @template_insertion_modes.size > 0
            reset_insertion_mode
          end
        else
          # For other end tags, process using the current template insertion mode
          # This is already handled by reset_insertion_mode
          process_in_body_end_tag(tag)
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
        # Run the adoption agency algorithm
        handled = run_adoption_agency_algorithm(name)
        # If AAA returned false, process as "any other end tag"
        unless handled
          (@open_elements.size - 1).downto(0) do |i|
            el = @open_elements[i]
            if el.name == name
              generate_implied_end_tags(name)
              (@open_elements.size - i).times { @open_elements.pop }
              break
            end
            break if Constants::SPECIAL_ELEMENTS.includes?(el.name)
          end
        end
      when "applet", "marquee", "object"
        if has_element_in_scope?(name)
          generate_implied_end_tags
          pop_until(name)
          clear_active_formatting_elements_to_last_marker
        end
      when "template"
        # Handle template end tag
        if @open_elements.any? { |el| el.name == "template" }
          generate_implied_end_tags
          pop_until("template")
          clear_active_formatting_elements_to_last_marker
          @template_insertion_modes.pop if @template_insertion_modes.size > 0
          reset_insertion_mode
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

    private def create_element(tag : Tag, namespace : String = "html") : Element
      name = tag.name
      # Adjust SVG tag names
      if namespace == "svg"
        name = adjust_svg_tag_name(name)
      end
      Element.new(name, tag.attrs, namespace)
    end

    private def adjust_svg_tag_name(name : String) : String
      Constants::SVG_TAG_ADJUSTMENTS[name]? || name
    end

    private def insert_element(element : Element) : Nil
      if @foster_parenting && in_table_context?
        foster_parent_node(element)
      elsif current = current_node
        # If current is a template element, insert into its template_contents
        if current.name == "template" && (template_contents = current.template_contents)
          template_contents.append_child(element)
        else
          current.append_child(element)
        end
      else
        @document.append_child(element)
      end
      @open_elements << element
    end

    private def insert_node(node : Node) : Nil
      if @foster_parenting && in_table_context?
        foster_parent_node(node)
      elsif current = current_node
        # If current is a template element, insert into its template_contents
        if current.name == "template" && (template_contents = current.template_contents)
          template_contents.append_child(node)
        else
          current.append_child(node)
        end
      else
        @document.append_child(node)
      end
    end

    private def in_table_context? : Bool
      # Check if the current node (where we'd insert) is a table-related element
      # If the current node is NOT a table element (e.g., it's a foster-parented <p>),
      # then we shouldn't foster parent children of that element
      if current = current_node
        {"table", "tbody", "tfoot", "thead", "tr", "td", "th", "caption", "colgroup"}.includes?(current.name)
      else
        false
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

    private def has_element_in_table_scope?(name : String) : Bool
      scope_terminators = {"html", "table", "template"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        return false if scope_terminators.includes?(el.name)
      end
      false
    end

    # Table context helpers

    private def clear_stack_back_to_table_context : Nil
      while el = @open_elements.last?
        break if {"table", "template", "html"}.includes?(el.name)
        @open_elements.pop
      end
    end

    private def clear_stack_back_to_table_body_context : Nil
      while el = @open_elements.last?
        break if {"tbody", "tfoot", "thead", "template", "html"}.includes?(el.name)
        @open_elements.pop
      end
    end

    private def clear_stack_back_to_table_row_context : Nil
      while el = @open_elements.last?
        break if {"tr", "template", "html"}.includes?(el.name)
        @open_elements.pop
      end
    end

    private def pop_current_table_body : Nil
      if el = @open_elements.last?
        if {"tbody", "tfoot", "thead"}.includes?(el.name)
          @open_elements.pop
        end
      end
    end

    private def close_cell : Nil
      generate_implied_end_tags
      while el = @open_elements.pop?
        break if {"td", "th"}.includes?(el.name)
      end
      clear_active_formatting_elements_to_last_marker
      @mode = InsertionMode::InRow
    end

    private def reset_insertion_mode : Nil
      @open_elements.reverse_each do |el|
        last = el == @open_elements.first?
        case el.name
        when "select"
          @mode = InsertionMode::InSelect
          return
        when "td", "th"
          @mode = InsertionMode::InCell
          return
        when "tr"
          @mode = InsertionMode::InRow
          return
        when "tbody", "thead", "tfoot"
          @mode = InsertionMode::InTableBody
          return
        when "caption"
          @mode = InsertionMode::InCaption
          return
        when "colgroup"
          @mode = InsertionMode::InColumnGroup
          return
        when "table"
          @mode = InsertionMode::InTable
          return
        when "template"
          # Use the current template insertion mode from the stack
          if mode = @template_insertion_modes.last?
            @mode = mode
          else
            @mode = InsertionMode::InTemplate
          end
          return
        when "body"
          @mode = InsertionMode::InBody
          return
        when "frameset"
          @mode = InsertionMode::InFrameset
          return
        when "html"
          if @head_element.nil?
            @mode = InsertionMode::BeforeHead
          else
            @mode = InsertionMode::AfterHead
          end
          return
        end
        if last
          @mode = InsertionMode::InBody
          return
        end
      end
      @mode = InsertionMode::InBody
    end

    # Active formatting elements methods

    private def push_onto_active_formatting_elements(entry : ActiveFormattingEntry) : Nil
      # If it's a marker, just add it
      if entry.is_a?(ActiveFormattingMarker)
        @active_formatting_elements << entry
        return
      end

      # Check for duplicate formatting elements (Noah's Ark clause)
      # If there are already 3 elements with same tag and attributes, remove the earliest
      element = entry.as(Element)
      count = 0
      earliest_idx : Int32? = nil

      @active_formatting_elements.each_with_index do |existing, idx|
        case existing
        when ActiveFormattingMarker
          # Reset count at marker
          count = 0
          earliest_idx = nil
        when Element
          if existing.name == element.name && existing.attrs == element.attrs
            count += 1
            earliest_idx = idx if earliest_idx.nil?
          end
        end
      end

      if count >= 3 && earliest_idx
        @active_formatting_elements.delete_at(earliest_idx)
      end

      @active_formatting_elements << element
    end

    private def reconstruct_active_formatting_elements : Nil
      return if @active_formatting_elements.empty?

      # If the last entry is a marker or in the stack, return
      last = @active_formatting_elements.last
      return if last.is_a?(ActiveFormattingMarker)
      return if @open_elements.includes?(last)

      # Step 4: Let entry be the last element
      entry_idx = @active_formatting_elements.size - 1

      # Step 5-7: Rewind
      loop do
        break if entry_idx == 0
        entry_idx -= 1
        entry = @active_formatting_elements[entry_idx]
        if entry.is_a?(ActiveFormattingMarker) || @open_elements.includes?(entry)
          entry_idx += 1
          break
        end
      end

      # Step 8: Advance and create
      while entry_idx < @active_formatting_elements.size
        entry = @active_formatting_elements[entry_idx]
        if entry.is_a?(Element)
          # Create a new element with same tag and attributes
          new_element = Element.new(entry.name, entry.attrs.dup)
          insert_element(new_element)
          @active_formatting_elements[entry_idx] = new_element
        end
        entry_idx += 1
      end
    end

    private def clear_active_formatting_elements_to_last_marker : Nil
      while entry = @active_formatting_elements.pop?
        break if entry.is_a?(ActiveFormattingMarker)
      end
    end

    private def remove_from_active_formatting_elements(element : Element) : Nil
      @active_formatting_elements.reject! { |e| e == element }
    end

    # The Adoption Agency Algorithm - handles misnested formatting elements
    private def run_adoption_agency_algorithm(subject : String) : Bool
      # Step 1-2: If current node is the subject and not in active formatting elements
      if current = current_node
        if current.name == subject
          in_active = @active_formatting_elements.any? { |e| e.is_a?(Element) && e == current }
          unless in_active
            @open_elements.pop
            return true
          end
        end
      end

      # Step 3-4: Outer loop (max 8 iterations)
      8.times do
        # Step 5: Find formatting element in active formatting elements
        formatting_element : Element? = nil
        formatting_element_idx : Int32? = nil

        (@active_formatting_elements.size - 1).downto(0) do |i|
          entry = @active_formatting_elements[i]
          case entry
          when ActiveFormattingMarker
            break # Not found before marker
          when Element
            if entry.name == subject
              formatting_element = entry
              formatting_element_idx = i
              break
            end
          end
        end

        # Step 6: If no formatting element, process as any other end tag
        return false unless formatting_element && formatting_element_idx

        # Step 7: Check if formatting element is in the stack of open elements
        stack_idx = @open_elements.index(formatting_element)
        unless stack_idx
          # Not in stack - remove from active formatting and return
          @active_formatting_elements.delete_at(formatting_element_idx)
          return true
        end

        # Step 8: Check if formatting element is in scope
        unless has_element_in_scope?(subject)
          return true # Parse error, do nothing
        end

        # Step 9: Find the furthest block
        furthest_block : Element? = nil
        furthest_block_idx : Int32? = nil

        ((stack_idx + 1)...@open_elements.size).each do |i|
          el = @open_elements[i]
          if Constants::SPECIAL_ELEMENTS.includes?(el.name)
            furthest_block = el
            furthest_block_idx = i
            break
          end
        end

        # Step 10: If no furthest block, pop until formatting element
        unless furthest_block && furthest_block_idx
          while el = @open_elements.pop?
            break if el == formatting_element
          end
          @active_formatting_elements.delete_at(formatting_element_idx)
          return true
        end

        # Step 11: Let common ancestor be the element immediately above formatting element
        common_ancestor = @open_elements[stack_idx - 1]? if stack_idx > 0

        # Step 12: Let bookmark point to formatting element's position
        bookmark = formatting_element_idx

        # Step 13: Let node and last node point to furthest block
        node = furthest_block
        node_idx = furthest_block_idx
        last_node = furthest_block

        # Step 14: Inner loop
        inner_loop_counter = 0
        loop do
          # Step 14.1: Increment inner loop counter
          inner_loop_counter += 1

          # Step 14.2: Let node be the element immediately above node in the stack
          node_idx -= 1
          break if node_idx < 0
          node = @open_elements[node_idx]

          # Step 14.3: If node is the formatting element, break
          break if node == formatting_element

          # Step 14.4: If inner loop counter > 3 and node is in active formatting, remove it
          node_in_active = @active_formatting_elements.index { |e| e == node }
          if inner_loop_counter > 3 && node_in_active
            @active_formatting_elements.delete_at(node_in_active)
            # Adjust bookmark if we removed an entry before it
            bookmark -= 1 if node_in_active < bookmark
            node_in_active = nil
          end

          # Step 14.5: If node is not in active formatting elements, remove from stack and continue
          unless node_in_active
            @open_elements.delete_at(node_idx)
            furthest_block_idx -= 1 if furthest_block_idx > node_idx
            next
          end

          # Step 14.6: Create new element, replace in both lists
          new_element = Element.new(node.name, node.attrs.dup)

          # Replace in active formatting elements
          @active_formatting_elements[node_in_active] = new_element

          # Replace in open elements stack
          @open_elements[node_idx] = new_element

          # Step 14.7: If last node is furthest block, update bookmark
          if last_node == furthest_block
            bookmark = node_in_active + 1
          end

          # Step 14.8: Move last node to be a child of new element
          if parent = last_node.parent
            parent.children.delete(last_node)
          end
          new_element.append_child(last_node)

          # Step 14.9: Set last node to new element
          last_node = new_element
          node = new_element
        end

        # Step 15: Insert last node at appropriate place for common ancestor
        if common_ancestor
          # If foster parenting, do that; otherwise insert in common ancestor
          if @foster_parenting
            foster_parent_node(last_node)
          else
            if parent = last_node.parent
              parent.children.delete(last_node)
            end
            # Insert into template_contents if common ancestor is a template
            if common_ancestor.name == "template" && (template_contents = common_ancestor.template_contents)
              template_contents.append_child(last_node)
            else
              common_ancestor.append_child(last_node)
            end
          end
        end

        # Step 16: Create new element with formatting element's attributes
        new_formatting_element = Element.new(formatting_element.name, formatting_element.attrs.dup)

        # Step 17: Take all children of furthest block and append to new element
        furthest_block.children.each do |child|
          child.parent = new_formatting_element
        end
        new_formatting_element.children.concat(furthest_block.children)
        furthest_block.children.clear

        # Step 18: Append new element to furthest block
        furthest_block.append_child(new_formatting_element)

        # Step 19: Remove formatting element from active formatting and insert new element at bookmark
        @active_formatting_elements.delete(formatting_element)
        bookmark = [bookmark, @active_formatting_elements.size].min
        @active_formatting_elements.insert(bookmark, new_formatting_element)

        # Step 20: Remove formatting element from stack and insert new element after furthest block
        @open_elements.delete(formatting_element)
        new_idx = @open_elements.index(furthest_block)
        if new_idx
          @open_elements.insert(new_idx + 1, new_formatting_element)
        else
          @open_elements << new_formatting_element
        end
      end

      true
    end

    # Foster parenting - insert node before the table in the DOM
    private def foster_parent_node(node : Node) : Nil
      # Find the last table in the stack
      table_idx = @open_elements.rindex { |el| el.name == "table" }

      if table_idx
        table = @open_elements[table_idx]
        if parent = table.parent
          # Insert before the table
          idx = parent.children.index(table) || parent.children.size
          node.parent = parent
          parent.children.insert(idx, node)
          return
        elsif table_idx > 0
          # Insert as last child of element before table in stack
          foster_parent = @open_elements[table_idx - 1]
          foster_parent.append_child(node)
          return
        end
      end

      # Fallback: insert in body or html
      if body = @open_elements.find { |el| el.name == "body" }
        body.append_child(node)
      elsif html = @open_elements.first?
        html.append_child(node)
      end
    end
  end

  # FragmentBuilder parses HTML fragments into DocumentFragment nodes
  class FragmentBuilder
    include TokenSink

    getter fragment : DocumentFragment
    getter errors : Array(ParseError)

    @open_elements : Array(Element)
    @context : Element
    @tokenizer : Tokenizer?
    @ignore_lf : Bool

    def initialize(context_name : String = "body", context_namespace : String = "html", @collect_errors : Bool = false)
      @fragment = DocumentFragment.new
      @errors = [] of ParseError
      @context = Element.new(context_name, context_namespace)
      @open_elements = [@context]
      @tokenizer = nil
      @ignore_lf = false
    end

    def self.parse(html : String, context : String = "body", context_namespace : String = "html", collect_errors : Bool = false) : DocumentFragment
      builder = new(context, context_namespace, collect_errors)
      tokenizer = Tokenizer.new(builder, collect_errors)
      builder.set_tokenizer(tokenizer)
      tokenizer.run(html)

      # Move children from context element to fragment
      builder.context.children.each do |child|
        child.parent = builder.fragment
        builder.fragment.children << child
      end
      builder.context.children.clear

      builder.fragment
    end

    protected def context : Element
      @context
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
      # In foreign content (SVG/MathML), CDATA sections are tokenized as comments
      # with data like "[CDATA[content]]". Convert these to text nodes.
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "math")
        if comment.data.starts_with?("[CDATA[") && comment.data.ends_with?("]]")
          cdata_content = comment.data[7..-3]
          # Normalize line endings: CRLF -> LF, CR -> LF
          cdata_content = cdata_content.gsub("\r\n", "\n").gsub("\r", "\n")
          node = Text.new(cdata_content)
          insert_node(node)
          return
        end
      end

      node = Comment.new(comment.data)
      insert_node(node)
    end

    def process_doctype(doctype : Doctype) : Nil
      # Ignore doctype in fragments
    end

    def process_eof : Nil
      # Nothing to do
    end

    def process_characters(data : String) : Nil
      return if data.empty?

      if @ignore_lf && data[0] == '\n'
        data = data[1..]
        return if data.empty?
      end
      @ignore_lf = false

      if current = current_node
        # Merge adjacent text nodes
        if last = current.children.last?
          if last.is_a?(Text)
            combined = last.as(Text).data + data
            current.children.pop
            current.append_child(Text.new(combined))
            return
          end
        end
        current.append_child(Text.new(data))
      end
    end

    def open_elements : Array(Element)
      @open_elements
    end

    private def adjust_svg_tag_name(name : String) : String
      Constants::SVG_TAG_ADJUSTMENTS[name]? || name
    end

    # Check if an element is an HTML integration point
    private def is_html_integration_point?(element : Element?) : Bool
      return false unless element

      # SVG foreignObject, desc, title are integration points
      if element.namespace == "svg"
        return {"foreignObject", "desc", "title"}.includes?(element.name)
      end

      # MathML annotation-xml is an integration point with certain attributes
      # MathML text integration points: mi, mo, mn, ms, mtext
      if element.namespace == "mathml"
        if element.name == "annotation-xml"
          encoding = element["encoding"].try(&.downcase)
          return encoding == "text/html" || encoding == "application/xhtml+xml"
        end
        # MathML text elements are also integration points
        return {"mi", "mo", "mn", "ms", "mtext"}.includes?(element.name)
      end

      false
    end

    # Check if a tag should break out of foreign content
    # These are HTML formatting/phrasing elements that break out if they have certain attributes
    private def breaks_out_of_foreign_content?(tag : Tag, current_namespace : String) : Bool
      return false if current_namespace == "html"

      name = tag.name
      attrs = tag.attrs

      # Font element with color, face, or size attribute breaks out
      if name == "font"
        return attrs.has_key?("color") || attrs.has_key?("face") || attrs.has_key?("size")
      end

      # These elements always break out
      break_out_tags = {"b", "big", "blockquote", "body", "br", "center", "code", "dd", "div",
                        "dl", "dt", "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head",
                        "hr", "i", "img", "li", "listing", "menu", "meta", "nobr", "ol", "p",
                        "pre", "ruby", "s", "small", "span", "strong", "strike", "sub", "sup",
                        "table", "tt", "u", "ul", "var"}
      return break_out_tags.includes?(name)
    end

    # Check if a tag name is a MathML-specific element
    private def is_mathml_text_integration_point_element?(tag_name : String) : Bool
      # MathML text integration points can have both HTML and MathML content
      # but certain elements are MathML-only
      mathml_only = {"mglyph", "malignmark"}
      mathml_only.includes?(tag_name)
    end

    private def process_start_tag(tag : Tag) : Nil
      name = tag.name

      # Determine the namespace for the new element
      current = current_node
      namespace = current.try(&.namespace) || "html"

      # If we're in an HTML integration point and encounter table structure tags,
      # ignore them (they're parse errors in this context)
      if current && is_html_integration_point?(current) &&
         {"tr", "td", "th", "tbody", "thead", "tfoot", "table", "caption", "col", "colgroup"}.includes?(tag.name)
        # Ignore this tag
        return
      end

      # Special handling for MathML text integration points
      is_in_mathml_integration_point = current && is_html_integration_point?(current) && current.namespace == "mathml"

      # Check if this tag breaks out of foreign content
      if breaks_out_of_foreign_content?(tag, namespace)
        namespace = "html"
      # If current element is an HTML integration point
      elsif is_in_mathml_integration_point && is_mathml_text_integration_point_element?(tag.name)
        # MathML-specific elements stay in MathML namespace even in integration points
        namespace = "mathml"
      elsif is_html_integration_point?(current)
        namespace = "html"
      end

      # Adjust tag name for SVG namespace
      if namespace == "svg"
        name = adjust_svg_tag_name(name)
      end

      # Handle svg/math tags entering foreign content
      if namespace == "html"
        if tag.name == "svg"
          namespace = "svg"
        elsif tag.name == "math"
          namespace = "mathml"
        end
      end

      case name
      when "script", "style"
        element = Element.new(name, tag.attrs, namespace)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
      when "textarea"
        element = Element.new(name, tag.attrs, namespace)
        insert_element(element)
        @ignore_lf = true
        @tokenizer.try(&.set_state(Tokenizer::State::RCDATA))
      else
        element = Element.new(name, tag.attrs, namespace)
        insert_element(element)
        # In foreign content (SVG/MathML), self-closing tags should be popped
        # In HTML, only void elements should be popped
        if namespace != "html" && tag.self_closing?
          @open_elements.pop
        elsif Constants::VOID_ELEMENTS.includes?(name)
          @open_elements.pop
        end
      end
    end

    private def process_end_tag(tag : Tag) : Nil
      name = tag.name

      # Pop elements until we find a matching one
      (@open_elements.size - 1).downto(1) do |i|
        el = @open_elements[i]
        if el.name == name
          # Pop up to and including the matched element
          (@open_elements.size - i).times { @open_elements.pop }
          break
        end
        break if Constants::SPECIAL_ELEMENTS.includes?(el.name)
      end
    end

    private def insert_element(element : Element) : Nil
      if current = current_node
        current.append_child(element)
      end
      @open_elements << element
    end

    private def insert_node(node : Node) : Nil
      if current = current_node
        current.append_child(node)
      end
    end

    private def current_node : Element?
      @open_elements.last?
    end
  end
end
