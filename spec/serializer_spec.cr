require "./spec_helper"

describe JustHTML::Serializer do
  describe ".to_html" do
    it "serializes simple elements" do
      doc = JustHTML::TreeBuilder.parse("<p>Hello</p>")
      html = JustHTML::Serializer.to_html(doc)

      html.should contain("<p>Hello</p>")
    end

    it "serializes nested elements" do
      doc = JustHTML::TreeBuilder.parse("<div><span>text</span></div>")
      html = JustHTML::Serializer.to_html(doc)

      html.should contain("<div><span>text</span></div>")
    end

    it "serializes void elements without closing tag" do
      doc = JustHTML::TreeBuilder.parse("<p>Line 1<br>Line 2</p>")
      html = JustHTML::Serializer.to_html(doc)

      html.should contain("<br>")
      html.should_not contain("</br>")
    end

    it "serializes attributes" do
      doc = JustHTML::TreeBuilder.parse("<a href=\"http://example.com\" class=\"link\">click</a>")
      html = JustHTML::Serializer.to_html(doc)

      html.should contain("href=\"http://example.com\"")
      html.should contain("class=\"link\"")
    end

    it "escapes special characters in text" do
      el = JustHTML::Element.new("p")
      el.append_child(JustHTML::Text.new("<script>alert('xss')</script>"))
      html = JustHTML::Serializer.to_html(el)

      html.should contain("&lt;script&gt;")
      html.should_not contain("<script>")
    end

    it "escapes special characters in attributes" do
      el = JustHTML::Element.new("div", {"data-value" => "a<b&c\"d"})
      html = JustHTML::Serializer.to_html(el)

      html.should contain("data-value=\"a&lt;b&amp;c&quot;d\"")
    end

    it "serializes comments" do
      doc = JustHTML::TreeBuilder.parse("<!-- comment --><p>text</p>")
      html = JustHTML::Serializer.to_html(doc)

      html.should contain("<!-- comment -->")
    end

    it "serializes doctype" do
      doc = JustHTML::TreeBuilder.parse("<!DOCTYPE html><html><body></body></html>")
      html = JustHTML::Serializer.to_html(doc)

      html.should contain("<!DOCTYPE html>")
    end

    it "handles boolean attributes" do
      el = JustHTML::Element.new("input", {"disabled" => nil, "type" => "text"})
      html = JustHTML::Serializer.to_html(el)

      html.should contain("disabled")
      html.should contain("type=\"text\"")
    end
  end

  describe ".to_text" do
    it "extracts text from elements" do
      doc = JustHTML::TreeBuilder.parse("<p>Hello World</p>")
      text = JustHTML::Serializer.to_text(doc)

      text.should contain("Hello World")
    end

    it "extracts text from nested elements" do
      doc = JustHTML::TreeBuilder.parse("<div><p>First</p><p>Second</p></div>")
      text = JustHTML::Serializer.to_text(doc)

      text.should contain("First")
      text.should contain("Second")
    end

    it "adds newlines for block elements" do
      doc = JustHTML::TreeBuilder.parse("<p>Para 1</p><p>Para 2</p>")
      text = JustHTML::Serializer.to_text(doc)

      text.should contain("Para 1")
      text.should contain("Para 2")
      # Should have some separation
      text.should_not eq("Para 1Para 2")
    end

    it "handles br elements" do
      doc = JustHTML::TreeBuilder.parse("<p>Line 1<br>Line 2</p>")
      text = JustHTML::Serializer.to_text(doc)

      text.should contain("Line 1")
      text.should contain("Line 2")
    end

    it "skips script and style content" do
      doc = JustHTML::TreeBuilder.parse("<p>Visible</p><script>invisible</script><style>also invisible</style>")
      text = JustHTML::Serializer.to_text(doc)

      text.should contain("Visible")
      text.should_not contain("invisible")
    end
  end
end
