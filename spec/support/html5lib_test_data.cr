require "../../src/just_html"
require "json"

module HTML5LibTestData
  # Test case for tree construction tests
  class TreeConstructionTest
    property data : String
    property errors : Array(String)
    property document : String
    property document_fragment : String?
    property script_directive : String?
    property xml_coercion : Bool
    property iframe_srcdoc : Bool

    def initialize(@data : String, @errors : Array(String), @document : String,
                   @document_fragment : String? = nil, @script_directive : String? = nil,
                   @xml_coercion : Bool = false, @iframe_srcdoc : Bool = false)
    end
  end

  # Parse .dat file into test cases
  def self.parse_tree_construction_tests(content : String) : Array(TreeConstructionTest)
    tests = [] of TreeConstructionTest
    lines = content.split('\n')
    i = 0

    while i < lines.size
      # Skip until we find #data
      while i < lines.size && lines[i] != "#data"
        i += 1
      end
      break if i >= lines.size

      test = parse_single_test(lines, i)
      if test
        tests << test[:test]
        i = test[:next_line]
      else
        i += 1
      end
    end

    tests
  end

  private def self.parse_single_test(lines : Array(String), start : Int32) : NamedTuple(test: TreeConstructionTest, next_line: Int32)?
    return nil unless lines[start] == "#data"

    i = start + 1
    data_lines = [] of String

    # Read data section
    while i < lines.size && !lines[i].starts_with?("#")
      data_lines << lines[i]
      i += 1
    end

    # Join data lines - preserve newlines but remove trailing one if empty
    data = data_lines.join('\n')
    if data.ends_with?('\n') && !data_lines.empty? && data_lines.last.empty?
      data = data[0...-1]
    end

    errors = [] of String
    document_lines = [] of String
    document_fragment : String? = nil
    script_directive : String? = nil
    xml_coercion = false
    iframe_srcdoc = false

    # Parse remaining sections
    while i < lines.size
      case lines[i]
      when "#errors"
        i += 1
        while i < lines.size && !lines[i].starts_with?("#")
          errors << lines[i] unless lines[i].empty?
          i += 1
        end
      when "#new-errors"
        i += 1
        while i < lines.size && !lines[i].starts_with?("#")
          i += 1
        end
      when "#document-fragment"
        i += 1
        if i < lines.size && !lines[i].starts_with?("#")
          document_fragment = lines[i].strip
          i += 1
        end
      when "#script-off"
        script_directive = "script-off"
        i += 1
      when "#script-on"
        script_directive = "script-on"
        i += 1
      when "#xml-coercion"
        xml_coercion = true
        i += 1
      when "#iframe-srcdoc"
        iframe_srcdoc = true
        i += 1
      when "#document"
        i += 1
        while i < lines.size && !lines[i].starts_with?("#")
          document_lines << lines[i]
          i += 1
        end
        break # End of test case
      else
        break
      end
    end

    document = document_lines.join('\n')

    # Decode escape sequences in data
    data = decode_escapes(data)

    {test: TreeConstructionTest.new(data, errors, document, document_fragment, script_directive, xml_coercion, iframe_srcdoc), next_line: i}
  end

  # Decode escape sequences \xNN and \uNNNN
  def self.decode_escapes(text : String) : String
    return text unless text.includes?("\\x") || text.includes?("\\u")

    result = String::Builder.new
    i = 0
    while i < text.size
      if text[i] == '\\' && i + 3 < text.size && text[i + 1] == 'x'
        # \xNN hex escape
        hex = text[i + 2, 2]
        if hex.matches?(/^[0-9A-Fa-f]{2}$/)
          code = hex.to_i(16)
          result << safe_chr(code)
          i += 4
          next
        end
      elsif text[i] == '\\' && i + 5 < text.size && text[i + 1] == 'u'
        # \uNNNN unicode escape
        hex = text[i + 2, 4]
        if hex.matches?(/^[0-9A-Fa-f]{4}$/)
          code = hex.to_i(16)
          result << safe_chr(code)
          i += 6
          next
        end
      end
      result << text[i]
      i += 1
    end
    result.to_s
  end

  # Safely convert codepoint to character, handling surrogates
  private def self.safe_chr(code : Int32) : Char
    # Surrogate range (0xD800-0xDFFF) is invalid in UTF-8
    # Replace with replacement character
    if code >= 0xD800 && code <= 0xDFFF
      '\uFFFD'
    else
      code.chr
    end
  end

  # Serialize document to html5lib test format
  def self.serialize_to_test_format(node : JustHTML::Node, indent : Int32 = 0) : String
    result = String::Builder.new
    serialize_node(node, result, indent)
    result.to_s.strip
  end

  # Known foreign attributes that need space-separated format in test output
  FOREIGN_ATTR_DISPLAY = {
    "xlink:actuate" => "xlink actuate",
    "xlink:arcrole" => "xlink arcrole",
    "xlink:href"    => "xlink href",
    "xlink:role"    => "xlink role",
    "xlink:show"    => "xlink show",
    "xlink:title"   => "xlink title",
    "xlink:type"    => "xlink type",
    "xml:lang"      => "xml lang",
    "xml:space"     => "xml space",
    "xmlns:xlink"   => "xmlns xlink",
  }

  # Format foreign attribute name for test output: "xlink:show" -> "xlink show"
  private def self.format_foreign_attr(name : String) : String
    FOREIGN_ATTR_DISPLAY[name]? || name
  end

  private def self.serialize_node(node : JustHTML::Node, builder : String::Builder, indent : Int32) : Nil
    prefix = "| " + ("  " * indent)

    case node
    when JustHTML::Document
      node.children.each { |child| serialize_node(child, builder, indent) }
    when JustHTML::DocumentFragment
      node.children.each { |child| serialize_node(child, builder, indent) }
    when JustHTML::DoctypeNode
      builder << prefix << "<!DOCTYPE "
      builder << (node.doctype_name || "")
      if public_id = node.public_id
        builder << " \"" << public_id << "\""
        builder << " \"" << (node.system_id || "") << "\""
      elsif system_id = node.system_id
        builder << " \"\" \"" << system_id << "\""
      end
      builder << ">\n"
    when JustHTML::Element
      builder << prefix << "<"
      # Namespace prefix for non-HTML elements
      case node.namespace
      when "svg"
        builder << "svg "
      when "mathml"
        builder << "math "
      end
      builder << node.name << ">\n"

      # Attributes in alphabetical order by display name
      # Only use space-separated format for foreign elements (SVG/MathML)
      is_foreign = node.namespace == "svg" || node.namespace == "mathml"
      attrs = node.attrs.to_a.map { |k, v| {is_foreign ? format_foreign_attr(k) : k, v} }.sort_by { |k, _| k }
      attrs.each do |attr_name, attr_value|
        builder << prefix << "  " << attr_name
        builder << "=\"" << (attr_value || "") << "\""
        builder << "\n"
      end

      # Template elements have their content in a document fragment
      if node.name == "template" && (template_contents = node.template_contents)
        builder << prefix << "  content\n"
        template_contents.children.each { |child| serialize_node(child, builder, indent + 2) }
      else
        # Regular children
        node.children.each { |child| serialize_node(child, builder, indent + 1) }
      end
    when JustHTML::Text
      builder << prefix << "\"" << node.data << "\"\n"
    when JustHTML::Comment
      builder << prefix << "<!-- " << node.data << " -->\n"
    end
  end

  # Token collector sink for tokenizer tests
  class TokenCollector
    include JustHTML::TokenSink

    def initialize(@tokens : Array(JSON::Any))
    end

    def process_tag(tag : JustHTML::Tag) : Nil
      if tag.kind == :start
        arr = ["StartTag", tag.name] of JSON::Any::Type
        attrs = {} of String => JSON::Any
        tag.attrs.each { |k, v| attrs[k] = JSON::Any.new(v || "") }
        arr << attrs
        arr << true if tag.self_closing?
        @tokens << JSON::Any.new(arr.map { |v|
          case v
          when String then JSON::Any.new(v)
          when Bool   then JSON::Any.new(v)
          when Hash   then JSON::Any.new(v)
          else             JSON::Any.new(v.to_s)
          end
        })
      else
        @tokens << JSON.parse(["EndTag", tag.name].to_json)
      end
    end

    def process_comment(comment : JustHTML::CommentToken) : Nil
      @tokens << JSON.parse(["Comment", comment.data].to_json)
    end

    def process_doctype(doctype : JustHTML::Doctype) : Nil
      @tokens << JSON.parse(["DOCTYPE", doctype.name, doctype.public_id, doctype.system_id, !doctype.force_quirks?].to_json)
    end

    def process_characters(data : String) : Nil
      @tokens << JSON.parse(["Character", data].to_json)
    end

    def process_eof : Nil
    end
  end
end
