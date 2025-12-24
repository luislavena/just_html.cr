require "./spec_helper"

describe JasperHTML::Selector do
  describe ".parse" do
    it "parses type selector" do
      selector = JasperHTML::Selector.parse("div")
      selector.should_not be_nil
    end

    it "parses class selector" do
      selector = JasperHTML::Selector.parse(".container")
      selector.should_not be_nil
    end

    it "parses id selector" do
      selector = JasperHTML::Selector.parse("#main")
      selector.should_not be_nil
    end

    it "parses attribute selector" do
      selector = JasperHTML::Selector.parse("[type]")
      selector.should_not be_nil
    end

    it "parses attribute value selector" do
      selector = JasperHTML::Selector.parse("[type=text]")
      selector.should_not be_nil
    end

    it "parses compound selector" do
      selector = JasperHTML::Selector.parse("div.container#main")
      selector.should_not be_nil
    end

    it "parses descendant combinator" do
      selector = JasperHTML::Selector.parse("div p")
      selector.should_not be_nil
    end

    it "parses child combinator" do
      selector = JasperHTML::Selector.parse("div > p")
      selector.should_not be_nil
    end

    it "parses selector list" do
      selector = JasperHTML::Selector.parse("div, p, span")
      selector.should_not be_nil
    end
  end

  describe "#matches?" do
    it "matches type selector" do
      doc = JasperHTML::TreeBuilder.parse("<div></div>")
      div = doc.children.find { |n| n.is_a?(JasperHTML::Element) && n.name == "html" }
        .try(&.children.find { |n| n.is_a?(JasperHTML::Element) && n.name == "body" })
        .try(&.children.first)
      div.should_not be_nil
      div = div.as(JasperHTML::Element)

      selector = JasperHTML::Selector.parse("div")
      selector.not_nil!.matches?(div).should be_true

      selector = JasperHTML::Selector.parse("span")
      selector.not_nil!.matches?(div).should be_false
    end

    it "matches class selector" do
      doc = JasperHTML::TreeBuilder.parse("<div class='foo bar'></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse(".foo").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse(".bar").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse(".baz").not_nil!.matches?(div).should be_false
    end

    it "matches id selector" do
      doc = JasperHTML::TreeBuilder.parse("<div id='main'></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("#main").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse("#other").not_nil!.matches?(div).should be_false
    end

    it "matches attribute presence" do
      doc = JasperHTML::TreeBuilder.parse("<input type='text'>")
      input = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("[type]").not_nil!.matches?(input).should be_true
      JasperHTML::Selector.parse("[value]").not_nil!.matches?(input).should be_false
    end

    it "matches attribute value equals" do
      doc = JasperHTML::TreeBuilder.parse("<input type='text'>")
      input = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("[type=text]").not_nil!.matches?(input).should be_true
      JasperHTML::Selector.parse("[type='text']").not_nil!.matches?(input).should be_true
      JasperHTML::Selector.parse("[type=password]").not_nil!.matches?(input).should be_false
    end

    it "matches attribute value starts with" do
      doc = JasperHTML::TreeBuilder.parse("<a href='https://example.com'></a>")
      a = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("[href^=https]").not_nil!.matches?(a).should be_true
      JasperHTML::Selector.parse("[href^=http]").not_nil!.matches?(a).should be_true
      JasperHTML::Selector.parse("[href^=ftp]").not_nil!.matches?(a).should be_false
    end

    it "matches attribute value ends with" do
      doc = JasperHTML::TreeBuilder.parse("<a href='file.pdf'></a>")
      a = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("[href$=pdf]").not_nil!.matches?(a).should be_true
      JasperHTML::Selector.parse("[href$=.pdf]").not_nil!.matches?(a).should be_true
      JasperHTML::Selector.parse("[href$=doc]").not_nil!.matches?(a).should be_false
    end

    it "matches attribute value contains" do
      doc = JasperHTML::TreeBuilder.parse("<div data-info='hello world'></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("[data-info*=world]").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse("[data-info*=hello]").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse("[data-info*=foo]").not_nil!.matches?(div).should be_false
    end

    it "matches compound selector" do
      doc = JasperHTML::TreeBuilder.parse("<div class='container' id='main'></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("div.container").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse("div#main").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse("div.container#main").not_nil!.matches?(div).should be_true
      JasperHTML::Selector.parse("span.container").not_nil!.matches?(div).should be_false
    end

    it "matches universal selector" do
      doc = JasperHTML::TreeBuilder.parse("<div></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      JasperHTML::Selector.parse("*").not_nil!.matches?(div).should be_true
    end
  end

  describe "Element#query_selector" do
    it "finds first matching element" do
      doc = JasperHTML::TreeBuilder.parse("<div><p class='first'>One</p><p class='second'>Two</p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      result = div.query_selector("p")
      result.should_not be_nil
      result.not_nil!.has_class?("first").should be_true
    end

    it "returns nil when no match" do
      doc = JasperHTML::TreeBuilder.parse("<div><p>text</p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      result = div.query_selector("span")
      result.should be_nil
    end

    it "finds with descendant combinator" do
      doc = JasperHTML::TreeBuilder.parse("<div><section><p>text</p></section></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      result = div.query_selector("div p")
      result.should_not be_nil
      result.not_nil!.name.should eq("p")
    end

    it "finds with child combinator" do
      doc = JasperHTML::TreeBuilder.parse("<div><p>direct</p><section><p>nested</p></section></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      result = div.query_selector("div > p")
      result.should_not be_nil
      result.not_nil!.children.first.as(JasperHTML::Text).data.should eq("direct")
    end
  end

  describe "Element#query_selector_all" do
    it "finds all matching elements" do
      doc = JasperHTML::TreeBuilder.parse("<div><p>One</p><p>Two</p><p>Three</p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      results = div.query_selector_all("p")
      results.size.should eq(3)
    end

    it "returns empty array when no match" do
      doc = JasperHTML::TreeBuilder.parse("<div><p>text</p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      results = div.query_selector_all("span")
      results.should be_empty
    end

    it "finds with class selector" do
      doc = JasperHTML::TreeBuilder.parse("<div><p class='item'>A</p><span>B</span><p class='item'>C</p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      results = div.query_selector_all(".item")
      results.size.should eq(2)
    end
  end

  describe "pseudo-class selectors" do
    it "matches :first-child" do
      doc = JasperHTML::TreeBuilder.parse("<ul><li>First</li><li>Second</li><li>Third</li></ul>")
      ul = find_body(doc).children.first.as(JasperHTML::Element)

      result = ul.query_selector("li:first-child")
      result.should_not be_nil
      result.not_nil!.children.first.as(JasperHTML::Text).data.should eq("First")
    end

    it "matches :last-child" do
      doc = JasperHTML::TreeBuilder.parse("<ul><li>First</li><li>Second</li><li>Third</li></ul>")
      ul = find_body(doc).children.first.as(JasperHTML::Element)

      result = ul.query_selector("li:last-child")
      result.should_not be_nil
      result.not_nil!.children.first.as(JasperHTML::Text).data.should eq("Third")
    end

    it "matches :nth-child(n)" do
      doc = JasperHTML::TreeBuilder.parse("<ul><li>First</li><li>Second</li><li>Third</li></ul>")
      ul = find_body(doc).children.first.as(JasperHTML::Element)

      result = ul.query_selector("li:nth-child(2)")
      result.should_not be_nil
      result.not_nil!.children.first.as(JasperHTML::Text).data.should eq("Second")
    end

    it "matches :nth-child(odd)" do
      doc = JasperHTML::TreeBuilder.parse("<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>")
      ul = find_body(doc).children.first.as(JasperHTML::Element)

      results = ul.query_selector_all("li:nth-child(odd)")
      results.size.should eq(2)
    end

    it "matches :nth-child(even)" do
      doc = JasperHTML::TreeBuilder.parse("<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>")
      ul = find_body(doc).children.first.as(JasperHTML::Element)

      results = ul.query_selector_all("li:nth-child(even)")
      results.size.should eq(2)
    end

    it "matches :only-child" do
      doc = JasperHTML::TreeBuilder.parse("<div><p>Only</p></div><div><p>First</p><p>Second</p></div>")
      body = find_body(doc)

      results = body.query_selector_all("p:only-child")
      results.size.should eq(1)
      results.first.children.first.as(JasperHTML::Text).data.should eq("Only")
    end

    it "matches :empty" do
      doc = JasperHTML::TreeBuilder.parse("<div><p></p><p>Not empty</p><p></p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      results = div.query_selector_all("p:empty")
      results.size.should eq(2)
    end

    it "matches :not(selector)" do
      doc = JasperHTML::TreeBuilder.parse("<div><p class='skip'>A</p><p>B</p><p class='skip'>C</p></div>")
      div = find_body(doc).children.first.as(JasperHTML::Element)

      results = div.query_selector_all("p:not(.skip)")
      results.size.should eq(1)
      results.first.children.first.as(JasperHTML::Text).data.should eq("B")
    end
  end
end

private def find_body(doc : JasperHTML::Document) : JasperHTML::Element
  html = doc.children.find { |n| n.is_a?(JasperHTML::Element) && n.name == "html" }.as(JasperHTML::Element)
  html.children.find { |n| n.is_a?(JasperHTML::Element) && n.name == "body" }.as(JasperHTML::Element)
end
