require "./spec_helper"

describe JustHTML::Constants do
  describe "VOID_ELEMENTS" do
    it "includes br, hr, img, input" do
      JustHTML::Constants::VOID_ELEMENTS.should contain("br")
      JustHTML::Constants::VOID_ELEMENTS.should contain("hr")
      JustHTML::Constants::VOID_ELEMENTS.should contain("img")
      JustHTML::Constants::VOID_ELEMENTS.should contain("input")
    end
  end

  describe "SPECIAL_ELEMENTS" do
    it "includes html, head, body, div" do
      JustHTML::Constants::SPECIAL_ELEMENTS.should contain("html")
      JustHTML::Constants::SPECIAL_ELEMENTS.should contain("head")
      JustHTML::Constants::SPECIAL_ELEMENTS.should contain("body")
      JustHTML::Constants::SPECIAL_ELEMENTS.should contain("div")
    end
  end

  describe "FORMATTING_ELEMENTS" do
    it "includes a, b, i, u" do
      JustHTML::Constants::FORMATTING_ELEMENTS.should contain("a")
      JustHTML::Constants::FORMATTING_ELEMENTS.should contain("b")
      JustHTML::Constants::FORMATTING_ELEMENTS.should contain("i")
      JustHTML::Constants::FORMATTING_ELEMENTS.should contain("u")
    end
  end
end
