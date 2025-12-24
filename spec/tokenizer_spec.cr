require "./spec_helper"

private alias Token = JustHTML::Tag | JustHTML::CommentToken | JustHTML::Doctype | String

private def tokenize(html : String) : Array(Token)
  tokens = [] of Token
  sink = TestTokenSink.new(tokens)
  tokenizer = JustHTML::Tokenizer.new(sink)
  tokenizer.run(html)
  tokens
end

private class TestTokenSink
  include JustHTML::TokenSink

  def initialize(@tokens : Array(Token))
  end

  def process_tag(tag : JustHTML::Tag) : Nil
    @tokens << JustHTML::Tag.new(tag.kind, tag.name, tag.attrs.dup, tag.self_closing?)
  end

  def process_comment(comment : JustHTML::CommentToken) : Nil
    @tokens << JustHTML::CommentToken.new(comment.data)
  end

  def process_doctype(doctype : JustHTML::Doctype) : Nil
    @tokens << JustHTML::Doctype.new(doctype.name, doctype.public_id, doctype.system_id, doctype.force_quirks?)
  end

  def process_characters(data : String) : Nil
    @tokens << data
  end

  def process_eof : Nil
  end
end

describe JustHTML::Tokenizer do
  it "tokenizes simple text" do
    tokens = tokenize("Hello")
    tokens.size.should eq(1)
    tokens[0].should be_a(String)
    tokens[0].as(String).should eq("Hello")
  end

  it "tokenizes a simple tag" do
    tokens = tokenize("<div>")
    tokens.size.should eq(1)
    tag = tokens[0].as(JustHTML::Tag)
    tag.kind.should eq(:start)
    tag.name.should eq("div")
  end

  it "tokenizes end tag" do
    tokens = tokenize("</div>")
    tokens.size.should eq(1)
    tag = tokens[0].as(JustHTML::Tag)
    tag.kind.should eq(:end)
    tag.name.should eq("div")
  end

  it "tokenizes tag with attributes" do
    tokens = tokenize("<div id='main' class=\"container\">")
    tokens.size.should eq(1)
    tag = tokens[0].as(JustHTML::Tag)
    tag.attrs["id"].should eq("main")
    tag.attrs["class"].should eq("container")
  end

  it "tokenizes self-closing tag" do
    tokens = tokenize("<br/>")
    tag = tokens[0].as(JustHTML::Tag)
    tag.name.should eq("br")
    tag.self_closing?.should be_true
  end

  it "tokenizes comment" do
    tokens = tokenize("<!-- comment -->")
    tokens.size.should eq(1)
    tokens[0].should be_a(JustHTML::CommentToken)
    tokens[0].as(JustHTML::CommentToken).data.should eq(" comment ")
  end

  it "tokenizes doctype" do
    tokens = tokenize("<!DOCTYPE html>")
    tokens.size.should eq(1)
    tokens[0].should be_a(JustHTML::Doctype)
    tokens[0].as(JustHTML::Doctype).name.should eq("html")
  end

  it "tokenizes mixed content" do
    tokens = tokenize("<p>Hello <b>world</b>!</p>")
    tokens.size.should eq(7)
    tokens[0].as(JustHTML::Tag).name.should eq("p")
    tokens[1].as(String).should eq("Hello ")
    tokens[2].as(JustHTML::Tag).name.should eq("b")
    tokens[3].as(String).should eq("world")
    tokens[4].as(JustHTML::Tag).name.should eq("b")
    tokens[4].as(JustHTML::Tag).kind.should eq(:end)
    tokens[5].as(String).should eq("!")
    tokens[6].as(JustHTML::Tag).name.should eq("p")
    tokens[6].as(JustHTML::Tag).kind.should eq(:end)
  end

  it "tokenizes unquoted attribute values" do
    tokens = tokenize("<input type=text>")
    tag = tokens[0].as(JustHTML::Tag)
    tag.attrs["type"].should eq("text")
  end

  it "tokenizes boolean attributes" do
    tokens = tokenize("<input disabled>")
    tag = tokens[0].as(JustHTML::Tag)
    tag.has_attribute?("disabled").should be_true
  end

  it "decodes entities in text" do
    tokens = tokenize("&lt;div&gt;")
    tokens[0].as(String).should eq("<div>")
  end

  it "decodes entities in attributes" do
    tokens = tokenize("<a href=\"?a=1&amp;b=2\">")
    tag = tokens[0].as(JustHTML::Tag)
    tag.attrs["href"].should eq("?a=1&b=2")
  end
end
