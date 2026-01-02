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

    # Elements that are targets for foster parenting
    TABLE_FOSTER_TARGETS = {"table", "tbody", "tfoot", "thead", "tr"}

    # Elements allowed as children of table-related elements (not foster parented)
    TABLE_ALLOWED_CHILDREN = {"caption", "colgroup", "tbody", "tfoot", "thead", "tr", "td", "th", "script", "template", "style"}

    getter document : Document
    getter errors : Array(ParseError)

    # Fragment context support
    record FragmentContext, tag_name : String, namespace : String?

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
    @fragment_context : FragmentContext?
    @fragment_context_element : Element?
    @pending_table_text : Array(String)
    @table_text_original_mode : InsertionMode?

    def initialize(@collect_errors : Bool = false, @fragment_context : FragmentContext? = nil)
      @document = Document.new
      @errors = [] of ParseError
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
      @fragment_context_element = nil
      @pending_table_text = [] of String
      @table_text_original_mode = nil

      if fragment_ctx = @fragment_context
        # Fragment parsing per HTML5 spec
        root = Element.new("html")
        @document.append_child(root)
        @open_elements << root

        namespace = fragment_ctx.namespace
        context_name = fragment_ctx.tag_name.downcase

        # Create a context element for special contexts
        if namespace && namespace != "html"
          # Foreign content (SVG/MathML)
          adjusted_name = context_name
          if namespace == "svg"
            adjusted_name = adjust_svg_tag_name(context_name)
          end
          context_element = Element.new(adjusted_name, {} of String => String?, namespace)
          root.append_child(context_element)
          @open_elements << context_element
          @fragment_context_element = context_element
        end

        # Set insertion mode based on context element name
        @mode = case context_name
        when "html"
          InsertionMode::BeforeHead
        when "tbody", "thead", "tfoot"
          if namespace.nil? || namespace == "html"
            InsertionMode::InTableBody
          else
            InsertionMode::InBody
          end
        when "tr"
          if namespace.nil? || namespace == "html"
            InsertionMode::InRow
          else
            InsertionMode::InBody
          end
        when "td", "th"
          if namespace.nil? || namespace == "html"
            InsertionMode::InCell
          else
            InsertionMode::InBody
          end
        when "caption"
          if namespace.nil? || namespace == "html"
            InsertionMode::InCaption
          else
            InsertionMode::InBody
          end
        when "colgroup"
          if namespace.nil? || namespace == "html"
            InsertionMode::InColumnGroup
          else
            InsertionMode::InBody
          end
        when "table"
          if namespace.nil? || namespace == "html"
            InsertionMode::InTable
          else
            InsertionMode::InBody
          end
        else
          InsertionMode::InBody
        end

        # For fragments, frameset_ok starts as False per HTML5 spec
        # This prevents frameset from being inserted in fragment contexts
        @frameset_ok = false
      else
        @mode = InsertionMode::Initial
      end
    end

    def self.parse(html : String, collect_errors : Bool = false) : Document
      builder = new(collect_errors)
      tokenizer = Tokenizer.new(builder, collect_errors)
      builder.set_tokenizer(tokenizer)
      tokenizer.run(html)
      builder.document
    end

    def self.parse_fragment(html : String, context : String = "body", context_namespace : String? = nil, collect_errors : Bool = false) : DocumentFragment
      fragment_ctx = FragmentContext.new(context, context_namespace)
      builder = new(collect_errors, fragment_ctx)
      tokenizer = Tokenizer.new(builder, collect_errors)
      builder.set_tokenizer(tokenizer)

      # Set tokenizer state based on context element per HTML5 spec
      # Only applies to HTML namespace (no namespace or "html")
      if context_namespace.nil? || context_namespace == "html"
        context_lower = context.downcase
        case context_lower
        when "title", "textarea"
          tokenizer.set_state(Tokenizer::State::RCDATA)
        when "style", "xmp", "iframe", "noembed", "noframes"
          tokenizer.set_state(Tokenizer::State::RAWTEXT)
        when "script"
          tokenizer.set_state(Tokenizer::State::ScriptData)
        when "plaintext"
          tokenizer.set_state(Tokenizer::State::PLAINTEXT)
        end
      end

      tokenizer.run(html)
      builder.finish_fragment
    end

    # Finish fragment parsing and return DocumentFragment
    protected def finish_fragment : DocumentFragment
      fragment = DocumentFragment.new

      # Find the root html element
      root = @document.children.find { |c| c.is_a?(Element) && c.as(Element).name == "html" }
      return fragment unless root.is_a?(Element)

      # If there's a fragment context element, move its children to the root first
      if context_elem = @fragment_context_element
        if context_elem.parent == root
          context_elem.children.each do |child|
            child.parent = root
            root.children << child
          end
          context_elem.children.clear
          root.children.delete(context_elem)
        end
      end

      # Move all children of root to fragment
      root.children.each do |child|
        child.parent = fragment
        fragment.children << child
      end
      root.children.clear

      fragment
    end

    def set_tokenizer(tokenizer : Tokenizer) : Nil
      @tokenizer = tokenizer
    end

    # TokenSink implementation

    def process_tag(tag : Tag) : Nil
      # Flush pending table text if we're in InTableText mode
      if @mode.in_table_text?
        flush_pending_table_text
      end

      if tag.kind == :start
        process_start_tag(tag)
      else
        process_end_tag(tag)
      end
    end

    def process_comment(comment : CommentToken) : Nil
      # Flush pending table text if we're in InTableText mode
      if @mode.in_table_text?
        flush_pending_table_text
      end

      # In foreign content (SVG/MathML), CDATA sections are tokenized as comments
      # with data like "[CDATA[content]]" or "[CDATA[content" (unclosed).
      # Convert these to text nodes.
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "mathml")
        if comment.data.starts_with?("[CDATA[")
          # Extract content: remove "[CDATA[" prefix and "]]" suffix if present
          cdata_content = comment.data[7..]
          if cdata_content.ends_with?("]]")
            cdata_content = cdata_content[0..-3]
          end
          # Only insert non-empty content
          unless cdata_content.empty?
            # Normalize line endings: CRLF -> LF, CR -> LF
            cdata_content = cdata_content.gsub("\r\n", "\n").gsub("\r", "\n")
            node = Text.new(cdata_content)
            insert_node(node)
          end
          return
        end
      end

      node = Comment.new(comment.data)

      # In after-after-body/after-after-frameset modes, comments are appended to document
      if @mode.after_after_body? || @mode.after_after_frameset?
        @document.append_child(node)
        return
      end

      # In after-body mode, comments are appended to the html element
      if @mode.after_body?
        if html = @open_elements.first?
          html.append_child(node)
          return
        end
      end

      insert_node(node)
    end

    def process_doctype(doctype : Doctype) : Nil
      # Flush pending table text if we're in InTableText mode
      if @mode.in_table_text?
        flush_pending_table_text
      end

      # DOCTYPE is only valid in Initial mode
      # In any other mode, it's a parse error and should be ignored
      return unless @mode.initial?

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

      # Remove NULL bytes in most contexts (except foreign content where they're replaced with U+FFFD)
      # This matches HTML5 spec behavior for character tokens
      if data.includes?('\0')
        # In foreign content (not at integration points), NULL is replaced with U+FFFD (handled in insert_text)
        # In HTML content and at integration points, NULL is removed
        current = current_node
        in_foreign = current && (current.namespace == "svg" || current.namespace == "mathml")
        at_integration_point = current && (is_html_integration_point?(current) || is_mathml_text_integration_point?(current))

        # Remove NULL if we're NOT in foreign content, OR if we're at an integration point
        unless in_foreign && !at_integration_point
          data = data.gsub('\0', "")
          return if data.empty?
        end
      end

      # Handle whitespace in certain modes
      case @mode
      when .initial?, .before_html?, .before_head?
        # Skip leading ASCII whitespace in these modes (not all Unicode whitespace)
        data = lstrip_ascii_whitespace(data)
        return if data.empty?
        # If non-whitespace, need to ensure proper context
        if @mode.before_head?
          ensure_body_context
        end
      when .in_head?
        # In head mode: whitespace is inserted, non-whitespace causes head to close
        ws_len = 0
        data.each_char do |c|
          break unless c == ' ' || c == '\t' || c == '\n' || c == '\f' || c == '\r'
          ws_len += 1
        end
        if ws_len > 0
          insert_text(data[0, ws_len])
        end
        if ws_len < data.size
          # Has non-whitespace - close head, move to after head, reprocess
          @open_elements.pop if @open_elements.last?.try(&.name) == "head"
          @mode = InsertionMode::AfterHead
          process_characters(data[ws_len..])
        end
        return
      when .in_head_noscript?
        # Whitespace: process using in head rules (insert as text)
        if all_ascii_whitespace?(data)
          insert_text(data)
          return
        end
        # Non-whitespace: pop noscript, reprocess in head
        @open_elements.pop if @open_elements.last?.try(&.name) == "noscript"
        @mode = InsertionMode::InHead
        process_characters(data)
        return
      when .after_head?
        # Skip leading ASCII whitespace in AfterHead mode
        data = lstrip_ascii_whitespace(data)
        return if data.empty?
        # Non-whitespace in AfterHead mode: insert implicit body
        body = Element.new("body")
        insert_element(body)
        @mode = InsertionMode::InBody
        @frameset_ok = false # Non-whitespace sets frameset_ok to false
        reconstruct_active_formatting_elements
      when .in_body?
        # Reconstruct active formatting elements when in body mode
        reconstruct_active_formatting_elements
        # Non-whitespace text sets frameset_ok to false
        unless all_ascii_whitespace?(data)
          @frameset_ok = false
        end
      when .in_column_group?
        # Whitespace is allowed, non-whitespace causes colgroup to close
        ws_len = 0
        data.each_char do |c|
          break unless c == ' ' || c == '\t' || c == '\n' || c == '\f' || c == '\r'
          ws_len += 1
        end
        if ws_len > 0
          insert_text(data[0, ws_len])
        end
        if ws_len < data.size
          # Has non-whitespace - pop colgroup and switch to InTable
          current = current_node
          if current && current.name == "colgroup"
            @open_elements.pop
            @mode = InsertionMode::InTable
            process_characters(data[ws_len..])
          end
          # Otherwise ignore (template context)
        end
        return
      when .in_table?, .in_table_body?, .in_row?
        # In table modes, switch to InTableText to collect text
        @pending_table_text.clear
        @table_text_original_mode = @mode
        @mode = InsertionMode::InTableText
        process_characters(data)  # Reprocess in InTableText mode
        return
      when .in_table_text?
        # Collect text in pending_table_text
        @pending_table_text << data
        return
      when .in_cell?, .in_caption?
        # In cell/caption, process normally using in-body rules
        reconstruct_active_formatting_elements
        # Non-whitespace text sets frameset_ok to false
        unless all_ascii_whitespace?(data)
          @frameset_ok = false
        end
      when .in_select?, .in_select_in_table?
        # Characters are allowed in select (except NULL)
        insert_text(data.gsub('\0', ""))
        return
      when .in_frameset?, .after_frameset?, .after_after_frameset?
        # Only whitespace is allowed in frameset modes
        ws_only = data.chars.select { |c| c == ' ' || c == '\t' || c == '\n' || c == '\f' || c == '\r' }.join
        insert_text(ws_only) unless ws_only.empty?
        return
      when .in_template?
        # In template mode, process as in body
        reconstruct_active_formatting_elements
        # Non-whitespace text sets frameset_ok to false
        unless all_ascii_whitespace?(data)
          @frameset_ok = false
        end
      when .after_body?, .after_after_body?
        # Whitespace is processed using InBody rules (stays in current mode)
        # Non-whitespace reprocesses in InBody
        if all_ascii_whitespace?(data)
          # Process whitespace using InBody rules
          reconstruct_active_formatting_elements
          insert_text(data)
          return
        else
          # Non-whitespace: switch to InBody and reprocess
          @mode = InsertionMode::InBody
          process_characters(data)
          return
        end
      end

      # Insert text into current element
      insert_text(data)
    end

    private def insert_text(data : String) : Nil
      return if data.empty?

      if current = current_node
        # In foreign content (SVG/MathML), replace NULL bytes with U+FFFD
        # But NOT at HTML/MathML integration points where NULL is removed like in HTML
        if (current.namespace == "svg" || current.namespace == "mathml") && data.includes?('\0')
          unless is_html_integration_point?(current) || is_mathml_text_integration_point?(current)
            data = data.gsub('\0', '\ufffd')
          end
        end

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
      # Flush pending table text if we're in InTableText mode
      if @mode.in_table_text?
        flush_pending_table_text
      end

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
          # In fragment parsing, don't create implicit head
          if @fragment_context
            @mode = InsertionMode::InBody
          else
            # Create implicit head element
            head = Element.new("head")
            insert_element(head)
            @head_element = head
            @mode = InsertionMode::InHead
          end
        when .in_head?, .in_head_noscript?
          # Pop head and move to AfterHead
          @open_elements.pop if @open_elements.last?.try(&.name) == "head"
          @mode = InsertionMode::AfterHead
        when .after_head?
          # If we're inside a template or fragment parsing, don't create body
          if @template_insertion_modes.size > 0 || @fragment_context
            @mode = InsertionMode::InBody
          else
            # Create implicit body element
            body = Element.new("body")
            insert_element(body)
            @mode = InsertionMode::InBody
          end
        when .text?
          # Pop current element, return to original mode
          @open_elements.pop
          @mode = @original_mode || InsertionMode::InBody
          # If returning to AfterHead, we need to remove head from the stack
          # (it was pushed for processing script/style from AfterHead mode)
          if @mode.after_head? && @open_elements.last?.try(&.name) == "head"
            @open_elements.pop
          end
        when .in_template?
          # Handle EOF in template - pop until HTML template
          if @open_elements.any? { |el| el.name == "template" && el.namespace == "html" }
            pop_until_html_template
            clear_active_formatting_elements_to_last_marker
            @template_insertion_modes.pop if @template_insertion_modes.size > 0
            reset_insertion_mode
          else
            break
          end
        when .in_body?, .in_table?, .in_table_body?, .in_row?, .in_cell?,
             .in_select?, .in_select_in_table?, .in_column_group?, .in_caption?,
             .in_frameset?, .after_frameset?, .after_after_frameset?
          # Check for unclosed HTML templates first
          if @open_elements.any? { |el| el.name == "template" && el.namespace == "html" }
            pop_until_html_template
            clear_active_formatting_elements_to_last_marker
            @template_insertion_modes.pop if @template_insertion_modes.size > 0
            reset_insertion_mode
          else
            # Transition to after body for final cleanup
            @mode = InsertionMode::AfterBody
          end
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

      # Check for foreign content processing before mode-based dispatch
      # This mirrors Python html5lib's mainLoop approach
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "mathml")
        if should_use_foreign_content?(tag, current)
          if breaks_out_of_foreign_content?(tag, current.namespace)
            # Pop elements until we reach HTML namespace or integration point
            pop_until_html_or_integration_point
            # Fall through to reprocess in current insertion mode
          else
            # Stay in foreign content - create element in same namespace
            process_foreign_content_start_tag(tag, current.namespace)
            return
          end
        end
        # At integration point, fall through to normal mode handling
        # But first check if we're in a table mode without an actual table in scope
        # In that case, temporarily use IN_BODY mode (where table structure tags are ignored)
        if is_mathml_text_integration_point?(current) || is_html_integration_point?(current)
          if @mode != InsertionMode::InBody
            table_modes = {InsertionMode::InTable, InsertionMode::InTableBody,
                           InsertionMode::InRow, InsertionMode::InCell,
                           InsertionMode::InCaption, InsertionMode::InColumnGroup}
            if table_modes.includes?(@mode) && !has_element_in_table_scope?("table")
              # Temporarily use IN_BODY mode for this tag
              saved_mode = @mode
              @mode = InsertionMode::InBody
              process_in_body_start_tag(tag)
              # Restore mode if we're still in IN_BODY (i.e., mode wasn't changed by the handler)
              @mode = saved_mode if @mode == InsertionMode::InBody
              return
            end
          end
        end
      end

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
        when "title", "style", "script", "noframes"
          element = create_element(tag)
          insert_element(element)
          if name == "script"
            @tokenizer.try(&.set_state(Tokenizer::State::ScriptData))
          elsif name == "style" || name == "noframes"
            @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
          elsif name == "title"
            @tokenizer.try(&.set_state(Tokenizer::State::RCDATA))
          end
          @original_mode = @mode
          @mode = InsertionMode::Text
        when "noscript"
          # Scripting is disabled: parse noscript content as HTML
          element = create_element(tag)
          insert_element(element)
          @mode = InsertionMode::InHeadNoscript
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
      when .in_head_noscript?
        # Handle tokens in 'in head noscript' insertion mode (scripting disabled)
        case name
        when "html"
          # Process using in body rules
          process_in_body_start_tag(tag)
        when "basefont", "bgsound", "link", "meta", "noframes", "style"
          # Process using in head rules
          @mode = InsertionMode::InHead
          process_start_tag(tag)
          @mode = InsertionMode::InHeadNoscript
        when "head", "noscript"
          # Parse error, ignore
        else
          # Any other start tag: pop noscript, reprocess in head
          @open_elements.pop if @open_elements.last?.try(&.name) == "noscript"
          @mode = InsertionMode::InHead
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
            if @mode.text?
              # Script/style switched to Text mode - set original_mode to AfterHead
              # so we return there after content is processed
              @original_mode = InsertionMode::AfterHead
            else
              @open_elements.delete(head)
              @mode = InsertionMode::AfterHead if @mode.in_head?
            end
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
      when .in_caption?
        process_in_caption_start_tag(tag)
      when .in_template?
        process_in_template_start_tag(tag)
      when .in_column_group?
        process_in_column_group_start_tag(tag)
      when .in_select?, .in_select_in_table?
        process_in_select_start_tag(tag)
      when .in_frameset?
        process_in_frameset_start_tag(tag)
      when .after_frameset?
        process_after_frameset_start_tag(tag)
      when .after_after_body?
        # Any start tag in after-after-body mode: reprocess in body mode
        @mode = InsertionMode::InBody
        process_start_tag(tag)
      when .after_after_frameset?
        # html tag: process using in body rules
        # noframes: process using in head rules (RAWTEXT mode)
        # Any other start tag: ignore
        case name
        when "html"
          process_in_body_start_tag(tag)
        when "noframes"
          element = create_element(tag)
          insert_element(element)
          @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
          @original_mode = @mode
          @mode = InsertionMode::Text
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

    private def process_in_column_group_start_tag(tag : Tag) : Nil
      name = tag.name
      current = current_node

      case name
      when "html"
        # Process using in body rules
        process_in_body_start_tag(tag)
      when "col"
        # Insert and pop (void element)
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop
      when "template"
        # Delegate to in head rules
        @mode = InsertionMode::InHead
        process_start_tag(tag)
        # After template, stay in column group mode
      else
        # Anything else: if we're in a colgroup, pop it and switch to InTable
        if current && current.name == "colgroup"
          @open_elements.pop
          @mode = InsertionMode::InTable
          process_start_tag(tag)
        elsif current && current.name == "template"
          # In template column group context, ignore non-column content
        else
          # Pop colgroup and reprocess
          @open_elements.pop if current
          @mode = InsertionMode::InTable
          process_start_tag(tag)
        end
      end
    end

    private def process_in_select_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "html"
        # Process using in body rules
        process_in_body_start_tag(tag)
      when "option"
        if current_node.try(&.name) == "option"
          @open_elements.pop
        end
        element = create_element(tag)
        insert_element(element)
      when "optgroup"
        if current_node.try(&.name) == "option"
          @open_elements.pop
        end
        if current_node.try(&.name) == "optgroup"
          @open_elements.pop
        end
        element = create_element(tag)
        insert_element(element)
      when "select"
        # Close current select
        pop_until("select")
        reset_insertion_mode
      when "input", "textarea", "keygen"
        # Close current select and reprocess
        pop_until("select")
        reset_insertion_mode
        process_start_tag(tag)
      when "script", "template"
        # Process using in head rules
        @mode = InsertionMode::InHead
        process_start_tag(tag)
        # Mode was changed by process_start_tag
      when "svg"
        # Foreign elements in select - insert with namespace
        reconstruct_active_formatting_elements
        element = create_element(tag, Constants::NAMESPACE_SVG)
        insert_element(element)
        @open_elements.pop if tag.self_closing?
      when "math"
        # Foreign elements in select - insert with namespace
        reconstruct_active_formatting_elements
        element = create_element(tag, Constants::NAMESPACE_MATHML)
        insert_element(element)
        @open_elements.pop if tag.self_closing?
      when "p", "div", "span", "button", "datalist", "selectedcontent", "menuitem"
        # Allow common HTML elements in select (newer spec)
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop if tag.self_closing?
      when "br", "img"
        # Void elements allowed in select
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop
      when "hr"
        # Pop option and optgroup before inserting hr
        if current_node.try(&.name) == "option"
          @open_elements.pop
        end
        if current_node.try(&.name) == "optgroup"
          @open_elements.pop
        end
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop
      when "plaintext"
        # Plaintext element consumes all remaining text
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
      when "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr", "table"
        # Table-related tags: pop select and reprocess
        pop_until("select")
        reset_insertion_mode
        process_start_tag(tag)
      else
        # Ignore other start tags
      end
    end

    private def process_in_frameset_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "html"
        # Process using in body rules
        process_in_body_start_tag(tag)
      when "frameset"
        element = create_element(tag)
        insert_element(element)
      when "frame"
        # Void element
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop
      when "noframes"
        # Use RAWTEXT mode
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
        @original_mode = @mode
        @mode = InsertionMode::Text
      else
        # Ignore other start tags
      end
    end

    private def process_after_frameset_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "html"
        # Process using in body rules
        process_in_body_start_tag(tag)
      when "noframes"
        # Use RAWTEXT mode
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
        @original_mode = @mode
        @mode = InsertionMode::Text
      else
        # Ignore other start tags
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
      when "base", "basefont", "bgsound", "link", "meta"
        # Void head elements: just insert (don't push)
        element = create_element(tag)
        insert_element(element)
        @open_elements.pop
      when "title"
        # Handle title with RCDATA mode
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RCDATA))
        @original_mode = @mode  # Keep InTemplate as original!
        @mode = InsertionMode::Text
      when "script"
        # Handle script with ScriptData mode
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::ScriptData))
        @original_mode = @mode  # Keep InTemplate as original!
        @mode = InsertionMode::Text
      when "style", "noframes"
        # Handle style/noframes with RAWTEXT mode
        element = create_element(tag)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::RAWTEXT))
        @original_mode = @mode  # Keep InTemplate as original!
        @mode = InsertionMode::Text
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
        # Only restore InTable if mode wasn't changed (template switches to InTemplate)
        @mode = InsertionMode::InTable if @mode == InsertionMode::InHead
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
        # If there's no form element pointer and no template on the stack
        if @form_element.nil? && !@open_elements.any? { |el| el.name == "template" && el.namespace == "html" }
          form_element = create_element(tag)
          insert_element(form_element)
          @form_element = form_element
          @open_elements.pop  # Immediately pop it (form is invisible in table)
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

    private def process_in_caption_start_tag(tag : Tag) : Nil
      name = tag.name

      case name
      when "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"
        # These tags close the caption
        if has_element_in_table_scope?("caption")
          generate_implied_end_tags
          pop_until("caption")
          clear_active_formatting_elements_to_last_marker
          @mode = InsertionMode::InTable
          process_start_tag(tag)
        end
      when "table"
        # Close caption and reprocess
        if has_element_in_table_scope?("caption")
          generate_implied_end_tags
          pop_until("caption")
          clear_active_formatting_elements_to_last_marker
          @mode = InsertionMode::InTable
          process_start_tag(tag)
        else
          # Fragment parsing: no caption on stack - handle in body mode
          process_in_body_start_tag(tag)
        end
      else
        # Process using "in body" rules
        process_in_body_start_tag(tag)
      end
    end

    private def process_in_body_start_tag(tag : Tag) : Nil
      name = tag.name

      # Check if we're in foreign content (SVG or MathML)
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "mathml")
        # First check if we're at an integration point
        if should_use_foreign_content?(tag, current)
          # In foreign content, check for breakout
          if breaks_out_of_foreign_content?(tag, current.namespace)
            # Pop elements until we exit foreign content or reach integration point
            pop_until_html_or_integration_point
            # Process the tag in HTML context (fall through to normal handling)
          else
            # Stay in foreign content - create element in same namespace
            element = create_element(tag, current.namespace)
            insert_element(element)
            if tag.self_closing? || Constants::VOID_ELEMENTS.includes?(name)
              @open_elements.pop
            end
            return
          end
        end
        # At integration point or after breakout, fall through to HTML handling
      end

      case name
      when "html"
        # Inside template, ignore html start tag
        return if @template_insertion_modes.size > 0
        if html = @open_elements.first?
          tag.attrs.each do |k, v|
            html[k] = v unless html.has_attribute?(k)
          end
        end
      when "body"
        # Inside template, ignore body start tag
        return if @template_insertion_modes.size > 0
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
      when "button"
        # If there's already a button in scope, close it first
        if has_element_in_scope?("button")
          generate_implied_end_tags
          pop_until("button")
        end
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        @frameset_ok = false
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
      when "plaintext"
        close_p_if_in_button_scope
        element = create_element(tag)
        insert_element(element)
        @frameset_ok = false
        # PLAINTEXT state consumes all remaining input - no end tag
        @tokenizer.try(&.set_state(Tokenizer::State::PLAINTEXT))
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
      when "rb", "rtc"
        # Ruby elements: rb and rtc close rb, rt, rtc, rp
        if has_element_in_scope?("ruby")
          generate_implied_end_tags
          if cn = current_node
            if !{"rb", "rtc", "ruby"}.includes?(cn.name)
              # Parse error but continue
            end
          end
          pop_until_one_of({"rb", "rtc", "rp", "rt"})
        end
        element = create_element(tag)
        insert_element(element)
      when "rp", "rt"
        # Ruby elements: rp and rt close rb, rp, rt but NOT rtc
        if has_element_in_scope?("ruby")
          generate_implied_end_tags("rtc")
          if cn = current_node
            if !{"rb", "rtc", "rp", "rt", "ruby"}.includes?(cn.name)
              # Parse error but continue
            end
          end
          # Only pop rb, rp, rt - NOT rtc (rt and rp can be inside rtc)
          pop_until_one_of({"rb", "rp", "rt"})
        end
        element = create_element(tag)
        insert_element(element)
      when "span"
        element = create_element(tag)
        insert_element(element)
      when "svg"
        reconstruct_active_formatting_elements
        element = create_element(tag, Constants::NAMESPACE_SVG)
        insert_element(element)
        # Self-closing svg tag should be popped
        @open_elements.pop if tag.self_closing?
      when "math"
        reconstruct_active_formatting_elements
        element = create_element(tag, Constants::NAMESPACE_MATHML)
        insert_element(element)
        # Self-closing math tag should be popped
        @open_elements.pop if tag.self_closing?
      when "frameset"
        # Frameset in body mode - only allowed if frameset-ok is true
        if @frameset_ok
          # If the second element is body, remove it from its parent (the DOM)
          if @open_elements.size > 1
            second = @open_elements[1]
            if second.name == "body"
              second.parent.try(&.remove_child(second))
            end
          end
          # Pop all elements from stack except html
          while @open_elements.size > 1 && @open_elements.last?.try(&.name) != "html"
            @open_elements.pop
          end
          element = create_element(tag)
          insert_element(element)
          @mode = InsertionMode::InFrameset
        end
        # Otherwise ignore
      when "frame", "head"
        # Parse error - frame is only valid in frameset mode, head in head mode
        # Ignore in body mode
      when "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"
        # Table structure tags are ignored in body mode (parse error)
        # These are only valid inside tables
      when "template"
        # Template in body mode - process using in head rules
        element = create_element(tag)
        insert_element(element)
        push_onto_active_formatting_elements(ActiveFormattingMarker.new)
        @frameset_ok = false
        @mode = InsertionMode::InTemplate
        @template_insertion_modes << InsertionMode::InTemplate
      else
        # Default: reconstruct formatting elements and insert the element
        reconstruct_active_formatting_elements
        element = create_element(tag)
        insert_element(element)
        if Constants::VOID_ELEMENTS.includes?(name)
          @open_elements.pop
        end
      end
    end

    private def process_end_tag(tag : Tag) : Nil
      name = tag.name

      # Check for foreign content processing before mode-based dispatch
      # This mirrors Python html5lib's mainLoop approach for end tags
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "mathml")
        if process_foreign_content_end_tag(tag)
          return
        end
      end

      case @mode
      when .initial?
        # Ignore
      when .before_html?
        if {"head", "body", "html", "br"}.includes?(name)
          # Create html element and reprocess
          html = Element.new("html")
          @document.append_child(html)
          @open_elements << html
          @mode = InsertionMode::BeforeHead
          process_end_tag(tag)
        end
        # Other end tags are ignored
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
          # Handle template end tag - only match HTML namespace templates
          if @open_elements.any? { |el| el.name == "template" && el.namespace == "html" }
            generate_implied_end_tags
            pop_until_html_template
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
      when .in_head_noscript?
        if name == "noscript"
          # Pop noscript element
          @open_elements.pop if @open_elements.last?.try(&.name) == "noscript"
          @mode = InsertionMode::InHead
        elsif name == "br"
          # Pop noscript, reprocess in head
          @open_elements.pop if @open_elements.last?.try(&.name) == "noscript"
          @mode = InsertionMode::InHead
          process_end_tag(tag)
        end
        # Any other end tag: parse error, ignore
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
        # If returning to AfterHead, we need to remove head from the stack
        # (it was pushed for processing script/style from AfterHead mode)
        if @mode.after_head? && @open_elements.last?.try(&.name) == "head"
          @open_elements.pop
        end
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
          # Handle template end tag (same as in_head) - only match HTML namespace templates
          if @open_elements.any? { |el| el.name == "template" && el.namespace == "html" }
            generate_implied_end_tags
            pop_until_html_template
            clear_active_formatting_elements_to_last_marker
            @template_insertion_modes.pop if @template_insertion_modes.size > 0
            reset_insertion_mode
          end
        else
          # For other end tags, process using the current template insertion mode
          # This is already handled by reset_insertion_mode
          process_in_body_end_tag(tag)
        end
      when .in_caption?
        case name
        when "caption"
          if has_element_in_table_scope?("caption")
            generate_implied_end_tags
            pop_until("caption")
            clear_active_formatting_elements_to_last_marker
            @mode = InsertionMode::InTable
          end
        when "table"
          if has_element_in_table_scope?("caption")
            generate_implied_end_tags
            pop_until("caption")
            clear_active_formatting_elements_to_last_marker
            @mode = InsertionMode::InTable
            process_end_tag(tag)
          end
        when "body", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr"
          # Parse error - ignore
        else
          process_in_body_end_tag(tag)
        end
      when .in_column_group?
        case name
        when "colgroup"
          current = current_node
          # Don't pop template element - only pop actual colgroup
          if current && current.name == "colgroup"
            @open_elements.pop
            @mode = InsertionMode::InTable
          end
          # Otherwise ignore
        when "col"
          # Ignore end tag for col (void element)
        when "template"
          # Delegate to in head rules
          @mode = InsertionMode::InHead
          process_end_tag(tag)
        else
          # Pop colgroup and reprocess in table mode
          current = current_node
          if current && current.name == "colgroup"
            @open_elements.pop
            @mode = InsertionMode::InTable
            process_end_tag(tag)
          end
          # Otherwise ignore
        end
      when .in_row?
        # Handle row end tags specially
        case name
        when "tr"
          if has_element_in_table_scope?("tr")
            clear_stack_back_to_table_row_context
            @open_elements.pop if current_node.try(&.name) == "tr"
            # When in a template, restore template mode; otherwise use IN_TABLE_BODY
            if @template_insertion_modes.size > 0
              @mode = @template_insertion_modes.last
            else
              @mode = InsertionMode::InTableBody
            end
          end
        when "table"
          if has_element_in_table_scope?("tr")
            clear_stack_back_to_table_row_context
            @open_elements.pop if current_node.try(&.name) == "tr"
            # Restore mode and reprocess
            if @template_insertion_modes.size > 0
              @mode = @template_insertion_modes.last
            else
              @mode = InsertionMode::InTableBody
            end
            process_end_tag(tag)
          end
        when "tbody", "tfoot", "thead"
          if has_element_in_table_scope?(name)
            if has_element_in_table_scope?("tr")
              clear_stack_back_to_table_row_context
              @open_elements.pop if current_node.try(&.name) == "tr"
              if @template_insertion_modes.size > 0
                @mode = @template_insertion_modes.last
              else
                @mode = InsertionMode::InTableBody
              end
            end
            process_end_tag(tag)
          end
        when "body", "caption", "col", "colgroup", "html", "td", "th"
          # Parse error - ignore
        else
          # For other end tags, process using in body rules with foster parenting
          @foster_parenting = true
          process_in_body_end_tag(tag)
          @foster_parenting = false
        end
      when .in_table?, .in_table_body?
        # Handle table end tags
        case name
        when "table"
          if has_element_in_table_scope?("table")
            pop_until("table")
            reset_insertion_mode
          end
        when "tbody", "tfoot", "thead"
          if @mode.in_table_body? && has_element_in_table_scope?(name)
            clear_stack_back_to_table_body_context
            @open_elements.pop
            @mode = InsertionMode::InTable
          elsif has_element_in_table_scope?(name)
            # In InTable mode, pop table sections and reprocess
            pop_until(name)
            reset_insertion_mode
            process_end_tag(tag)
          end
        when "body", "caption", "col", "colgroup", "html", "td", "th", "tr"
          # Ignore these end tags in table context
        else
          # For other end tags, process using in body rules with foster parenting
          @foster_parenting = true
          process_in_body_end_tag(tag)
          @foster_parenting = false
        end
      when .in_select?, .in_select_in_table?
        case name
        when "optgroup"
          # Pop optgroup if current is option and previous is optgroup
          if current_node.try(&.name) == "option"
            if @open_elements.size >= 2 && @open_elements[-2].name == "optgroup"
              @open_elements.pop # Pop option
              @open_elements.pop # Pop optgroup
            end
          elsif current_node.try(&.name) == "optgroup"
            @open_elements.pop
          end
          # Otherwise ignore
        when "option"
          if current_node.try(&.name) == "option"
            @open_elements.pop
          end
          # Otherwise ignore
        when "select"
          pop_until("select")
          reset_insertion_mode
        when "template"
          # Process using in head rules
          @mode = InsertionMode::InHead
          process_end_tag(tag)
        when "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr", "table"
          # Table-related end tags: pop select and reprocess
          pop_until("select")
          reset_insertion_mode
          process_end_tag(tag)
        else
          # Ignore other end tags
        end
      when .in_frameset?
        case name
        when "frameset"
          # Don't pop if current is html (root)
          if current_node.try(&.name) != "html"
            @open_elements.pop
            if current_node.try(&.name) != "frameset"
              @mode = InsertionMode::AfterFrameset
            end
          end
        else
          # Ignore other end tags
        end
      when .after_frameset?
        case name
        when "html"
          @mode = InsertionMode::AfterAfterFrameset
        else
          # Ignore other end tags
        end
      when .in_cell?
        case name
        when "td", "th"
          if has_element_in_table_scope?(name)
            generate_implied_end_tags
            pop_until(name)
            clear_active_formatting_elements_to_last_marker
            @mode = InsertionMode::InRow
          end
        when "body", "caption", "col", "colgroup", "html"
          # Ignore
        when "table", "tbody", "tfoot", "thead", "tr"
          if has_element_in_table_scope?(name)
            close_cell
            process_end_tag(tag)
          end
        else
          process_in_body_end_tag(tag)
        end
      else
        # Default behavior
        pop_until(name)
      end
    end

    private def process_in_body_end_tag(tag : Tag) : Nil
      name = tag.name

      # Check if we're in foreign content (SVG or MathML)
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "mathml")
        # In foreign content, look for matching element in the foreign content part of the stack
        # Pop elements in reverse order, looking for a match
        (@open_elements.size - 1).downto(0) do |i|
          el = @open_elements[i]
          # If we find an HTML element, stop - fall through to normal processing
          break if el.namespace == "html"
          # If we find a matching element in foreign content, pop up to it
          if el.name.downcase == name.downcase
            ((@open_elements.size - 1) - i + 1).times { @open_elements.pop }
            return
          end
        end
        # No match in foreign content - fall through to normal HTML processing
      end

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
        # Handle template end tag - only match HTML namespace templates
        if @open_elements.any? { |el| el.name == "template" && el.namespace == "html" }
          generate_implied_end_tags
          pop_until_html_template
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
      attrs = tag.attrs
      # Adjust SVG tag names and attributes
      if namespace == "svg"
        name = adjust_svg_tag_name(name)
        attrs = adjust_svg_attributes(attrs)
      elsif namespace == "mathml"
        attrs = adjust_mathml_attributes(attrs)
      end
      Element.new(name, attrs, namespace)
    end

    private def adjust_svg_tag_name(name : String) : String
      Constants::SVG_TAG_ADJUSTMENTS[name]? || name
    end

    private def adjust_svg_attributes(attrs : Hash(String, String?)) : Hash(String, String?)
      adjusted = {} of String => String?
      attrs.each do |key, value|
        adjusted_key = Constants::SVG_ATTRIBUTE_ADJUSTMENTS[key]? || key
        adjusted[adjusted_key] = value
      end
      adjusted
    end

    private def adjust_mathml_attributes(attrs : Hash(String, String?)) : Hash(String, String?)
      adjusted = {} of String => String?
      attrs.each do |key, value|
        adjusted_key = Constants::MATHML_ATTRIBUTE_ADJUSTMENTS[key]? || key
        adjusted[adjusted_key] = value
      end
      adjusted
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

    # Flush pending table text and restore original mode
    private def flush_pending_table_text : Nil
      data = @pending_table_text.join
      @pending_table_text.clear

      original_mode = @table_text_original_mode || InsertionMode::InTable
      @table_text_original_mode = nil
      @mode = original_mode

      return if data.empty?

      # If all whitespace, insert as normal text
      if all_ascii_whitespace?(data)
        insert_text(data)
        return
      end

      # Contains non-whitespace - foster parent with reconstruct formatting
      @foster_parenting = true
      reconstruct_active_formatting_elements
      insert_text(data)
      @foster_parenting = false
    end

    # Check if foster parenting should occur for a given target element
    # Similar to Python's _should_foster_parenting
    private def should_foster_parenting?(target : Element, for_tag : String? = nil, is_text : Bool = false) : Bool
      return false unless @foster_parenting
      return false unless TABLE_FOSTER_TARGETS.includes?(target.name)
      return true if is_text
      return false if for_tag && TABLE_ALLOWED_CHILDREN.includes?(for_tag)
      true
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
        # Match elements in HTML namespace (or no namespace)
        break if el.name == name && (el.namespace == "html" || el.namespace.nil?)
      end
    end

    # Pop elements until we find an HTML namespace template element
    private def pop_until_html_template : Nil
      while el = @open_elements.pop?
        break if el.name == "template" && el.namespace == "html"
      end
    end

    private def pop_until_one_of(names : Set(String) | Tuple) : Nil
      # Pop elements until we find one with a matching name, or reach an element not in the set
      while el = @open_elements.last?
        if names.includes?(el.name)
          @open_elements.pop
        else
          break
        end
      end
    end

    private def lstrip_ascii_whitespace(str : String) : String
      # Strip only ASCII whitespace: space, tab, newline, form feed, carriage return
      # Not all Unicode whitespace (e.g., &ThickSpace; should be preserved)
      i = 0
      while i < str.size
        c = str[i]
        break unless c == ' ' || c == '\t' || c == '\n' || c == '\f' || c == '\r'
        i += 1
      end
      i == 0 ? str : str[i..]
    end

    private def all_ascii_whitespace?(str : String) : Bool
      str.each_char.all? { |c| c == ' ' || c == '\t' || c == '\n' || c == '\f' || c == '\r' }
    end

    private def has_element_in_scope?(name : String, check_integration_points : Bool = true) : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        # For HTML elements, check terminators
        if el.namespace == "html"
          return false if scope_terminators.includes?(el.name)
        elsif check_integration_points
          # For foreign content elements, integration points terminate scope
          return false if is_html_integration_point?(el) || is_mathml_text_integration_point?(el)
        end
      end
      false
    end

    private def has_element_in_button_scope?(name : String) : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "button"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        # For HTML elements, check terminators
        if el.namespace == "html"
          return false if scope_terminators.includes?(el.name)
        else
          # For foreign content elements, integration points terminate scope
          return false if is_html_integration_point?(el) || is_mathml_text_integration_point?(el)
        end
      end
      false
    end

    private def has_element_in_list_scope?(name : String) : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "ol", "ul"}
      @open_elements.reverse_each do |el|
        return true if el.name == name
        # For HTML elements, check terminators
        if el.namespace == "html"
          return false if scope_terminators.includes?(el.name)
        else
          # For foreign content elements, integration points terminate scope
          return false if is_html_integration_point?(el) || is_mathml_text_integration_point?(el)
        end
      end
      false
    end

    private def has_heading_in_scope? : Bool
      scope_terminators = {"applet", "caption", "html", "table", "td", "th", "marquee", "object", "template"}
      @open_elements.reverse_each do |el|
        return true if {"h1", "h2", "h3", "h4", "h5", "h6"}.includes?(el.name)
        # For HTML elements, check terminators
        if el.namespace == "html"
          return false if scope_terminators.includes?(el.name)
        else
          # For foreign content elements, integration points terminate scope
          return false if is_html_integration_point?(el) || is_mathml_text_integration_point?(el)
        end
      end
      false
    end

    private def has_element_in_table_scope?(name : String) : Bool
      # Table scope doesn't check integration points (per spec)
      scope_terminators = {"html", "table", "template"}
      @open_elements.reverse_each do |el|
        # Only match HTML namespace elements
        if el.namespace == "html" || el.namespace.nil?
          return true if el.name == name
          return false if scope_terminators.includes?(el.name)
        end
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
        when "head"
          # If head element and not last, switch to "in head" mode
          unless last
            @mode = InsertionMode::InHead
            return
          end
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
        # Only HTML elements can be special - foreign content (SVG/MathML) is never special
        furthest_block : Element? = nil
        furthest_block_idx : Int32? = nil

        ((stack_idx + 1)...@open_elements.size).each do |i|
          el = @open_elements[i]
          # Only consider HTML namespace elements as special
          if el.namespace == "html" && Constants::SPECIAL_ELEMENTS.includes?(el.name)
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
          # Remove last_node from its current parent first
          if parent = last_node.parent
            parent.children.delete(last_node)
          end

          # Check if we should foster parent based on common ancestor
          # This is key for table foster parenting during AAA
          last_node_name = last_node.is_a?(Element) ? last_node.name : nil
          if should_foster_parenting?(common_ancestor, last_node_name)
            foster_parent_node(last_node)
          else
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
        while child = furthest_block.children.first?
          furthest_block.children.shift
          child.parent = new_formatting_element
          new_formatting_element.children << child
        end

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
      # Find the last HTML template and table in the stack
      template_idx = @open_elements.rindex { |el| el.name == "template" && el.namespace == "html" }
      table_idx = @open_elements.rindex { |el| el.name == "table" }

      # If template exists and (no table OR template is after table), insert into template_content
      if template_idx && (table_idx.nil? || template_idx > table_idx)
        template = @open_elements[template_idx]
        if template_contents = template.template_contents
          # If inserting text and last child is text, merge them
          if node.is_a?(Text)
            if last = template_contents.children.last?
              if last.is_a?(Text)
                last.data += node.data
                return
              end
            end
          end
          template_contents.append_child(node)
          return
        end
      end

      if table_idx
        table = @open_elements[table_idx]
        if parent = table.parent
          # Insert before the table
          idx = parent.children.index(table) || parent.children.size

          # If inserting text and previous sibling is text, merge them
          if node.is_a?(Text) && idx > 0
            if prev = parent.children[idx - 1]?
              if prev.is_a?(Text)
                prev.data += node.data
                return
              end
            end
          end

          node.parent = parent
          parent.children.insert(idx, node)
          return
        elsif table_idx > 0
          # Insert as last child of element before table in stack
          foster_parent = @open_elements[table_idx - 1]

          # If inserting text and last child is text, merge them
          if node.is_a?(Text)
            if last = foster_parent.children.last?
              if last.is_a?(Text)
                last.data += node.data
                return
              end
            end
          end

          foster_parent.append_child(node)
          return
        end
      end

      # Fallback: insert in body or html
      if body = @open_elements.find { |el| el.name == "body" }
        # Merge text nodes if possible
        if node.is_a?(Text) && (last = body.children.last?) && last.is_a?(Text)
          last.data += node.data
        else
          body.append_child(node)
        end
      elsif html = @open_elements.first?
        html.append_child(node)
      end
    end

    # Check if element is an HTML integration point (allows HTML content inside foreign content)
    private def is_html_integration_point?(element : Element?) : Bool
      return false unless element

      # SVG foreignObject, desc, title are integration points
      if element.namespace == "svg"
        return {"foreignObject", "desc", "title"}.includes?(element.name)
      end

      # MathML annotation-xml with specific encoding is an HTML integration point
      if element.namespace == "mathml" && element.name == "annotation-xml"
        encoding = element["encoding"]
        if encoding
          enc_lower = encoding.downcase
          return enc_lower == "text/html" || enc_lower == "application/xhtml+xml"
        end
      end

      false
    end

    # Check if element is a MathML text integration point
    private def is_mathml_text_integration_point?(element : Element?) : Bool
      return false unless element
      return false unless element.namespace == "mathml"
      {"mi", "mo", "mn", "ms", "mtext"}.includes?(element.name)
    end

    # Determine if a start tag should be processed in foreign content mode
    # Process a start tag in foreign content (SVG or MathML)
    private def process_foreign_content_start_tag(tag : Tag, namespace : String) : Nil
      name = tag.name
      attrs = tag.attrs

      # Adjust names and attributes for the namespace
      if namespace == "svg"
        name = adjust_svg_tag_name(name)
        attrs = adjust_svg_attributes(attrs)
      elsif namespace == "mathml"
        attrs = adjust_mathml_attributes(attrs)
      end
      # Note: adjust_foreign_attributes for xlink/xml/xmlns prefixes not yet implemented

      # Create element in the foreign namespace
      element = Element.new(name, attrs, namespace)
      insert_element(element)

      # Self-closing tags should be popped
      if tag.self_closing?
        @open_elements.pop
      end
    end

    # Process an end tag in foreign content (SVG or MathML)
    # Returns true if handled, false if should fall through to mode handling
    private def process_foreign_content_end_tag(tag : Tag) : Bool
      name = tag.name.downcase
      current = current_node
      return false unless current

      # Special case: </br> and </p> end tags trigger breakout from foreign content
      # They should be reprocessed in HTML mode to create implicit opening tags
      if name == "br" || name == "p"
        pop_until_html_or_integration_point
        # Don't reset_insertion_mode - stay in current mode (InBody for fragment parsing)
        return false  # Fall through to HTML mode handling
      end

      # For script end tag, handle specially
      if name == "script" && current.name == "script" && current.namespace == "svg"
        @open_elements.pop
        return true
      end

      # Look for matching element in open elements stack (from top to bottom)
      # For SVG, comparison should be case-insensitive
      @open_elements.reverse_each.with_index do |element, index|
        actual_index = @open_elements.size - 1 - index

        # Check if element matches (case-sensitive for mathml, adjusted for svg)
        matches = if element.namespace == "svg"
          element.name.downcase == name.downcase
        else
          element.name == name
        end

        if matches
          # Check if this is the fragment context element - can't pop that
          if @fragment_context_element && element.same?(@fragment_context_element)
            # Parse error - unexpected end tag in fragment context
            return true
          end
          # Pop elements from the stack down to and including this one
          (@open_elements.size - actual_index).times { @open_elements.pop }
          return true
        end

        # If we reach an HTML element, stop searching and fall through
        if element.namespace == "html"
          return false
        end
      end

      false
    end

    private def should_use_foreign_content?(tag : Tag, current : Element) : Bool
      # At MathML text integration points, most start tags fall through to HTML
      if is_mathml_text_integration_point?(current)
        # Only mglyph and malignmark stay in foreign content
        return {"mglyph", "malignmark"}.includes?(tag.name)
      end

      # At annotation-xml in MathML, svg tag falls through to HTML mode
      if current.namespace == "mathml" && current.name == "annotation-xml"
        return tag.name != "svg"
      end

      # At HTML integration points, start tags fall through to HTML
      if is_html_integration_point?(current)
        return false
      end

      # Otherwise, stay in foreign content
      true
    end

    # Pop elements until we reach HTML namespace or an integration point
    private def pop_until_html_or_integration_point : Nil
      while element = current_node
        break if element.namespace == "html"
        break if is_html_integration_point?(element)
        break if is_mathml_text_integration_point?(element)
        # Don't pop the fragment context element
        if @fragment_context_element && element.same?(@fragment_context_element)
          break
        end
        @open_elements.pop
      end
    end

    # Check if a tag should break out of foreign content
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
      # with data like "[CDATA[content]]" or "[CDATA[content" (unclosed).
      # Convert these to text nodes.
      current = current_node
      if current && (current.namespace == "svg" || current.namespace == "mathml")
        if comment.data.starts_with?("[CDATA[")
          # Extract content: remove "[CDATA[" prefix and "]]" suffix if present
          cdata_content = comment.data[7..]
          if cdata_content.ends_with?("]]")
            cdata_content = cdata_content[0..-3]
          end
          # Only insert non-empty content
          unless cdata_content.empty?
            # Normalize line endings: CRLF -> LF, CR -> LF
            cdata_content = cdata_content.gsub("\r\n", "\n").gsub("\r", "\n")
            node = Text.new(cdata_content)
            insert_node(node)
          end
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

      # If we're in an HTML integration point and encounter structural tags,
      # ignore them (they're parse errors in this context)
      if current && is_html_integration_point?(current) &&
         {"tr", "td", "th", "tbody", "thead", "tfoot", "table", "caption", "col", "colgroup",
          "html", "head", "body", "frameset"}.includes?(tag.name)
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
      when "script"
        element = Element.new(name, tag.attrs, namespace)
        insert_element(element)
        @tokenizer.try(&.set_state(Tokenizer::State::ScriptData))
      when "style"
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
