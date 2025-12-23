require "./spec_helper"

describe JasperHTML::Entities do
  describe ".decode" do
    it "decodes named entities" do
      JasperHTML::Entities.decode("&amp;").should eq("&")
      JasperHTML::Entities.decode("&lt;").should eq("<")
      JasperHTML::Entities.decode("&gt;").should eq(">")
      JasperHTML::Entities.decode("&quot;").should eq("\"")
      JasperHTML::Entities.decode("&apos;").should eq("'")
      JasperHTML::Entities.decode("&nbsp;").should eq("\u00A0")
    end

    it "decodes numeric entities" do
      JasperHTML::Entities.decode("&#65;").should eq("A")
      JasperHTML::Entities.decode("&#x41;").should eq("A")
      JasperHTML::Entities.decode("&#X41;").should eq("A")
    end

    it "handles invalid entities" do
      JasperHTML::Entities.decode("&invalid;").should eq("&invalid;")
    end

    it "decodes entities in text" do
      JasperHTML::Entities.decode("Hello &amp; world").should eq("Hello & world")
      JasperHTML::Entities.decode("&lt;div&gt;").should eq("<div>")
    end
  end
end
