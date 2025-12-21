require "./spec_helper"

describe JasperHTML::Error do
  it "is a base exception" do
    error = JasperHTML::Error.new("test")
    error.should be_a(Exception)
  end
end

describe JasperHTML::ParseError do
  it "stores error details" do
    error = JasperHTML::ParseError.new(
      code: "unexpected-null-character",
      line: 1,
      column: 5,
      message: "Unexpected null character"
    )
    error.code.should eq("unexpected-null-character")
    error.line.should eq(1)
    error.column.should eq(5)
    error.message.should eq("Unexpected null character")
  end

  it "formats error string with location" do
    error = JasperHTML::ParseError.new(
      code: "eof-in-tag",
      line: 3,
      column: 10
    )
    error.to_s.should contain("(3,10)")
    error.to_s.should contain("eof-in-tag")
  end
end

describe JasperHTML::SelectorError do
  it "inherits from Error" do
    error = JasperHTML::SelectorError.new("invalid selector")
    error.should be_a(JasperHTML::Error)
  end
end
