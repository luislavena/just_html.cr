require "./spec_helper"
require "./support/html5lib_test_data"

# Basic sanity tests for html5lib test infrastructure
# The actual html5lib conformance tests are in spec/html5lib/
describe "html5lib test infrastructure" do
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

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].data.should eq("<html>")
    end
  end

  describe "test serialization" do
    it "serializes a simple document" do
      doc = JustHTML::TreeBuilder.parse("<!DOCTYPE html><html><head></head><body></body></html>")
      output = HTML5LibTestData.serialize_to_test_format(doc)
      output.should contain("<!DOCTYPE html>")
      output.should contain("<html>")
      output.should contain("<head>")
      output.should contain("<body>")
    end

    it "serializes text nodes" do
      doc = JustHTML::TreeBuilder.parse("<p>Hello</p>")
      output = HTML5LibTestData.serialize_to_test_format(doc)
      output.should contain("\"Hello\"")
    end

    it "serializes comments" do
      doc = JustHTML::TreeBuilder.parse("<!--test-->")
      output = HTML5LibTestData.serialize_to_test_format(doc)
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
