require "./spec_helper"

describe JustHTML::TreeBuilder do
  describe "#parse" do
    it "parses simple HTML" do
      html = "<html><head></head><body><p>Hello</p></body></html>"
      doc = JustHTML::TreeBuilder.parse(html)

      doc.should be_a(JustHTML::Document)
      doc.children.size.should be > 0
    end

    it "parses HTML with doctype" do
      html = "<!DOCTYPE html><html><body>Hello</body></html>"
      doc = JustHTML::TreeBuilder.parse(html)

      doc.children.first.should be_a(JustHTML::DoctypeNode)
    end

    it "ignores duplicate DOCTYPE tokens" do
      # HTML5 spec: DOCTYPE after initial mode should be ignored
      html = "<!DOCTYPE html><!DOCTYPE html>"
      doc = JustHTML::TreeBuilder.parse(html)

      # Should only have one DOCTYPE node
      doctype_count = doc.children.count(&.is_a?(JustHTML::DoctypeNode))
      doctype_count.should eq(1)
    end

    it "ignores DOCTYPE after html element" do
      html = "<html><!DOCTYPE html>"
      doc = JustHTML::TreeBuilder.parse(html)

      # No DOCTYPE nodes should exist (none was valid before html)
      doctype_count = doc.children.count(&.is_a?(JustHTML::DoctypeNode))
      doctype_count.should eq(0)
    end

    it "creates implicit html/head/body elements" do
      html = "<p>Hello</p>"
      doc = JustHTML::TreeBuilder.parse(html)

      # Find the html element
      html_el = doc.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "html" }
      html_el.should_not be_nil
    end

    it "parses text content" do
      html = "<p>Hello World</p>"
      doc = JustHTML::TreeBuilder.parse(html)

      # Navigate to find the text
      html_el = doc.children.find(&.is_a?(JustHTML::Element)).as(JustHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "body" }
      body_el.should_not be_nil

      p_el = body_el.as(JustHTML::Element).children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "p" }
      p_el.should_not be_nil

      text = p_el.as(JustHTML::Element).children.first
      text.should be_a(JustHTML::Text)
      text.as(JustHTML::Text).data.should eq("Hello World")
    end

    it "parses nested elements" do
      html = "<div><span>text</span></div>"
      doc = JustHTML::TreeBuilder.parse(html)

      html_el = doc.children.find(&.is_a?(JustHTML::Element)).as(JustHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "body" }.as(JustHTML::Element)
      div_el = body_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "div" }.as(JustHTML::Element)

      div_el.should_not be_nil
      span_el = div_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "span" }
      span_el.should_not be_nil
    end

    it "parses void elements correctly" do
      html = "<p>Line 1<br>Line 2</p>"
      doc = JustHTML::TreeBuilder.parse(html)

      html_el = doc.children.find(&.is_a?(JustHTML::Element)).as(JustHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "body" }.as(JustHTML::Element)
      p_el = body_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "p" }.as(JustHTML::Element)

      # Should have: Text("Line 1"), br, Text("Line 2")
      p_el.children.size.should eq(3)
      p_el.children[1].as(JustHTML::Element).name.should eq("br")
    end

    it "parses comments" do
      html = "<!-- comment --><p>text</p>"
      doc = JustHTML::TreeBuilder.parse(html)

      # Comment should be a child of document or html
      has_comment = doc.children.any?(&.is_a?(JustHTML::Comment))
      has_comment.should be_true
    end

    it "parses attributes" do
      html = "<a href=\"http://example.com\" class=\"link\">click</a>"
      doc = JustHTML::TreeBuilder.parse(html)

      html_el = doc.children.find(&.is_a?(JustHTML::Element)).as(JustHTML::Element)
      body_el = html_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "body" }.as(JustHTML::Element)
      a_el = body_el.children.find { |c| c.is_a?(JustHTML::Element) && c.as(JustHTML::Element).name == "a" }.as(JustHTML::Element)

      a_el["href"].should eq("http://example.com")
      a_el["class"].should eq("link")
    end
  end

  describe "implicit tag closing" do
    it "closes p when another p starts" do
      doc = JustHTML.parse("<p>First<p>Second")
      body = doc.query_selector("body").not_nil!
      # Should have two separate p elements, not nested
      ps = body.query_selector_all("p")
      ps.size.should eq(2)
      ps[0].text_content.should eq("First")
      ps[1].text_content.should eq("Second")
    end

    it "closes li when another li starts" do
      doc = JustHTML.parse("<ul><li>One<li>Two<li>Three</ul>")
      ul = doc.query_selector("ul").not_nil!
      lis = ul.query_selector_all("li")
      lis.size.should eq(3)
    end

    it "closes dd when dt starts" do
      doc = JustHTML.parse("<dl><dt>Term<dd>Definition<dt>Term2</dl>")
      dl = doc.query_selector("dl").not_nil!
      dts = dl.query_selector_all("dt")
      dds = dl.query_selector_all("dd")
      dts.size.should eq(2)
      dds.size.should eq(1)
    end

    it "closes heading when another heading starts" do
      doc = JustHTML.parse("<h1>Title<h2>Subtitle")
      body = doc.query_selector("body").not_nil!
      h1s = body.query_selector_all("h1")
      h2s = body.query_selector_all("h2")
      h1s.size.should eq(1)
      h2s.size.should eq(1)
      # They should be siblings, not nested
      h1s[0].text_content.should eq("Title")
      h2s[0].text_content.should eq("Subtitle")
    end
  end

  describe "void elements" do
    it "handles input without closing tag" do
      doc = JustHTML.parse("<form><input type='text'><input type='submit'></form>")
      form = doc.query_selector("form").not_nil!
      inputs = form.query_selector_all("input")
      inputs.size.should eq(2)
    end

    it "handles self-closing img" do
      doc = JustHTML.parse("<p><img src='a.png'/><img src='b.png'/></p>")
      p = doc.query_selector("p").not_nil!
      imgs = p.query_selector_all("img")
      imgs.size.should eq(2)
    end

    it "handles meta in head" do
      doc = JustHTML.parse("<html><head><meta charset='utf-8'><title>Test</title></head></html>")
      head = doc.query_selector("head").not_nil!
      meta = head.query_selector("meta")
      meta.should_not be_nil
      meta.not_nil!["charset"].should eq("utf-8")
    end
  end

  describe "raw text elements" do
    it "preserves script content" do
      doc = JustHTML.parse("<script>if (a < b) { x = 1; }</script>")
      script = doc.query_selector("script").not_nil!
      script.text_content.should eq("if (a < b) { x = 1; }")
    end

    it "handles script with HTML comment escape" do
      # HTML5 spec: script content with <!-- should enter escaped mode
      # and the first </script> inside should be ignored
      doc = JustHTML.parse("<script type=\"data\"><!--<script></script></script>")
      script = doc.query_selector("script").not_nil!
      script.text_content.should eq("<!--<script></script>")
    end

    it "preserves style content" do
      doc = JustHTML.parse("<style>p { color: red; }</style>")
      style = doc.query_selector("style").not_nil!
      style.text_content.should eq("p { color: red; }")
    end

    it "handles textarea content" do
      doc = JustHTML.parse("<textarea><p>Not HTML</p></textarea>")
      textarea = doc.query_selector("textarea").not_nil!
      textarea.text_content.should eq("<p>Not HTML</p>")
    end
  end

  describe "misnested tags" do
    it "handles unclosed tags" do
      doc = JustHTML.parse("<div><p>unclosed")
      div = doc.query_selector("div").not_nil!
      p = div.query_selector("p").not_nil!
      p.text_content.should eq("unclosed")
    end

    it "handles wrongly nested bold and italic" do
      doc = JustHTML.parse("<b>bold<i>both</b>italic</i>")
      body = doc.query_selector("body").not_nil!
      # The structure depends on adoption agency algorithm
      # At minimum, text should be preserved
      body.text_content.should contain("bold")
      body.text_content.should contain("both")
      body.text_content.should contain("italic")
    end

    it "handles extra end tags gracefully" do
      doc = JustHTML.parse("<div>content</div></div></div>")
      divs = doc.query_selector_all("div")
      divs.size.should eq(1)
    end
  end

  describe "form handling" do
    it "associates form with nested elements" do
      doc = JustHTML.parse("<form><input name='a'><button>Submit</button></form>")
      form = doc.query_selector("form").not_nil!
      input = form.query_selector("input")
      button = form.query_selector("button")
      input.should_not be_nil
      button.should_not be_nil
    end

    it "ignores nested form tags" do
      doc = JustHTML.parse("<form id='outer'><form id='inner'><input></form></form>")
      forms = doc.query_selector_all("form")
      # Only one form should exist
      forms.size.should eq(1)
      forms[0].id.should eq("outer")
    end
  end

  describe "special elements" do
    it "handles pre with leading newline" do
      doc = JustHTML.parse("<pre>\nFirst line\nSecond line</pre>")
      pre = doc.query_selector("pre").not_nil!
      # Leading newline after pre tag should be stripped
      pre.text_content.should eq("First line\nSecond line")
    end

    it "handles listing with leading newline" do
      doc = JustHTML.parse("<listing>\nCode here</listing>")
      listing = doc.query_selector("listing").not_nil!
      listing.text_content.should eq("Code here")
    end

    it "treats image as img" do
      doc = JustHTML.parse("<image src='test.png'>")
      img = doc.query_selector("img")
      img.should_not be_nil
      img.not_nil!["src"].should eq("test.png")
    end
  end

  describe "foreign content handling" do
    it "keeps font without special attrs in SVG namespace" do
      doc = JustHTML.parse("<svg><font></font></svg>")
      svg = doc.query_selector("svg").not_nil!
      font = svg.children.find { |c| c.is_a?(JustHTML::Element) }.as(JustHTML::Element)
      font.name.should eq("font")
      font.namespace.should eq("svg")
    end

    it "breaks font with size attr out of SVG" do
      doc = JustHTML.parse("<svg><font size=4></font></svg>")
      body = doc.query_selector("body").not_nil!
      svg = doc.query_selector("svg").not_nil!
      # Font should be sibling of svg, not child
      svg.children.select(&.is_a?(JustHTML::Element)).size.should eq(0)
      font = body.query_selector("font")
      font.should_not be_nil
      font.not_nil!["size"].should eq("4")
    end

    it "breaks font with color attr out of SVG" do
      doc = JustHTML.parse("<svg><font color=red></font></svg>")
      body = doc.query_selector("body").not_nil!
      svg = doc.query_selector("svg").not_nil!
      svg.children.select(&.is_a?(JustHTML::Element)).size.should eq(0)
      font = body.query_selector("font")
      font.should_not be_nil
    end
  end

  describe "entity handling" do
    it "decodes named entities" do
      doc = JustHTML.parse("<p>&amp;&lt;&gt;&quot;</p>")
      p = doc.query_selector("p").not_nil!
      p.text_content.should eq("&<>\"")
    end

    it "decodes numeric entities" do
      doc = JustHTML.parse("<p>&#65;&#66;&#67;</p>")
      p = doc.query_selector("p").not_nil!
      p.text_content.should eq("ABC")
    end

    it "decodes hex entities" do
      doc = JustHTML.parse("<p>&#x41;&#x42;&#x43;</p>")
      p = doc.query_selector("p").not_nil!
      p.text_content.should eq("ABC")
    end
  end
end
