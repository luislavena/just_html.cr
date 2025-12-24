require "./spec_helper"

describe JustHTML::Entities do
  describe ".decode" do
    it "decodes named entities" do
      JustHTML::Entities.decode("&amp;").should eq("&")
      JustHTML::Entities.decode("&lt;").should eq("<")
      JustHTML::Entities.decode("&gt;").should eq(">")
      JustHTML::Entities.decode("&quot;").should eq("\"")
      JustHTML::Entities.decode("&apos;").should eq("'")
      JustHTML::Entities.decode("&nbsp;").should eq("\u00A0")
    end

    it "decodes numeric entities" do
      JustHTML::Entities.decode("&#65;").should eq("A")
      JustHTML::Entities.decode("&#x41;").should eq("A")
      JustHTML::Entities.decode("&#X41;").should eq("A")
    end

    it "handles invalid entities" do
      JustHTML::Entities.decode("&invalid;").should eq("&invalid;")
    end

    it "decodes entities in text" do
      JustHTML::Entities.decode("Hello &amp; world").should eq("Hello & world")
      JustHTML::Entities.decode("&lt;div&gt;").should eq("<div>")
    end
  end
end
