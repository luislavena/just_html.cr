require "./spec_helper"

describe JasperHTML::Encoding do
  describe ".detect_bom" do
    it "detects UTF-8 BOM" do
      bytes = Bytes[0xEF, 0xBB, 0xBF, 0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E]
      result = JasperHTML::Encoding.detect_bom(bytes)
      result.should eq({"UTF-8", 3})
    end

    it "detects UTF-16 LE BOM" do
      bytes = Bytes[0xFF, 0xFE, 0x3C, 0x00]
      result = JasperHTML::Encoding.detect_bom(bytes)
      result.should eq({"UTF-16LE", 2})
    end

    it "detects UTF-16 BE BOM" do
      bytes = Bytes[0xFE, 0xFF, 0x00, 0x3C]
      result = JasperHTML::Encoding.detect_bom(bytes)
      result.should eq({"UTF-16BE", 2})
    end

    it "returns nil for no BOM" do
      bytes = Bytes[0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E]
      result = JasperHTML::Encoding.detect_bom(bytes)
      result.should be_nil
    end
  end

  describe ".prescan_meta_charset" do
    it "detects charset from meta tag" do
      html = "<html><head><meta charset='utf-8'></head></html>"
      result = JasperHTML::Encoding.prescan_meta_charset(html.to_slice)
      result.should eq("UTF-8")
    end

    it "detects charset from content-type meta" do
      html = "<html><head><meta http-equiv='content-type' content='text/html; charset=iso-8859-1'></head></html>"
      result = JasperHTML::Encoding.prescan_meta_charset(html.to_slice)
      result.should eq("ISO-8859-1")
    end

    it "returns nil when no charset found" do
      html = "<html><head><title>Test</title></head></html>"
      result = JasperHTML::Encoding.prescan_meta_charset(html.to_slice)
      result.should be_nil
    end

    it "stops scanning at 1024 bytes" do
      # Create HTML with charset after 1024 bytes
      padding = "x" * 1100
      html = "<html>#{padding}<meta charset='utf-8'></html>"
      result = JasperHTML::Encoding.prescan_meta_charset(html.to_slice)
      result.should be_nil
    end

    it "handles uppercase charset names" do
      html = "<meta charset='UTF-8'>"
      result = JasperHTML::Encoding.prescan_meta_charset(html.to_slice)
      result.should eq("UTF-8")
    end

    it "handles quoted charset values" do
      html = "<meta charset=\"utf-8\">"
      result = JasperHTML::Encoding.prescan_meta_charset(html.to_slice)
      result.should eq("UTF-8")
    end
  end

  describe ".normalize_encoding_name" do
    it "normalizes common encoding names" do
      JasperHTML::Encoding.normalize_encoding_name("utf-8").should eq("UTF-8")
      JasperHTML::Encoding.normalize_encoding_name("UTF8").should eq("UTF-8")
      JasperHTML::Encoding.normalize_encoding_name("iso-8859-1").should eq("ISO-8859-1")
      JasperHTML::Encoding.normalize_encoding_name("latin1").should eq("ISO-8859-1")
      JasperHTML::Encoding.normalize_encoding_name("ascii").should eq("windows-1252")
    end

    it "returns nil for unknown encodings" do
      JasperHTML::Encoding.normalize_encoding_name("unknown-encoding").should be_nil
    end
  end

  describe ".detect" do
    it "uses BOM when present" do
      bytes = Bytes[0xEF, 0xBB, 0xBF, 0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E]
      result = JasperHTML::Encoding.detect(bytes)
      result.should eq("UTF-8")
    end

    it "uses meta charset when no BOM" do
      html = "<html><head><meta charset='iso-8859-1'></head></html>"
      result = JasperHTML::Encoding.detect(html.to_slice)
      result.should eq("ISO-8859-1")
    end

    it "defaults to UTF-8 when nothing detected" do
      html = "<html><body>Hello</body></html>"
      result = JasperHTML::Encoding.detect(html.to_slice)
      result.should eq("UTF-8")
    end
  end
end
