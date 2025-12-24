require "./spec_helper"

describe JustHTML::Tag do
  it "creates a start tag" do
    tag = JustHTML::Tag.new(:start, "div")
    tag.kind.should eq(:start)
    tag.name.should eq("div")
    tag.attrs.should be_empty
    tag.self_closing?.should be_false
  end

  it "creates an end tag" do
    tag = JustHTML::Tag.new(:end, "p")
    tag.kind.should eq(:end)
    tag.name.should eq("p")
  end

  it "stores attributes" do
    tag = JustHTML::Tag.new(:start, "input", {"type" => "text", "value" => nil})
    tag.attrs["type"].should eq("text")
    tag.attrs["value"].should be_nil
  end

  it "marks self-closing tags" do
    tag = JustHTML::Tag.new(:start, "br", self_closing: true)
    tag.self_closing?.should be_true
  end
end

describe JustHTML::Doctype do
  it "stores doctype info" do
    doctype = JustHTML::Doctype.new(
      name: "html",
      public_id: "-//W3C//DTD HTML 4.01//EN",
      system_id: "http://www.w3.org/TR/html4/strict.dtd"
    )
    doctype.name.should eq("html")
    doctype.public_id.should eq("-//W3C//DTD HTML 4.01//EN")
    doctype.system_id.should eq("http://www.w3.org/TR/html4/strict.dtd")
    doctype.force_quirks?.should be_false
  end
end

describe JustHTML::CommentToken do
  it "stores comment data" do
    comment = JustHTML::CommentToken.new("This is a comment")
    comment.data.should eq("This is a comment")
  end
end
