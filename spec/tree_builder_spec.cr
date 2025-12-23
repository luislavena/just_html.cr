require "./spec_helper"

describe JasperHTML::TreeBuilder do
  describe "#parse" do
    it "parses simple HTML" do
      html = "<html><head></head><body><p>Hello</p></body></html>"
      doc = JasperHTML::TreeBuilder.parse(html)

      doc.should be_a(JasperHTML::Document)
      doc.children.size.should be > 0
    end

    it "parses HTML with doctype" do
      html = "<!DOCTYPE html><html><body>Hello</body></html>"
      doc = JasperHTML::TreeBuilder.parse(html)

      doc.children.first.should be_a(JasperHTML::DoctypeNode)
    end

    it "creates implicit html/head/body elements" do
      html = "<p>Hello</p>"
      doc = JasperHTML::TreeBuilder.parse(html)

      # Find the html element
      html_el = doc.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "html" }
      html_el.should_not be_nil
    end

    it "parses text content" do
      html = "<p>Hello World</p>"
      doc = JasperHTML::TreeBuilder.parse(html)

      # Navigate to find the text
      html_el = doc.children.find(&.is_a?(JasperHTML::Element)).as(JasperHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "body" }
      body_el.should_not be_nil

      p_el = body_el.as(JasperHTML::Element).children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "p" }
      p_el.should_not be_nil

      text = p_el.as(JasperHTML::Element).children.first
      text.should be_a(JasperHTML::Text)
      text.as(JasperHTML::Text).data.should eq("Hello World")
    end

    it "parses nested elements" do
      html = "<div><span>text</span></div>"
      doc = JasperHTML::TreeBuilder.parse(html)

      html_el = doc.children.find(&.is_a?(JasperHTML::Element)).as(JasperHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "body" }.as(JasperHTML::Element)
      div_el = body_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "div" }.as(JasperHTML::Element)

      div_el.should_not be_nil
      span_el = div_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "span" }
      span_el.should_not be_nil
    end

    it "parses void elements correctly" do
      html = "<p>Line 1<br>Line 2</p>"
      doc = JasperHTML::TreeBuilder.parse(html)

      html_el = doc.children.find(&.is_a?(JasperHTML::Element)).as(JasperHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "body" }.as(JasperHTML::Element)
      p_el = body_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "p" }.as(JasperHTML::Element)

      # Should have: Text("Line 1"), br, Text("Line 2")
      p_el.children.size.should eq(3)
      p_el.children[1].as(JasperHTML::Element).name.should eq("br")
    end

    it "parses comments" do
      html = "<!-- comment --><p>text</p>"
      doc = JasperHTML::TreeBuilder.parse(html)

      # Comment should be a child of document or html
      has_comment = doc.children.any?(&.is_a?(JasperHTML::Comment))
      has_comment.should be_true
    end

    it "parses attributes" do
      html = "<a href=\"http://example.com\" class=\"link\">click</a>"
      doc = JasperHTML::TreeBuilder.parse(html)

      html_el = doc.children.find(&.is_a?(JasperHTML::Element)).as(JasperHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "body" }.as(JasperHTML::Element)
      a_el = body_el.children.find { |c| c.is_a?(JasperHTML::Element) && c.as(JasperHTML::Element).name == "a" }.as(JasperHTML::Element)

      a_el["href"].should eq("http://example.com")
      a_el["class"].should eq("link")
    end
  end
end
