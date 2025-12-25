module JustHTML
  module TokenSink
    abstract def process_tag(tag : Tag) : Nil
    abstract def process_comment(comment : CommentToken) : Nil
    abstract def process_doctype(doctype : Doctype) : Nil
    abstract def process_characters(data : String) : Nil
    abstract def process_eof : Nil
  end

  class Tokenizer
    enum State
      Data
      RCDATA
      RAWTEXT
      ScriptData
      PLAINTEXT
      TagOpen
      EndTagOpen
      TagName
      RCDATALessThanSign
      RCDATAEndTagOpen
      RCDATAEndTagName
      RAWTEXTLessThanSign
      RAWTEXTEndTagOpen
      RAWTEXTEndTagName
      ScriptDataLessThanSign
      ScriptDataEndTagOpen
      ScriptDataEndTagName
      ScriptDataEscapeStart
      ScriptDataEscapeStartDash
      ScriptDataEscaped
      ScriptDataEscapedDash
      ScriptDataEscapedDashDash
      ScriptDataEscapedLessThanSign
      ScriptDataEscapedEndTagOpen
      ScriptDataEscapedEndTagName
      ScriptDataDoubleEscapeStart
      ScriptDataDoubleEscaped
      ScriptDataDoubleEscapedDash
      ScriptDataDoubleEscapedDashDash
      ScriptDataDoubleEscapedLessThanSign
      ScriptDataDoubleEscapeEnd
      BeforeAttributeName
      AttributeName
      AfterAttributeName
      BeforeAttributeValue
      AttributeValueDoubleQuoted
      AttributeValueSingleQuoted
      AttributeValueUnquoted
      AfterAttributeValueQuoted
      SelfClosingStartTag
      BogusComment
      MarkupDeclarationOpen
      CommentStart
      CommentStartDash
      Comment
      CommentLessThanSign
      CommentLessThanSignBang
      CommentLessThanSignBangDash
      CommentLessThanSignBangDashDash
      CommentEndDash
      CommentEnd
      CommentEndBang
      DOCTYPE
      BeforeDOCTYPEName
      DOCTYPEName
      AfterDOCTYPEName
      AfterDOCTYPEPublicKeyword
      BeforeDOCTYPEPublicIdentifier
      DOCTYPEPublicIdentifierDoubleQuoted
      DOCTYPEPublicIdentifierSingleQuoted
      AfterDOCTYPEPublicIdentifier
      BetweenDOCTYPEPublicAndSystemIdentifiers
      AfterDOCTYPESystemKeyword
      BeforeDOCTYPESystemIdentifier
      DOCTYPESystemIdentifierDoubleQuoted
      DOCTYPESystemIdentifierSingleQuoted
      AfterDOCTYPESystemIdentifier
      BogusDOCTYPE
      CDATASection
      CDATASectionBracket
      CDATASectionEnd
      CharacterReference
      NamedCharacterReference
      AmbiguousAmpersand
      NumericCharacterReference
      HexadecimalCharacterReferenceStart
      DecimalCharacterReferenceStart
      HexadecimalCharacterReference
      DecimalCharacterReference
      NumericCharacterReferenceEnd
    end

    getter errors : Array(ParseError)

    @sink : TokenSink
    @state : State
    @return_state : State
    @buffer : String
    @pos : Int32
    @length : Int32
    @reconsume : Bool
    @current_char : Char?

    # Current tag being built
    @current_tag_name : String::Builder
    @current_tag_name_cached : String?
    @current_tag_kind : Tag::Kind
    @current_tag_attrs : Hash(String, String?)
    @current_tag_self_closing : Bool
    @current_attr_name : String::Builder
    @current_attr_value : String::Builder

    # Current comment/doctype being built
    @current_comment : String::Builder
    @current_doctype_name : String::Builder
    @current_doctype_public : String::Builder
    @current_doctype_system : String::Builder
    @current_doctype_force_quirks : Bool

    # Text buffer for character tokens
    @text_buffer : String::Builder

    # Last start tag name (for appropriate end tag matching)
    @last_start_tag_name : String

    # Temp buffer for character reference
    @temp_buffer : String::Builder

    # Character reference code
    @char_ref_code : Int32

    def initialize(@sink : TokenSink, @collect_errors : Bool = false)
      @state = State::Data
      @return_state = State::Data
      @buffer = ""
      @pos = 0
      @length = 0
      @reconsume = false
      @current_char = nil
      @errors = [] of ParseError

      @current_tag_name = String::Builder.new
      @current_tag_name_cached = nil
      @current_tag_kind = Tag::Kind::Start
      @current_tag_attrs = {} of String => String?
      @current_tag_self_closing = false
      @current_attr_name = String::Builder.new
      @current_attr_value = String::Builder.new

      @current_comment = String::Builder.new
      @current_doctype_name = String::Builder.new
      @current_doctype_public = String::Builder.new
      @current_doctype_system = String::Builder.new
      @current_doctype_force_quirks = false

      @text_buffer = String::Builder.new
      @last_start_tag_name = ""
      @temp_buffer = String::Builder.new
      @char_ref_code = 0
    end

    def run(html : String) : Nil
      @buffer = html
      @length = html.size
      @pos = 0

      # Discard BOM if present
      if @length > 0 && @buffer[0] == '\uFEFF'
        @pos = 1
      end

      loop do
        break if step
      end

      # Flush any remaining text
      flush_text
      @sink.process_eof
    end

    private def step : Bool
      # Returns true on EOF
      if @reconsume
        @reconsume = false
      else
        if @pos >= @length
          @current_char = nil
        else
          @current_char = @buffer[@pos]
          @pos += 1
        end
      end

      process_state
    end

    private def process_state : Bool
      case @state
      when .data?                              then state_data
      when .rcdata?                            then state_rcdata
      when .rawtext?                           then state_rawtext
      when .script_data?                       then state_script_data
      when .plaintext?                         then state_plaintext
      when .tag_open?                          then state_tag_open
      when .end_tag_open?                      then state_end_tag_open
      when .tag_name?                          then state_tag_name
      when .rcdata_less_than_sign?             then state_rcdata_less_than_sign
      when .rcdata_end_tag_open?               then state_rcdata_end_tag_open
      when .rcdata_end_tag_name?               then state_rcdata_end_tag_name
      when .rawtext_less_than_sign?            then state_rawtext_less_than_sign
      when .rawtext_end_tag_open?              then state_rawtext_end_tag_open
      when .rawtext_end_tag_name?              then state_rawtext_end_tag_name
      when .before_attribute_name?             then state_before_attribute_name
      when .attribute_name?                    then state_attribute_name
      when .after_attribute_name?              then state_after_attribute_name
      when .before_attribute_value?            then state_before_attribute_value
      when .attribute_value_double_quoted?     then state_attribute_value_double_quoted
      when .attribute_value_single_quoted?     then state_attribute_value_single_quoted
      when .attribute_value_unquoted?          then state_attribute_value_unquoted
      when .after_attribute_value_quoted?      then state_after_attribute_value_quoted
      when .self_closing_start_tag?            then state_self_closing_start_tag
      when .bogus_comment?                     then state_bogus_comment
      when .markup_declaration_open?           then state_markup_declaration_open
      when .comment_start?                     then state_comment_start
      when .comment_start_dash?                then state_comment_start_dash
      when .comment?                           then state_comment
      when .comment_less_than_sign?            then state_comment_less_than_sign
      when .comment_less_than_sign_bang?       then state_comment_less_than_sign_bang
      when .comment_less_than_sign_bang_dash?  then state_comment_less_than_sign_bang_dash
      when .comment_less_than_sign_bang_dash_dash? then state_comment_less_than_sign_bang_dash_dash
      when .comment_end_dash?                  then state_comment_end_dash
      when .comment_end?                       then state_comment_end
      when .comment_end_bang?                  then state_comment_end_bang
      when .doctype?                           then state_doctype
      when .before_doctype_name?               then state_before_doctype_name
      when .doctype_name?                      then state_doctype_name
      when .after_doctype_name?                then state_after_doctype_name
      when .after_doctype_public_keyword?      then state_after_doctype_public_keyword
      when .before_doctype_public_identifier?  then state_before_doctype_public_identifier
      when .doctype_public_identifier_double_quoted? then state_doctype_public_identifier_double_quoted
      when .doctype_public_identifier_single_quoted? then state_doctype_public_identifier_single_quoted
      when .after_doctype_public_identifier?   then state_after_doctype_public_identifier
      when .between_doctype_public_and_system_identifiers? then state_between_doctype_public_and_system_identifiers
      when .after_doctype_system_keyword?      then state_after_doctype_system_keyword
      when .before_doctype_system_identifier?  then state_before_doctype_system_identifier
      when .doctype_system_identifier_double_quoted? then state_doctype_system_identifier_double_quoted
      when .doctype_system_identifier_single_quoted? then state_doctype_system_identifier_single_quoted
      when .after_doctype_system_identifier?   then state_after_doctype_system_identifier
      when .bogus_doctype?                     then state_bogus_doctype
      when .character_reference?               then state_character_reference
      when .named_character_reference?         then state_named_character_reference
      when .ambiguous_ampersand?               then state_ambiguous_ampersand
      when .numeric_character_reference?       then state_numeric_character_reference
      when .hexadecimal_character_reference_start? then state_hexadecimal_character_reference_start
      when .decimal_character_reference_start? then state_decimal_character_reference_start
      when .hexadecimal_character_reference?   then state_hexadecimal_character_reference
      when .decimal_character_reference?       then state_decimal_character_reference
      when .numeric_character_reference_end?   then state_numeric_character_reference_end
      else
        false
      end
    end

    # State handlers

    private def state_data : Bool
      case c = @current_char
      when nil
        flush_text
        true # EOF
      when '&'
        @return_state = State::Data
        @state = State::CharacterReference
        false
      when '<'
        flush_text
        @state = State::TagOpen
        false
      when '\0'
        add_error("unexpected-null-character")
        @text_buffer << '\uFFFD'
        false
      else
        @text_buffer << c
        false
      end
    end

    private def state_rcdata : Bool
      case c = @current_char
      when nil
        flush_text
        true
      when '&'
        @return_state = State::RCDATA
        @state = State::CharacterReference
        false
      when '<'
        @state = State::RCDATALessThanSign
        false
      when '\0'
        add_error("unexpected-null-character")
        @text_buffer << '\uFFFD'
        false
      else
        @text_buffer << c
        false
      end
    end

    private def state_rawtext : Bool
      case c = @current_char
      when nil
        flush_text
        true
      when '<'
        @state = State::RAWTEXTLessThanSign
        false
      when '\0'
        add_error("unexpected-null-character")
        @text_buffer << '\uFFFD'
        false
      else
        @text_buffer << c
        false
      end
    end

    private def state_script_data : Bool
      case c = @current_char
      when nil
        flush_text
        true
      when '<'
        @state = State::ScriptDataLessThanSign
        false
      when '\0'
        add_error("unexpected-null-character")
        @text_buffer << '\uFFFD'
        false
      else
        @text_buffer << c
        false
      end
    end

    private def state_plaintext : Bool
      case c = @current_char
      when nil
        flush_text
        true
      when '\0'
        add_error("unexpected-null-character")
        @text_buffer << '\uFFFD'
        false
      else
        @text_buffer << c
        false
      end
    end

    private def state_tag_open : Bool
      case c = @current_char
      when nil
        add_error("eof-before-tag-name")
        @text_buffer << '<'
        flush_text
        true
      when '!'
        @state = State::MarkupDeclarationOpen
        false
      when '/'
        @state = State::EndTagOpen
        false
      when '?'
        add_error("unexpected-question-mark-instead-of-tag-name")
        @current_comment = String::Builder.new
        @state = State::BogusComment
        @reconsume = true
        false
      when .ascii_letter?
        @current_tag_name = String::Builder.new
        @current_tag_name_cached = nil
        @current_tag_kind = Tag::Kind::Start
        @current_tag_attrs = {} of String => String?
        @current_tag_self_closing = false
        @state = State::TagName
        @reconsume = true
        false
      else
        add_error("invalid-first-character-of-tag-name")
        @text_buffer << '<'
        @state = State::Data
        @reconsume = true
        false
      end
    end

    private def state_end_tag_open : Bool
      case c = @current_char
      when nil
        add_error("eof-before-tag-name")
        @text_buffer << '<'
        @text_buffer << '/'
        flush_text
        true
      when '>'
        add_error("missing-end-tag-name")
        @state = State::Data
        false
      when .ascii_letter?
        @current_tag_name = String::Builder.new
        @current_tag_name_cached = nil
        @current_tag_kind = Tag::Kind::End
        @current_tag_attrs = {} of String => String?
        @current_tag_self_closing = false
        @state = State::TagName
        @reconsume = true
        false
      else
        add_error("invalid-first-character-of-tag-name")
        @current_comment = String::Builder.new
        @state = State::BogusComment
        @reconsume = true
        false
      end
    end

    private def state_tag_name : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '\t', '\n', '\f', ' '
        @state = State::BeforeAttributeName
        false
      when '/'
        @state = State::SelfClosingStartTag
        false
      when '>'
        saved_state = @state
        emit_current_tag
        # Only reset to Data if tree builder didn't change the state
        @state = State::Data if @state == saved_state
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_tag_name << '\uFFFD'
        false
      else
        @current_tag_name << c.downcase
        false
      end
    end

    private def state_rcdata_less_than_sign : Bool
      case c = @current_char
      when '/'
        @temp_buffer = String::Builder.new
        @state = State::RCDATAEndTagOpen
        false
      else
        @text_buffer << '<'
        @state = State::RCDATA
        @reconsume = true
        false
      end
    end

    private def state_rcdata_end_tag_open : Bool
      c = @current_char
      if c && c.ascii_letter?
        @current_tag_name = String::Builder.new
        @current_tag_name_cached = nil
        @current_tag_kind = Tag::Kind::End
        @current_tag_attrs = {} of String => String?
        @current_tag_self_closing = false
        @state = State::RCDATAEndTagName
        @reconsume = true
        false
      else
        @text_buffer << '<'
        @text_buffer << '/'
        @state = State::RCDATA
        @reconsume = true
        false
      end
    end

    private def state_rcdata_end_tag_name : Bool
      c = @current_char
      if c == '\t' || c == '\n' || c == '\f' || c == ' '
        if is_appropriate_end_tag?
          @state = State::BeforeAttributeName
          return false
        end
      elsif c == '/'
        if is_appropriate_end_tag?
          @state = State::SelfClosingStartTag
          return false
        end
      elsif c == '>'
        if is_appropriate_end_tag?
          flush_text
          emit_current_tag
          @state = State::Data
          return false
        end
      elsif c && c.ascii_letter?
        @current_tag_name << c.downcase
        @temp_buffer << c
        return false
      end

      @text_buffer << '<'
      @text_buffer << '/'
      @text_buffer << @temp_buffer.to_s
      @state = State::RCDATA
      @reconsume = true
      false
    end

    private def state_rawtext_less_than_sign : Bool
      case c = @current_char
      when '/'
        @temp_buffer = String::Builder.new
        @state = State::RAWTEXTEndTagOpen
        false
      else
        @text_buffer << '<'
        @state = State::RAWTEXT
        @reconsume = true
        false
      end
    end

    private def state_rawtext_end_tag_open : Bool
      c = @current_char
      if c && c.ascii_letter?
        @current_tag_name = String::Builder.new
        @current_tag_name_cached = nil
        @current_tag_kind = Tag::Kind::End
        @current_tag_attrs = {} of String => String?
        @current_tag_self_closing = false
        @state = State::RAWTEXTEndTagName
        @reconsume = true
        false
      else
        @text_buffer << '<'
        @text_buffer << '/'
        @state = State::RAWTEXT
        @reconsume = true
        false
      end
    end

    private def state_rawtext_end_tag_name : Bool
      c = @current_char
      if c == '\t' || c == '\n' || c == '\f' || c == ' '
        if is_appropriate_end_tag?
          @state = State::BeforeAttributeName
          return false
        end
      elsif c == '/'
        if is_appropriate_end_tag?
          @state = State::SelfClosingStartTag
          return false
        end
      elsif c == '>'
        if is_appropriate_end_tag?
          flush_text
          emit_current_tag
          @state = State::Data
          return false
        end
      elsif c && c.ascii_letter?
        @current_tag_name << c.downcase
        @temp_buffer << c
        return false
      end

      @text_buffer << '<'
      @text_buffer << '/'
      @text_buffer << @temp_buffer.to_s
      @state = State::RAWTEXT
      @reconsume = true
      false
    end

    private def state_before_attribute_name : Bool
      case c = @current_char
      when nil
        @state = State::AfterAttributeName
        @reconsume = true
        false
      when '\t', '\n', '\f', ' '
        # Ignore whitespace
        false
      when '/', '>'
        @state = State::AfterAttributeName
        @reconsume = true
        false
      when '='
        add_error("unexpected-equals-sign-before-attribute-name")
        @current_attr_name = String::Builder.new
        @current_attr_name << c
        @current_attr_value = String::Builder.new
        @state = State::AttributeName
        false
      else
        @current_attr_name = String::Builder.new
        @current_attr_value = String::Builder.new
        @state = State::AttributeName
        @reconsume = true
        false
      end
    end

    private def state_attribute_name : Bool
      case c = @current_char
      when nil, '\t', '\n', '\f', ' ', '/', '>'
        finish_attribute_name
        @state = State::AfterAttributeName
        @reconsume = true
        false
      when '='
        finish_attribute_name
        @state = State::BeforeAttributeValue
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_attr_name << '\uFFFD'
        false
      when '"', '\'', '<'
        add_error("unexpected-character-in-attribute-name")
        @current_attr_name << c
        false
      else
        @current_attr_name << c.downcase
        false
      end
    end

    private def state_after_attribute_name : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '\t', '\n', '\f', ' '
        false
      when '/'
        finish_attribute_without_value
        @state = State::SelfClosingStartTag
        false
      when '='
        @state = State::BeforeAttributeValue
        false
      when '>'
        finish_attribute_without_value
        saved_state = @state
        emit_current_tag
        @state = State::Data if @state == saved_state
        false
      else
        finish_attribute_without_value
        @current_attr_name = String::Builder.new
        @current_attr_value = String::Builder.new
        @state = State::AttributeName
        @reconsume = true
        false
      end
    end

    private def state_before_attribute_value : Bool
      case c = @current_char
      when '\t', '\n', '\f', ' '
        false
      when '"'
        @state = State::AttributeValueDoubleQuoted
        false
      when '\''
        @state = State::AttributeValueSingleQuoted
        false
      when '>'
        add_error("missing-attribute-value")
        saved_state = @state
        emit_current_tag
        @state = State::Data if @state == saved_state
        false
      else
        @state = State::AttributeValueUnquoted
        @reconsume = true
        false
      end
    end

    private def state_attribute_value_double_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '"'
        finish_attribute
        @state = State::AfterAttributeValueQuoted
        false
      when '&'
        @return_state = State::AttributeValueDoubleQuoted
        @state = State::CharacterReference
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_attr_value << '\uFFFD'
        false
      else
        @current_attr_value << c
        false
      end
    end

    private def state_attribute_value_single_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '\''
        finish_attribute
        @state = State::AfterAttributeValueQuoted
        false
      when '&'
        @return_state = State::AttributeValueSingleQuoted
        @state = State::CharacterReference
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_attr_value << '\uFFFD'
        false
      else
        @current_attr_value << c
        false
      end
    end

    private def state_attribute_value_unquoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '\t', '\n', '\f', ' '
        finish_attribute
        @state = State::BeforeAttributeName
        false
      when '&'
        @return_state = State::AttributeValueUnquoted
        @state = State::CharacterReference
        false
      when '>'
        finish_attribute
        saved_state = @state
        emit_current_tag
        @state = State::Data if @state == saved_state
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_attr_value << '\uFFFD'
        false
      when '"', '\'', '<', '=', '`'
        add_error("unexpected-character-in-unquoted-attribute-value")
        @current_attr_value << c
        false
      else
        @current_attr_value << c
        false
      end
    end

    private def state_after_attribute_value_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '\t', '\n', '\f', ' '
        @state = State::BeforeAttributeName
        false
      when '/'
        @state = State::SelfClosingStartTag
        false
      when '>'
        saved_state = @state
        emit_current_tag
        @state = State::Data if @state == saved_state
        false
      else
        add_error("missing-whitespace-between-attributes")
        @state = State::BeforeAttributeName
        @reconsume = true
        false
      end
    end

    private def state_self_closing_start_tag : Bool
      case c = @current_char
      when nil
        add_error("eof-in-tag")
        true
      when '>'
        @current_tag_self_closing = true
        saved_state = @state
        emit_current_tag
        @state = State::Data if @state == saved_state
        false
      else
        add_error("unexpected-solidus-in-tag")
        @state = State::BeforeAttributeName
        @reconsume = true
        false
      end
    end

    private def state_bogus_comment : Bool
      case c = @current_char
      when nil
        emit_comment
        true
      when '>'
        emit_comment
        @state = State::Data
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_comment << '\uFFFD'
        false
      else
        @current_comment << c
        false
      end
    end

    private def state_markup_declaration_open : Bool
      # This state looks ahead without consuming - we need to check from @pos - 1
      # because the previous state already advanced @pos
      check_pos = @pos - 1

      if check_from("--", check_pos)
        @pos = check_pos + 2
        @current_comment = String::Builder.new
        @state = State::CommentStart
      elsif check_from_case_insensitive("DOCTYPE", check_pos)
        @pos = check_pos + 7
        @state = State::DOCTYPE
      elsif check_from("[CDATA[", check_pos)
        @pos = check_pos + 7
        # CDATA is only allowed in foreign content
        # For now, treat as bogus comment
        add_error("cdata-in-html-content")
        @current_comment = String::Builder.new
        @current_comment << "[CDATA["
        @state = State::BogusComment
      else
        add_error("incorrectly-opened-comment")
        @current_comment = String::Builder.new
        @state = State::BogusComment
        @reconsume = true
      end
      false
    end

    private def state_comment_start : Bool
      case c = @current_char
      when nil
        add_error("eof-in-comment")
        emit_comment
        true
      when '-'
        @state = State::CommentStartDash
        false
      when '>'
        add_error("abrupt-closing-of-empty-comment")
        emit_comment
        @state = State::Data
        false
      else
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_comment_start_dash : Bool
      case c = @current_char
      when nil
        add_error("eof-in-comment")
        emit_comment
        true
      when '-'
        @state = State::CommentEnd
        false
      when '>'
        add_error("abrupt-closing-of-empty-comment")
        emit_comment
        @state = State::Data
        false
      else
        @current_comment << '-'
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_comment : Bool
      case c = @current_char
      when nil
        add_error("eof-in-comment")
        emit_comment
        true
      when '<'
        @current_comment << c
        @state = State::CommentLessThanSign
        false
      when '-'
        @state = State::CommentEndDash
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_comment << '\uFFFD'
        false
      else
        @current_comment << c
        false
      end
    end

    private def state_comment_less_than_sign : Bool
      case c = @current_char
      when '!'
        @current_comment << c
        @state = State::CommentLessThanSignBang
        false
      when '<'
        @current_comment << c
        false
      else
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_comment_less_than_sign_bang : Bool
      case c = @current_char
      when '-'
        @state = State::CommentLessThanSignBangDash
        false
      else
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_comment_less_than_sign_bang_dash : Bool
      case c = @current_char
      when '-'
        @state = State::CommentLessThanSignBangDashDash
        false
      else
        @state = State::CommentEndDash
        @reconsume = true
        false
      end
    end

    private def state_comment_less_than_sign_bang_dash_dash : Bool
      case c = @current_char
      when nil, '>'
        @state = State::CommentEnd
        @reconsume = true
        false
      else
        add_error("nested-comment")
        @state = State::CommentEnd
        @reconsume = true
        false
      end
    end

    private def state_comment_end_dash : Bool
      case c = @current_char
      when nil
        add_error("eof-in-comment")
        emit_comment
        true
      when '-'
        @state = State::CommentEnd
        false
      else
        @current_comment << '-'
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_comment_end : Bool
      case c = @current_char
      when nil
        add_error("eof-in-comment")
        emit_comment
        true
      when '>'
        emit_comment
        @state = State::Data
        false
      when '!'
        @state = State::CommentEndBang
        false
      when '-'
        @current_comment << '-'
        false
      else
        @current_comment << "--"
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_comment_end_bang : Bool
      case c = @current_char
      when nil
        add_error("eof-in-comment")
        emit_comment
        true
      when '-'
        @current_comment << "--!"
        @state = State::CommentEndDash
        false
      when '>'
        add_error("incorrectly-closed-comment")
        emit_comment
        @state = State::Data
        false
      else
        @current_comment << "--!"
        @state = State::Comment
        @reconsume = true
        false
      end
    end

    private def state_doctype : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        @state = State::BeforeDOCTYPEName
        false
      when '>'
        @state = State::BeforeDOCTYPEName
        @reconsume = true
        false
      else
        add_error("missing-whitespace-before-doctype-name")
        @state = State::BeforeDOCTYPEName
        @reconsume = true
        false
      end
    end

    private def state_before_doctype_name : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        false
      when '>'
        add_error("missing-doctype-name")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_doctype_name = String::Builder.new
        @current_doctype_name << '\uFFFD'
        @state = State::DOCTYPEName
        false
      else
        @current_doctype_name = String::Builder.new
        @current_doctype_name << c.downcase
        @state = State::DOCTYPEName
        false
      end
    end

    private def state_doctype_name : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        @state = State::AfterDOCTYPEName
        false
      when '>'
        emit_doctype
        @state = State::Data
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_doctype_name << '\uFFFD'
        false
      else
        @current_doctype_name << c.downcase
        false
      end
    end

    private def state_after_doctype_name : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        false
      when '>'
        emit_doctype
        @state = State::Data
        false
      else
        if check_ahead_case_insensitive("UBLIC")
          @pos += 5
          @state = State::AfterDOCTYPEPublicKeyword
        elsif check_ahead_case_insensitive("YSTEM")
          @pos += 5
          @state = State::AfterDOCTYPESystemKeyword
        else
          add_error("invalid-character-sequence-after-doctype-name")
          @current_doctype_force_quirks = true
          @state = State::BogusDOCTYPE
          @reconsume = true
        end
        false
      end
    end

    private def state_after_doctype_public_keyword : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        @state = State::BeforeDOCTYPEPublicIdentifier
        false
      when '"'
        add_error("missing-whitespace-after-doctype-public-keyword")
        @current_doctype_public = String::Builder.new
        @state = State::DOCTYPEPublicIdentifierDoubleQuoted
        false
      when '\''
        add_error("missing-whitespace-after-doctype-public-keyword")
        @current_doctype_public = String::Builder.new
        @state = State::DOCTYPEPublicIdentifierSingleQuoted
        false
      when '>'
        add_error("missing-doctype-public-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        add_error("missing-quote-before-doctype-public-identifier")
        @current_doctype_force_quirks = true
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_before_doctype_public_identifier : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        false
      when '"'
        @current_doctype_public = String::Builder.new
        @state = State::DOCTYPEPublicIdentifierDoubleQuoted
        false
      when '\''
        @current_doctype_public = String::Builder.new
        @state = State::DOCTYPEPublicIdentifierSingleQuoted
        false
      when '>'
        add_error("missing-doctype-public-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        add_error("missing-quote-before-doctype-public-identifier")
        @current_doctype_force_quirks = true
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_doctype_public_identifier_double_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '"'
        @state = State::AfterDOCTYPEPublicIdentifier
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_doctype_public << '\uFFFD'
        false
      when '>'
        add_error("abrupt-doctype-public-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        @current_doctype_public << c
        false
      end
    end

    private def state_doctype_public_identifier_single_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\''
        @state = State::AfterDOCTYPEPublicIdentifier
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_doctype_public << '\uFFFD'
        false
      when '>'
        add_error("abrupt-doctype-public-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        @current_doctype_public << c
        false
      end
    end

    private def state_after_doctype_public_identifier : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        @state = State::BetweenDOCTYPEPublicAndSystemIdentifiers
        false
      when '>'
        emit_doctype
        @state = State::Data
        false
      when '"'
        add_error("missing-whitespace-between-doctype-public-and-system-identifiers")
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierDoubleQuoted
        false
      when '\''
        add_error("missing-whitespace-between-doctype-public-and-system-identifiers")
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierSingleQuoted
        false
      else
        add_error("missing-quote-before-doctype-system-identifier")
        @current_doctype_force_quirks = true
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_between_doctype_public_and_system_identifiers : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        false
      when '>'
        emit_doctype
        @state = State::Data
        false
      when '"'
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierDoubleQuoted
        false
      when '\''
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierSingleQuoted
        false
      else
        add_error("missing-quote-before-doctype-system-identifier")
        @current_doctype_force_quirks = true
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_after_doctype_system_keyword : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        @state = State::BeforeDOCTYPESystemIdentifier
        false
      when '"'
        add_error("missing-whitespace-after-doctype-system-keyword")
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierDoubleQuoted
        false
      when '\''
        add_error("missing-whitespace-after-doctype-system-keyword")
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierSingleQuoted
        false
      when '>'
        add_error("missing-doctype-system-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        add_error("missing-quote-before-doctype-system-identifier")
        @current_doctype_force_quirks = true
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_before_doctype_system_identifier : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        false
      when '"'
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierDoubleQuoted
        false
      when '\''
        @current_doctype_system = String::Builder.new
        @state = State::DOCTYPESystemIdentifierSingleQuoted
        false
      when '>'
        add_error("missing-doctype-system-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        add_error("missing-quote-before-doctype-system-identifier")
        @current_doctype_force_quirks = true
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_doctype_system_identifier_double_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '"'
        @state = State::AfterDOCTYPESystemIdentifier
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_doctype_system << '\uFFFD'
        false
      when '>'
        add_error("abrupt-doctype-system-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        @current_doctype_system << c
        false
      end
    end

    private def state_doctype_system_identifier_single_quoted : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\''
        @state = State::AfterDOCTYPESystemIdentifier
        false
      when '\0'
        add_error("unexpected-null-character")
        @current_doctype_system << '\uFFFD'
        false
      when '>'
        add_error("abrupt-doctype-system-identifier")
        @current_doctype_force_quirks = true
        emit_doctype
        @state = State::Data
        false
      else
        @current_doctype_system << c
        false
      end
    end

    private def state_after_doctype_system_identifier : Bool
      case c = @current_char
      when nil
        add_error("eof-in-doctype")
        @current_doctype_force_quirks = true
        emit_doctype
        true
      when '\t', '\n', '\f', ' '
        false
      when '>'
        emit_doctype
        @state = State::Data
        false
      else
        add_error("unexpected-character-after-doctype-system-identifier")
        @state = State::BogusDOCTYPE
        @reconsume = true
        false
      end
    end

    private def state_bogus_doctype : Bool
      case c = @current_char
      when nil
        emit_doctype
        true
      when '>'
        emit_doctype
        @state = State::Data
        false
      when '\0'
        add_error("unexpected-null-character")
        false
      else
        false
      end
    end

    # Character reference states

    private def state_character_reference : Bool
      @temp_buffer = String::Builder.new
      @temp_buffer << '&'

      c = @current_char
      if c && c.ascii_alphanumeric?
        @state = State::NamedCharacterReference
        @reconsume = true
        false
      elsif c == '#'
        @temp_buffer << c
        @state = State::NumericCharacterReference
        false
      else
        flush_code_points_consumed_as_character_reference
        @state = @return_state
        @reconsume = true
        false
      end
    end

    private def state_named_character_reference : Bool
      # Consume as many alphanumeric characters as possible
      # and try to match against the entity table
      name_start = @pos - 1
      name_end = @pos - 1

      # Build up the entity name
      while @pos < @length
        c = @buffer[@pos]
        break unless c.ascii_alphanumeric?
        name_end = @pos
        @pos += 1
      end

      # Check for semicolon
      has_semicolon = @pos < @length && @buffer[@pos] == ';'

      # Try to find a match
      entity_name = @buffer[name_start..name_end]
      @temp_buffer << entity_name

      if has_semicolon
        @temp_buffer << ';'
        @pos += 1
      end

      # Look up entity
      if replacement = Entities::NAMED_ENTITIES[entity_name]?
        # Check attribute value context rules for legacy entities
        if !has_semicolon && is_in_attribute_value?
          next_char = @pos < @length ? @buffer[@pos] : nil
          if next_char && (next_char == '=' || next_char.ascii_alphanumeric?)
            flush_code_points_consumed_as_character_reference
            @state = @return_state
            return false
          end
        end

        if !has_semicolon
          add_error("missing-semicolon-after-character-reference")
        end

        @temp_buffer = String::Builder.new
        @temp_buffer << replacement
        flush_code_points_consumed_as_character_reference
        @state = @return_state
      else
        # No match - try prefix matching for legacy entities
        # For simplicity, just output the temp buffer as-is
        flush_code_points_consumed_as_character_reference
        @state = State::AmbiguousAmpersand
      end
      false
    end

    private def state_ambiguous_ampersand : Bool
      c = @current_char
      if c && c.ascii_alphanumeric?
        if is_in_attribute_value?
          @current_attr_value << c
        else
          @text_buffer << c
        end
        false
      elsif c == ';'
        add_error("unknown-named-character-reference")
        @state = @return_state
        @reconsume = true
        false
      else
        @state = @return_state
        @reconsume = true
        false
      end
    end

    private def state_numeric_character_reference : Bool
      @char_ref_code = 0

      case c = @current_char
      when 'x', 'X'
        @temp_buffer << c
        @state = State::HexadecimalCharacterReferenceStart
        false
      else
        @state = State::DecimalCharacterReferenceStart
        @reconsume = true
        false
      end
    end

    private def state_hexadecimal_character_reference_start : Bool
      c = @current_char
      if c && c.hex?
        @state = State::HexadecimalCharacterReference
        @reconsume = true
        false
      else
        add_error("absence-of-digits-in-numeric-character-reference")
        flush_code_points_consumed_as_character_reference
        @state = @return_state
        @reconsume = true
        false
      end
    end

    private def state_decimal_character_reference_start : Bool
      c = @current_char
      if c && c.ascii_number?
        @state = State::DecimalCharacterReference
        @reconsume = true
        false
      else
        add_error("absence-of-digits-in-numeric-character-reference")
        flush_code_points_consumed_as_character_reference
        @state = @return_state
        @reconsume = true
        false
      end
    end

    private def state_hexadecimal_character_reference : Bool
      c = @current_char
      if c && c.ascii_number?
        digit = c.ord - '0'.ord
        # Prevent arithmetic overflow by capping at max value
        # Once we exceed 0x10FFFF, keep the overflow value to trigger proper error handling
        new_code = @char_ref_code.to_i64 * 16 + digit
        @char_ref_code = new_code > Int32::MAX ? Int32::MAX : new_code.to_i32
        false
      elsif c && ('A'..'F').includes?(c)
        digit = c.ord - 'A'.ord + 10
        new_code = @char_ref_code.to_i64 * 16 + digit
        @char_ref_code = new_code > Int32::MAX ? Int32::MAX : new_code.to_i32
        false
      elsif c && ('a'..'f').includes?(c)
        digit = c.ord - 'a'.ord + 10
        new_code = @char_ref_code.to_i64 * 16 + digit
        @char_ref_code = new_code > Int32::MAX ? Int32::MAX : new_code.to_i32
        false
      elsif c == ';'
        @state = State::NumericCharacterReferenceEnd
        false
      else
        add_error("missing-semicolon-after-character-reference")
        @state = State::NumericCharacterReferenceEnd
        @reconsume = true
        false
      end
    end

    private def state_decimal_character_reference : Bool
      c = @current_char
      if c && c.ascii_number?
        digit = c.ord - '0'.ord
        # Prevent arithmetic overflow by capping at max value
        # Once we exceed 0x10FFFF, keep the overflow value to trigger proper error handling
        new_code = @char_ref_code.to_i64 * 10 + digit
        @char_ref_code = new_code > Int32::MAX ? Int32::MAX : new_code.to_i32
        false
      elsif c == ';'
        @state = State::NumericCharacterReferenceEnd
        false
      else
        add_error("missing-semicolon-after-character-reference")
        @state = State::NumericCharacterReferenceEnd
        @reconsume = true
        false
      end
    end

    private def state_numeric_character_reference_end : Bool
      code = @char_ref_code

      if code == 0
        add_error("null-character-reference")
        code = 0xFFFD
      elsif code > 0x10FFFF
        add_error("character-reference-outside-unicode-range")
        code = 0xFFFD
      elsif (0xD800..0xDFFF).includes?(code)
        add_error("surrogate-character-reference")
        code = 0xFFFD
      elsif (0xFDD0..0xFDEF).includes?(code) || {0xFFFE, 0xFFFF, 0x1FFFE, 0x1FFFF, 0x2FFFE, 0x2FFFF, 0x3FFFE, 0x3FFFF, 0x4FFFE, 0x4FFFF, 0x5FFFE, 0x5FFFF, 0x6FFFE, 0x6FFFF, 0x7FFFE, 0x7FFFF, 0x8FFFE, 0x8FFFF, 0x9FFFE, 0x9FFFF, 0xAFFFE, 0xAFFFF, 0xBFFFE, 0xBFFFF, 0xCFFFE, 0xCFFFF, 0xDFFFE, 0xDFFFF, 0xEFFFE, 0xEFFFF, 0xFFFFE, 0xFFFFF, 0x10FFFE, 0x10FFFF}.includes?(code)
        add_error("noncharacter-character-reference")
      elsif code == 0x0D || ((0x0001..0x001F).includes?(code) && !(0x0009..0x000A).includes?(code) && code != 0x000C)
        add_error("control-character-reference")
      end

      # Apply numeric character reference replacements
      if replacement = Entities::NUMERIC_REPLACEMENTS[code]?
        code = replacement
      end

      @temp_buffer = String::Builder.new
      @temp_buffer << code.chr
      flush_code_points_consumed_as_character_reference
      @state = @return_state
      @reconsume = true
      false
    end

    # Helper methods

    private def check_ahead(expected : String) : Bool
      check_from(expected, @pos)
    end

    private def check_ahead_case_insensitive(expected : String) : Bool
      check_from_case_insensitive(expected, @pos)
    end

    private def check_from(expected : String, pos : Int32) : Bool
      return false if pos + expected.size > @length
      expected.each_char_with_index do |c, i|
        return false if @buffer[pos + i] != c
      end
      true
    end

    private def check_from_case_insensitive(expected : String, pos : Int32) : Bool
      return false if pos + expected.size > @length
      expected.each_char_with_index do |c, i|
        return false if @buffer[pos + i].downcase != c.downcase
      end
      true
    end

    private def is_appropriate_end_tag? : Bool
      current_tag_name_string == @last_start_tag_name
    end

    private def current_tag_name_string : String
      @current_tag_name_cached ||= @current_tag_name.to_s
    end

    private def reset_tag_name_cache : Nil
      @current_tag_name_cached = nil
    end

    private def is_in_attribute_value? : Bool
      @return_state == State::AttributeValueDoubleQuoted ||
        @return_state == State::AttributeValueSingleQuoted ||
        @return_state == State::AttributeValueUnquoted
    end

    private def flush_text : Nil
      text = @text_buffer.to_s
      unless text.empty?
        @sink.process_characters(text)
      end
      @text_buffer = String::Builder.new
    end

    private def flush_code_points_consumed_as_character_reference : Nil
      if is_in_attribute_value?
        @current_attr_value << @temp_buffer.to_s
      else
        @text_buffer << @temp_buffer.to_s
      end
    end

    private def finish_attribute_name : Nil
      # Just note that we have a pending attribute name
      # The value will be set by finish_attribute or when we encounter another attribute
    end

    private def finish_attribute : Nil
      name = @current_attr_name.to_s
      value = @current_attr_value.to_s
      @current_attr_name = String::Builder.new
      @current_attr_value = String::Builder.new
      unless name.empty?
        # Only add if not already present (first occurrence wins per HTML5 spec)
        unless @current_tag_attrs.has_key?(name)
          @current_tag_attrs[name] = value
        end
      end
    end

    private def finish_attribute_without_value : Nil
      name = @current_attr_name.to_s
      @current_attr_name = String::Builder.new
      @current_attr_value = String::Builder.new
      unless name.empty?
        unless @current_tag_attrs.has_key?(name)
          @current_tag_attrs[name] = nil
        end
      end
    end

    private def emit_current_tag : Nil
      name = current_tag_name_string
      tag = Tag.new(@current_tag_kind, name, @current_tag_attrs, @current_tag_self_closing)
      if @current_tag_kind == Tag::Kind::Start
        @last_start_tag_name = name
      end
      reset_tag_name_cache
      @sink.process_tag(tag)
    end

    private def emit_comment : Nil
      comment = CommentToken.new(@current_comment.to_s)
      @sink.process_comment(comment)
    end

    private def emit_doctype : Nil
      name = @current_doctype_name.to_s
      name = nil if name.empty?
      public_id = @current_doctype_public.to_s
      public_id = nil if public_id.empty?
      system_id = @current_doctype_system.to_s
      system_id = nil if system_id.empty?
      doctype = Doctype.new(name, public_id, system_id, @current_doctype_force_quirks)
      @sink.process_doctype(doctype)

      # Reset doctype state
      @current_doctype_name = String::Builder.new
      @current_doctype_public = String::Builder.new
      @current_doctype_system = String::Builder.new
      @current_doctype_force_quirks = false
    end

    private def add_error(code : String) : Nil
      return unless @collect_errors
      @errors << ParseError.new(code)
    end

    # Public method to allow tree builder to switch tokenizer state
    def set_state(state : State) : Nil
      @state = state
    end

    # Helper to check if element has specific attribute
    def has_attribute?(attr : String) : Bool
      @current_tag_attrs.has_key?(attr)
    end
  end
end
