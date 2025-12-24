module JasperHTML
  module Encoding
    # Maximum bytes to scan for charset in meta tags
    PRESCAN_LIMIT = 1024

    # Encoding name aliases (lowercase -> canonical name)
    ENCODING_ALIASES = {
      # UTF-8
      "utf-8"          => "UTF-8",
      "utf8"           => "UTF-8",
      "unicode-1-1-utf-8" => "UTF-8",

      # UTF-16
      "utf-16"         => "UTF-16",
      "utf-16le"       => "UTF-16LE",
      "utf-16be"       => "UTF-16BE",

      # ISO-8859-1 (Latin-1)
      "iso-8859-1"     => "ISO-8859-1",
      "iso8859-1"      => "ISO-8859-1",
      "iso88591"       => "ISO-8859-1",
      "latin1"         => "ISO-8859-1",
      "latin-1"        => "ISO-8859-1",
      "l1"             => "ISO-8859-1",
      "csisolatin1"    => "ISO-8859-1",

      # Windows-1252 (superset of ISO-8859-1)
      "windows-1252"   => "windows-1252",
      "cp1252"         => "windows-1252",
      "x-cp1252"       => "windows-1252",

      # ASCII -> windows-1252 per HTML5 spec
      "ascii"          => "windows-1252",
      "us-ascii"       => "windows-1252",
      "iso-ir-6"       => "windows-1252",

      # ISO-8859-2 through ISO-8859-16
      "iso-8859-2"     => "ISO-8859-2",
      "iso-8859-3"     => "ISO-8859-3",
      "iso-8859-4"     => "ISO-8859-4",
      "iso-8859-5"     => "ISO-8859-5",
      "iso-8859-6"     => "ISO-8859-6",
      "iso-8859-7"     => "ISO-8859-7",
      "iso-8859-8"     => "ISO-8859-8",
      "iso-8859-9"     => "ISO-8859-9",
      "iso-8859-10"    => "ISO-8859-10",
      "iso-8859-13"    => "ISO-8859-13",
      "iso-8859-14"    => "ISO-8859-14",
      "iso-8859-15"    => "ISO-8859-15",
      "iso-8859-16"    => "ISO-8859-16",

      # Windows codepages
      "windows-1250"   => "windows-1250",
      "windows-1251"   => "windows-1251",
      "windows-1253"   => "windows-1253",
      "windows-1254"   => "windows-1254",
      "windows-1255"   => "windows-1255",
      "windows-1256"   => "windows-1256",
      "windows-1257"   => "windows-1257",
      "windows-1258"   => "windows-1258",

      # KOI8
      "koi8-r"         => "KOI8-R",
      "koi8-u"         => "KOI8-U",

      # Chinese
      "gbk"            => "GBK",
      "gb2312"         => "GBK",
      "gb18030"        => "gb18030",
      "big5"           => "Big5",

      # Japanese
      "euc-jp"         => "EUC-JP",
      "shift_jis"      => "Shift_JIS",
      "shift-jis"      => "Shift_JIS",
      "iso-2022-jp"    => "ISO-2022-JP",

      # Korean
      "euc-kr"         => "EUC-KR",
    }

    # Detect encoding from BOM (Byte Order Mark)
    # Returns tuple of (encoding_name, bom_length) or nil
    def self.detect_bom(bytes : Bytes) : Tuple(String, Int32)?
      return nil if bytes.size < 2

      # UTF-8 BOM: EF BB BF
      if bytes.size >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
        return {"UTF-8", 3}
      end

      # UTF-16 LE BOM: FF FE
      if bytes[0] == 0xFF && bytes[1] == 0xFE
        return {"UTF-16LE", 2}
      end

      # UTF-16 BE BOM: FE FF
      if bytes[0] == 0xFE && bytes[1] == 0xFF
        return {"UTF-16BE", 2}
      end

      nil
    end

    # Prescan HTML for meta charset declaration
    # This is a simplified implementation of the HTML5 prescan algorithm
    def self.prescan_meta_charset(bytes : Bytes) : String?
      # Limit scan to PRESCAN_LIMIT bytes
      scan_bytes = bytes.size > PRESCAN_LIMIT ? bytes[0, PRESCAN_LIMIT] : bytes

      # Convert to string for easier parsing (assuming ASCII-compatible at this stage)
      html = String.new(scan_bytes)

      # Look for <meta charset="..."> or <meta ... charset="...">
      pos = 0
      while pos < html.size
        # Find next '<'
        tag_start = html.index('<', pos)
        break unless tag_start

        # Check if it's a meta tag
        if html[tag_start..].downcase.starts_with?("<meta")
          tag_end = html.index('>', tag_start)
          break unless tag_end

          tag_content = html[tag_start..tag_end]

          # Look for charset attribute
          if charset = extract_charset(tag_content)
            return normalize_encoding_name(charset)
          end

          # Look for http-equiv content-type with charset
          if tag_content.downcase.includes?("http-equiv") && tag_content.downcase.includes?("content-type")
            if charset = extract_content_charset(tag_content)
              return normalize_encoding_name(charset)
            end
          end

          pos = tag_end + 1
        elsif html[tag_start..].downcase.starts_with?("</head") || html[tag_start..].downcase.starts_with?("<body")
          # Stop scanning at </head> or <body>
          break
        else
          pos = tag_start + 1
        end
      end

      nil
    end

    # Normalize encoding name to canonical form
    def self.normalize_encoding_name(name : String) : String?
      normalized = name.downcase.strip
      ENCODING_ALIASES[normalized]?
    end

    # Main detection function - tries BOM, then meta, then defaults to UTF-8
    def self.detect(bytes : Bytes) : String
      # Try BOM first
      if bom_result = detect_bom(bytes)
        encoding, _ = bom_result
        return encoding
      end

      # Try meta charset prescan
      if charset = prescan_meta_charset(bytes)
        return charset
      end

      # Default to UTF-8
      "UTF-8"
    end

    # Extract charset value from a meta tag
    private def self.extract_charset(tag : String) : String?
      # Match charset='value' or charset="value" or charset=value
      if match = tag.match(/charset\s*=\s*["']?([^"'\s>]+)/i)
        return match[1]
      end
      nil
    end

    # Extract charset from content attribute (for http-equiv content-type)
    private def self.extract_content_charset(tag : String) : String?
      # Look for content="...charset=..."
      if match = tag.match(/content\s*=\s*["']?[^"']*charset\s*=\s*([^"'\s;>]+)/i)
        return match[1]
      end
      nil
    end
  end
end
