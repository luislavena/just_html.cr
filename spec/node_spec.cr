require "./spec_helper"

describe JustHTML::Element do
  it "has a name and namespace" do
    el = JustHTML::Element.new("div")
    el.name.should eq("div")
    el.namespace.should eq("html")
  end

  it "stores attributes" do
    el = JustHTML::Element.new("input", {"type" => "text", "disabled" => nil})
    el.attrs["type"].should eq("text")
    el.attrs["disabled"].should be_nil
    el["type"].should eq("text")
  end

  it "has children" do
    parent = JustHTML::Element.new("div")
    child = JustHTML::Element.new("p")
    parent.append_child(child)
    parent.children.size.should eq(1)
    child.parent.should eq(parent)
  end

  it "provides id helper" do
    el = JustHTML::Element.new("div", {"id" => "main"})
    el.id.should eq("main")
  end

  it "provides classes helper" do
    el = JustHTML::Element.new("div", {"class" => "foo bar baz"})
    el.classes.should eq(["foo", "bar", "baz"])
    el.has_class?("bar").should be_true
    el.has_class?("qux").should be_false
  end

  it "checks for attributes" do
    el = JustHTML::Element.new("input", {"type" => "text"})
    el.has_attribute?("type").should be_true
    el.has_attribute?("value").should be_false
  end

  describe "#text_content" do
    it "returns text from element" do
      el = JustHTML::Element.new("p")
      el.append_child(JustHTML::Text.new("Hello"))
      el.text_content.should eq("Hello")
    end

    it "returns text from nested elements" do
      div = JustHTML::Element.new("div")
      p = JustHTML::Element.new("p")
      p.append_child(JustHTML::Text.new("Hello "))
      span = JustHTML::Element.new("span")
      span.append_child(JustHTML::Text.new("World"))
      p.append_child(span)
      div.append_child(p)
      div.text_content.should eq("Hello World")
    end

    it "returns empty string for empty element" do
      el = JustHTML::Element.new("div")
      el.text_content.should eq("")
    end
  end

  describe "#inner_html" do
    it "returns HTML content of element" do
      div = JustHTML::Element.new("div")
      p = JustHTML::Element.new("p")
      p.append_child(JustHTML::Text.new("Hello"))
      div.append_child(p)
      div.inner_html.should eq("<p>Hello</p>")
    end

    it "returns empty string for empty element" do
      el = JustHTML::Element.new("div")
      el.inner_html.should eq("")
    end
  end

  describe "#outer_html" do
    it "returns element and its content as HTML" do
      div = JustHTML::Element.new("div", {"id" => "main"})
      p = JustHTML::Element.new("p")
      p.append_child(JustHTML::Text.new("Hello"))
      div.append_child(p)
      div.outer_html.should eq("<div id=\"main\"><p>Hello</p></div>")
    end
  end

  describe "#ancestors" do
    it "returns list of ancestor elements" do
      doc = JustHTML::TreeBuilder.parse("<div><section><p>text</p></section></div>")
      p = doc.query_selector("p").not_nil!
      ancestors = p.ancestors
      ancestors.map(&.name).should eq(["section", "div", "body", "html"])
    end

    it "returns empty array for root element" do
      el = JustHTML::Element.new("div")
      el.ancestors.should be_empty
    end
  end

  describe "#next_element_sibling" do
    it "returns next sibling element" do
      doc = JustHTML::TreeBuilder.parse("<div><p>First</p><span>Second</span></div>")
      p = doc.query_selector("p").not_nil!
      next_el = p.next_element_sibling
      next_el.should_not be_nil
      next_el.not_nil!.name.should eq("span")
    end

    it "returns nil for last element" do
      doc = JustHTML::TreeBuilder.parse("<div><p>Only</p></div>")
      p = doc.query_selector("p").not_nil!
      p.next_element_sibling.should be_nil
    end
  end

  describe "#previous_element_sibling" do
    it "returns previous sibling element" do
      doc = JustHTML::TreeBuilder.parse("<div><p>First</p><span>Second</span></div>")
      span = doc.query_selector("span").not_nil!
      prev_el = span.previous_element_sibling
      prev_el.should_not be_nil
      prev_el.not_nil!.name.should eq("p")
    end

    it "returns nil for first element" do
      doc = JustHTML::TreeBuilder.parse("<div><p>Only</p></div>")
      p = doc.query_selector("p").not_nil!
      p.previous_element_sibling.should be_nil
    end
  end
end

describe JustHTML::Text do
  it "stores text data" do
    text = JustHTML::Text.new("Hello, world!")
    text.data.should eq("Hello, world!")
    text.name.should eq("#text")
  end
end

describe JustHTML::Comment do
  it "stores comment data" do
    comment = JustHTML::Comment.new("This is a comment")
    comment.data.should eq("This is a comment")
    comment.name.should eq("#comment")
  end
end
