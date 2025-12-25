require "../spec_helper"
require "./html5lib_test_data"

describe HTML5LibTestData do
  describe "TreeConstructionTest" do
    it "stores test data" do
      test = HTML5LibTestData::TreeConstructionTest.new(
        data: "<p>Hello",
        errors: ["error1"],
        document: "| <html>",
        document_fragment: "div",
        script_directive: "script-off",
        xml_coercion: false,
        iframe_srcdoc: false
      )

      test.data.should eq("<p>Hello")
      test.errors.should eq(["error1"])
      test.document.should eq("| <html>")
      test.document_fragment.should eq("div")
      test.script_directive.should eq("script-off")
      test.xml_coercion.should eq(false)
      test.iframe_srcdoc.should eq(false)
    end
  end

  describe ".parse_tree_construction_tests" do
    it "parses simple test case" do
      content = <<-DAT
      #data
      <p>Hello
      #errors
      #document
      | <html>
      |   <head>
      |   <body>
      |     <p>
      |       "Hello"
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].data.should eq("<p>Hello")
      tests[0].errors.should be_empty
      tests[0].document.should contain("| <html>")
    end

    it "parses multiple test cases" do
      content = <<-DAT
      #data
      <p>Test1
      #errors
      #document
      | <html>

      #data
      <p>Test2
      #errors
      #document
      | <html>
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(2)
      tests[0].data.should eq("<p>Test1")
      tests[1].data.should eq("<p>Test2")
    end

    it "parses fragment context" do
      content = <<-DAT
      #data
      <p>Fragment test
      #errors
      #document-fragment
      div
      #document
      | <p>
      |   "Fragment test"
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].document_fragment.should eq("div")
    end

    it "parses script directives" do
      content = <<-DAT
      #data
      <script>alert()</script>
      #errors
      #script-off
      #document
      | <html>
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].script_directive.should eq("script-off")
    end

    it "parses xml coercion flag" do
      content = <<-DAT
      #data
      <test>
      #errors
      #xml-coercion
      #document
      | <html>
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].xml_coercion.should eq(true)
    end

    it "parses iframe srcdoc flag" do
      content = <<-DAT
      #data
      <test>
      #errors
      #iframe-srcdoc
      #document
      | <html>
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].iframe_srcdoc.should eq(true)
    end

    it "skips #new-errors sections" do
      content = <<-DAT
      #data
      <p>Test
      #errors
      old error
      #new-errors
      new error
      #document
      | <html>
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].errors.should eq(["old error"])
    end
  end

  describe ".decode_escapes" do
    it "decodes \\xNN hex escapes" do
      input = "Hello\\x20World"
      HTML5LibTestData.decode_escapes(input).should eq("Hello World")
    end

    it "decodes \\uNNNN unicode escapes" do
      input = "Hello\\u0020World"
      HTML5LibTestData.decode_escapes(input).should eq("Hello World")
    end

    it "handles surrogate pairs by replacing with replacement character" do
      input = "Test\\uD800Surrogate"
      result = HTML5LibTestData.decode_escapes(input)
      result.should eq("Test\uFFFDSurrogate")
    end

    it "returns unmodified text when no escapes present" do
      input = "Plain text"
      HTML5LibTestData.decode_escapes(input).should eq("Plain text")
    end

    it "handles multiple escapes in one string" do
      input = "\\x48\\x65\\x6C\\x6C\\x6F"
      HTML5LibTestData.decode_escapes(input).should eq("Hello")
    end
  end

  describe ".serialize_to_test_format" do
    it "serializes simple document" do
      doc = JustHTML.parse("<p>Hello</p>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("| <html>")
      result.should contain("|   <head>")
      result.should contain("|   <body>")
      result.should contain("|     <p>")
      result.should contain("|       \"Hello\"")
    end

    it "serializes DOCTYPE" do
      doc = JustHTML.parse("<!DOCTYPE html><p>Test</p>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("| <!DOCTYPE html>")
      result.should contain("| <html>")
    end

    it "serializes DOCTYPE with public and system IDs" do
      doc = JustHTML.parse("<!DOCTYPE html PUBLIC \"public\" \"system\"><p>Test</p>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("| <!DOCTYPE html \"public\" \"system\">")
    end

    it "serializes element attributes in alphabetical order" do
      doc = JustHTML.parse("<div id=\"test\" class=\"foo\" aria-label=\"bar\"></div>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      lines = result.split("\n").select { |l| l.includes?("=") }
      lines[0].should contain("aria-label=")
      lines[1].should contain("class=")
      lines[2].should contain("id=")
    end

    it "serializes comments" do
      doc = JustHTML.parse("<!-- comment --><p>Test</p>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("| <!--  comment  -->")
    end

    it "serializes SVG elements with namespace prefix" do
      doc = JustHTML.parse("<svg><path d=\"M0,0\"></path></svg>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("|     <svg svg>")
      result.should contain("|       <path>")
    end

    it "serializes MathML elements with namespace prefix" do
      doc = JustHTML.parse("<math><mi>x</mi></math>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("|     <math math>")
      result.should contain("|       <mi>")
    end

    it "serializes template element with content" do
      doc = JustHTML.parse("<template><p>Content</p></template>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("|     <template>")
      result.should contain("|       content")
      result.should contain("|         <body>")
    end

    it "handles nested elements with proper indentation" do
      doc = JustHTML.parse("<div><span><b>Text</b></span></div>")
      result = HTML5LibTestData.serialize_to_test_format(doc)

      result.should contain("|     <div>")
      result.should contain("|       <span>")
      result.should contain("|         <b>")
      result.should contain("|           \"Text\"")
    end
  end

  describe "TokenCollector" do
    it "collects start tags" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      tag = JustHTML::Tag.new(:start, "div", {} of String => String?)
      sink.process_tag(tag)

      tokens.size.should eq(1)
      tokens[0].as_a[0].as_s.should eq("StartTag")
      tokens[0].as_a[1].as_s.should eq("div")
    end

    it "collects end tags" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      tag = JustHTML::Tag.new(:end, "div", {} of String => String?)
      sink.process_tag(tag)

      tokens.size.should eq(1)
      tokens[0].as_a[0].as_s.should eq("EndTag")
      tokens[0].as_a[1].as_s.should eq("div")
    end

    it "collects tag attributes" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      attrs = {"id" => "test", "class" => "foo"} of String => String?
      tag = JustHTML::Tag.new(:start, "div", attrs)
      sink.process_tag(tag)

      tokens.size.should eq(1)
      token_attrs = tokens[0].as_a[2].as_h
      token_attrs["id"].as_s.should eq("test")
      token_attrs["class"].as_s.should eq("foo")
    end

    it "collects self-closing flag" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      tag = JustHTML::Tag.new(:start, "br", {} of String => String?, true)
      sink.process_tag(tag)

      tokens.size.should eq(1)
      tokens[0].as_a[3].as_bool.should eq(true)
    end

    it "collects comments" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      comment = JustHTML::CommentToken.new("test comment")
      sink.process_comment(comment)

      tokens.size.should eq(1)
      tokens[0].as_a[0].as_s.should eq("Comment")
      tokens[0].as_a[1].as_s.should eq("test comment")
    end

    it "collects DOCTYPE tokens" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      doctype = JustHTML::Doctype.new(name: "html")
      sink.process_doctype(doctype)

      tokens.size.should eq(1)
      tokens[0].as_a[0].as_s.should eq("DOCTYPE")
      tokens[0].as_a[1].as_s.should eq("html")
    end

    it "collects character tokens" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      sink.process_characters("Hello")

      tokens.size.should eq(1)
      tokens[0].as_a[0].as_s.should eq("Character")
      tokens[0].as_a[1].as_s.should eq("Hello")
    end

    it "handles EOF without error" do
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)

      sink.process_eof

      tokens.size.should eq(0)
    end
  end
end
