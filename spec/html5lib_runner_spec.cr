require "./spec_helper"

# html5lib-tests runner for tree construction tests
# Test format: https://github.com/html5lib/html5lib-tests

module HTML5LibTests
  # Parse html5lib tree construction test format
  class TreeConstructionTest
    getter data : String
    getter errors : Array(String)
    getter document : String
    getter document_fragment : String?
    getter scripting_enabled : Bool

    def initialize(@data : String, @errors : Array(String), @document : String,
                   @document_fragment : String? = nil, @scripting_enabled : Bool = true)
    end

    # Parse test cases from file content
    def self.parse_file(content : String) : Array(TreeConstructionTest)
      tests = [] of TreeConstructionTest
      lines = content.split('\n')
      i = 0

      while i < lines.size
        # Skip blank lines
        while i < lines.size && lines[i].strip.empty?
          i += 1
        end
        break if i >= lines.size

        # Each test starts with #data
        if lines[i] == "#data"
          test = parse_test(lines, i)
          if test
            tests << test[:test]
            i = test[:next_line]
          else
            i += 1
          end
        else
          i += 1
        end
      end

      tests
    end

    private def self.parse_test(lines : Array(String), start : Int32) : NamedTuple(test: TreeConstructionTest, next_line: Int32)?
      return nil unless lines[start] == "#data"

      i = start + 1
      data_lines = [] of String

      # Read data section
      while i < lines.size && !lines[i].starts_with?("#")
        data_lines << lines[i]
        i += 1
      end

      # Data may have trailing newline stripped
      data = data_lines.join('\n')
      data = data[0...-1] if data.ends_with?('\n') && data_lines.size > 0 && data_lines.last.empty?

      errors = [] of String
      document_lines = [] of String
      document_fragment : String? = nil
      scripting = true

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
            document_fragment = lines[i]
            i += 1
          end
        when "#script-off"
          scripting = false
          i += 1
        when "#script-on"
          scripting = true
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

      {test: TreeConstructionTest.new(data, errors, document, document_fragment, scripting), next_line: i}
    end
  end

  # Convert a parsed document to html5lib test format
  def self.serialize_to_test_format(node : JustHTML::Node, indent : Int32 = 0) : String
    result = String::Builder.new
    serialize_node(node, result, indent)
    result.to_s.strip
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

      # Attributes in alphabetical order
      attrs = node.attrs.to_a.sort_by { |k, _| k }
      attrs.each do |attr_name, attr_value|
        builder << prefix << "  " << attr_name
        if attr_value
          builder << "=\"" << attr_value << "\""
        else
          builder << "=\"\""
        end
        builder << "\n"
      end

      # Children
      node.children.each { |child| serialize_node(child, builder, indent + 1) }
    when JustHTML::Text
      builder << prefix << "\"" << node.data << "\"\n"
    when JustHTML::Comment
      builder << prefix << "<!-- " << node.data << " -->\n"
    end
  end

  # Run a single test case and return whether it passed
  def self.run_test(test : TreeConstructionTest) : Bool
    begin
      doc = JustHTML::TreeBuilder.parse(test.data)
      actual = serialize_to_test_format(doc)
      expected = test.document.strip

      actual == expected
    rescue ex
      false
    end
  end
end

describe "html5lib tree construction tests" do
  # Basic sanity tests to verify our test infrastructure works
  describe "test format parsing" do
    it "parses a simple test case" do
      content = <<-TEST
      #data
      <html>
      #errors
      #document
      | <html>
      |   <head>
      |   <body>
      TEST

      tests = HTML5LibTests::TreeConstructionTest.parse_file(content)
      tests.size.should eq(1)
      tests[0].data.should eq("<html>")
    end
  end

  describe "test serialization" do
    it "serializes a simple document" do
      doc = JustHTML::TreeBuilder.parse("<!DOCTYPE html><html><head></head><body></body></html>")
      output = HTML5LibTests.serialize_to_test_format(doc)
      output.should contain("<!DOCTYPE html>")
      output.should contain("<html>")
      output.should contain("<head>")
      output.should contain("<body>")
    end

    it "serializes text nodes" do
      doc = JustHTML::TreeBuilder.parse("<p>Hello</p>")
      output = HTML5LibTests.serialize_to_test_format(doc)
      output.should contain("\"Hello\"")
    end

    it "serializes comments" do
      doc = JustHTML::TreeBuilder.parse("<!--test-->")
      output = HTML5LibTests.serialize_to_test_format(doc)
      output.should contain("<!-- test -->")
    end
  end

  describe "basic parsing tests" do
    it "parses empty document" do
      doc = JustHTML.parse("")
      doc.should be_a(JustHTML::Document)
    end

    it "parses doctype" do
      doc = JustHTML.parse("<!DOCTYPE html>")
      doc.children.first.should be_a(JustHTML::DoctypeNode)
    end

    it "creates implicit html, head, body" do
      doc = JustHTML.parse("<p>text</p>")
      html = doc.query_selector("html")
      html.should_not be_nil

      head = doc.query_selector("head")
      head.should_not be_nil

      body = doc.query_selector("body")
      body.should_not be_nil
    end

    it "handles nested elements" do
      doc = JustHTML.parse("<div><p><span>text</span></p></div>")
      span = doc.query_selector("span")
      span.should_not be_nil
      span.not_nil!.children.first.as(JustHTML::Text).data.should eq("text")
    end

    it "handles void elements" do
      doc = JustHTML.parse("<p>before<br>after</p>")
      p = doc.query_selector("p")
      p.should_not be_nil
      p.not_nil!.children.size.should eq(3) # text, br, text
    end

    it "handles attributes" do
      doc = JustHTML.parse("<div id='main' class='container'>content</div>")
      div = doc.query_selector("div")
      div.should_not be_nil
      div.not_nil!.id.should eq("main")
      div.not_nil!.has_class?("container").should be_true
    end

    it "handles entities" do
      doc = JustHTML.parse("<p>&amp; &lt; &gt;</p>")
      p = doc.query_selector("p")
      p.should_not be_nil
      p.not_nil!.children.first.as(JustHTML::Text).data.should eq("& < >")
    end

    it "handles comments" do
      doc = JustHTML.parse("<!-- comment --><p>text</p>")
      # Comment should be in the document
      has_comment = doc.children.any? { |c| c.is_a?(JustHTML::Comment) }
      has_comment.should be_true
    end
  end
end
