require "./spec_helper"

describe JasperHTML::Constants do
  describe "VOID_ELEMENTS" do
    it "includes br, hr, img, input" do
      JasperHTML::Constants::VOID_ELEMENTS.should contain("br")
      JasperHTML::Constants::VOID_ELEMENTS.should contain("hr")
      JasperHTML::Constants::VOID_ELEMENTS.should contain("img")
      JasperHTML::Constants::VOID_ELEMENTS.should contain("input")
    end
  end

  describe "SPECIAL_ELEMENTS" do
    it "includes html, head, body, div" do
      JasperHTML::Constants::SPECIAL_ELEMENTS.should contain("html")
      JasperHTML::Constants::SPECIAL_ELEMENTS.should contain("head")
      JasperHTML::Constants::SPECIAL_ELEMENTS.should contain("body")
      JasperHTML::Constants::SPECIAL_ELEMENTS.should contain("div")
    end
  end

  describe "FORMATTING_ELEMENTS" do
    it "includes a, b, i, u" do
      JasperHTML::Constants::FORMATTING_ELEMENTS.should contain("a")
      JasperHTML::Constants::FORMATTING_ELEMENTS.should contain("b")
      JasperHTML::Constants::FORMATTING_ELEMENTS.should contain("i")
      JasperHTML::Constants::FORMATTING_ELEMENTS.should contain("u")
    end
  end
end
