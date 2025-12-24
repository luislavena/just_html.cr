require "./spec_helper"

describe JustHTML do
  it "has a version" do
    JustHTML::VERSION.should_not be_nil
  end

  describe ".parse" do
    it "parses a simple HTML document" do
      doc = JustHTML.parse("<html><body><p>Hello</p></body></html>")
      doc.should be_a(JustHTML::Document)
    end

    it "parses HTML fragment implicitly wrapping in document" do
      doc = JustHTML.parse("<p>Hello</p>")
      doc.children.first.should be_a(JustHTML::Element)
      doc.children.first.as(JustHTML::Element).name.should eq("html")
    end

    it "provides access to parse errors when requested" do
      doc = JustHTML.parse("<p><div></p></div>", collect_errors: true)
      doc.should be_a(JustHTML::Document)
    end
  end

  describe ".parse_fragment" do
    it "parses an HTML fragment" do
      fragment = JustHTML.parse_fragment("<p>Hello</p><p>World</p>")
      fragment.should be_a(JustHTML::DocumentFragment)
      # Should have 2 p elements
      p_elements = fragment.query_selector_all("p")
      p_elements.size.should eq(2)
    end

    it "parses with a context element" do
      fragment = JustHTML.parse_fragment("<li>Item</li>", context: "ul")
      fragment.should be_a(JustHTML::DocumentFragment)
      li_element = fragment.query_selector("li")
      li_element.should_not be_nil
    end

    it "handles text-only fragments" do
      fragment = JustHTML.parse_fragment("Hello World")
      # May have one text child or be wrapped
      fragment.to_text.strip.should eq("Hello World")
    end
  end

  describe "Document#to_html" do
    it "serializes document back to HTML" do
      html = "<html><head></head><body><p>Hello</p></body></html>"
      doc = JustHTML.parse(html)
      output = doc.to_html
      output.should contain("<p>Hello</p>")
      output.should contain("<html>")
    end
  end

  describe "Document#to_text" do
    it "extracts text content" do
      doc = JustHTML.parse("<html><body><p>Hello</p><p>World</p></body></html>")
      text = doc.to_text
      text.should contain("Hello")
      text.should contain("World")
    end
  end

  describe "Element querying" do
    it "supports query_selector on document" do
      doc = JustHTML.parse("<html><body><div id='main'><p>Text</p></div></body></html>")
      result = doc.query_selector("#main")
      result.should_not be_nil
      result.not_nil!.id.should eq("main")
    end

    it "supports query_selector_all on document" do
      doc = JustHTML.parse("<html><body><p>One</p><p>Two</p></body></html>")
      results = doc.query_selector_all("p")
      results.size.should eq(2)
    end
  end

  describe "Fragment querying" do
    it "supports query_selector on fragment" do
      fragment = JustHTML.parse_fragment("<div><p class='first'>A</p><p>B</p></div>")
      result = fragment.query_selector(".first")
      result.should_not be_nil
    end

    it "supports query_selector_all on fragment" do
      fragment = JustHTML.parse_fragment("<p>One</p><p>Two</p><p>Three</p>")
      results = fragment.query_selector_all("p")
      results.size.should eq(3)
    end
  end
end
