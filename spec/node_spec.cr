require "./spec_helper"

describe JasperHTML::Element do
  it "has a name and namespace" do
    el = JasperHTML::Element.new("div")
    el.name.should eq("div")
    el.namespace.should eq("html")
  end

  it "stores attributes" do
    el = JasperHTML::Element.new("input", {"type" => "text", "disabled" => nil})
    el.attrs["type"].should eq("text")
    el.attrs["disabled"].should be_nil
    el["type"].should eq("text")
  end

  it "has children" do
    parent = JasperHTML::Element.new("div")
    child = JasperHTML::Element.new("p")
    parent.append_child(child)
    parent.children.size.should eq(1)
    child.parent.should eq(parent)
  end

  it "provides id helper" do
    el = JasperHTML::Element.new("div", {"id" => "main"})
    el.id.should eq("main")
  end

  it "provides classes helper" do
    el = JasperHTML::Element.new("div", {"class" => "foo bar baz"})
    el.classes.should eq(["foo", "bar", "baz"])
    el.has_class?("bar").should be_true
    el.has_class?("qux").should be_false
  end

  it "checks for attributes" do
    el = JasperHTML::Element.new("input", {"type" => "text"})
    el.has_attribute?("type").should be_true
    el.has_attribute?("value").should be_false
  end
end

describe JasperHTML::Text do
  it "stores text data" do
    text = JasperHTML::Text.new("Hello, world!")
    text.data.should eq("Hello, world!")
    text.name.should eq("#text")
  end
end

describe JasperHTML::Comment do
  it "stores comment data" do
    comment = JasperHTML::Comment.new("This is a comment")
    comment.data.should eq("This is a comment")
    comment.name.should eq("#comment")
  end
end
