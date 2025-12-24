require "./entities_data"

module JustHTML
  module Entities
    # Legacy named character references that can be used without semicolons
    LEGACY_ENTITIES = Set{
      "gt", "lt", "amp", "quot", "nbsp",
      "AMP", "QUOT", "GT", "LT", "COPY", "REG",
      "AElig", "Aacute", "Acirc", "Agrave", "Aring", "Atilde", "Auml",
      "Ccedil", "ETH", "Eacute", "Ecirc", "Egrave", "Euml",
      "Iacute", "Icirc", "Igrave", "Iuml", "Ntilde",
      "Oacute", "Ocirc", "Ograve", "Oslash", "Otilde", "Ouml",
      "THORN", "Uacute", "Ucirc", "Ugrave", "Uuml", "Yacute",
      "aacute", "acirc", "acute", "aelig", "agrave", "aring", "atilde", "auml",
      "brvbar", "ccedil", "cedil", "cent", "copy", "curren",
      "deg", "divide", "eacute", "ecirc", "egrave", "eth", "euml",
      "frac12", "frac14", "frac34",
      "iacute", "icirc", "iexcl", "igrave", "iquest", "iuml",
      "laquo", "macr", "micro", "middot", "not", "ntilde",
      "oacute", "ocirc", "ograve", "ordf", "ordm", "oslash", "otilde", "ouml",
      "para", "plusmn", "pound", "raquo", "reg", "sect", "shy",
      "sup1", "sup2", "sup3", "szlig", "thorn", "times",
      "uacute", "ucirc", "ugrave", "uml", "uuml", "yacute", "yen", "yuml",
    }

    # HTML5 numeric character reference replacements
    NUMERIC_REPLACEMENTS = {
      0x00 => 0xFFFD, # NULL -> REPLACEMENT CHARACTER
      0x80 => 0x20AC, # EURO SIGN
      0x82 => 0x201A, # SINGLE LOW-9 QUOTATION MARK
      0x83 => 0x0192, # LATIN SMALL LETTER F WITH HOOK
      0x84 => 0x201E, # DOUBLE LOW-9 QUOTATION MARK
      0x85 => 0x2026, # HORIZONTAL ELLIPSIS
      0x86 => 0x2020, # DAGGER
      0x87 => 0x2021, # DOUBLE DAGGER
      0x88 => 0x02C6, # MODIFIER LETTER CIRCUMFLEX ACCENT
      0x89 => 0x2030, # PER MILLE SIGN
      0x8A => 0x0160, # LATIN CAPITAL LETTER S WITH CARON
      0x8B => 0x2039, # SINGLE LEFT-POINTING ANGLE QUOTATION MARK
      0x8C => 0x0152, # LATIN CAPITAL LIGATURE OE
      0x8E => 0x017D, # LATIN CAPITAL LETTER Z WITH CARON
      0x91 => 0x2018, # LEFT SINGLE QUOTATION MARK
      0x92 => 0x2019, # RIGHT SINGLE QUOTATION MARK
      0x93 => 0x201C, # LEFT DOUBLE QUOTATION MARK
      0x94 => 0x201D, # RIGHT DOUBLE QUOTATION MARK
      0x95 => 0x2022, # BULLET
      0x96 => 0x2013, # EN DASH
      0x97 => 0x2014, # EM DASH
      0x98 => 0x02DC, # SMALL TILDE
      0x99 => 0x2122, # TRADE MARK SIGN
      0x9A => 0x0161, # LATIN SMALL LETTER S WITH CARON
      0x9B => 0x203A, # SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
      0x9C => 0x0153, # LATIN SMALL LIGATURE OE
      0x9E => 0x017E, # LATIN SMALL LETTER Z WITH CARON
      0x9F => 0x0178, # LATIN CAPITAL LETTER Y WITH DIAERESIS
    }

    def self.decode(text : String, in_attribute : Bool = false) : String
      return text unless text.includes?('&')

      result = String::Builder.new(text.bytesize)
      i = 0
      length = text.size

      while i < length
        next_amp = text.index('&', i)
        if next_amp.nil?
          result << text[i..]
          break
        end

        if next_amp > i
          result << text[i...next_amp]
        end

        i = next_amp
        j = i + 1

        # Check for numeric entity
        if j < length && text[j] == '#'
          j += 1
          is_hex = false

          if j < length && (text[j] == 'x' || text[j] == 'X')
            is_hex = true
            j += 1
          end

          # Collect digits
          digit_start = j
          if is_hex
            while j < length && (text[j].ascii_number? || ('a'..'f').includes?(text[j].downcase))
              j += 1
            end
          else
            while j < length && text[j].ascii_number?
              j += 1
            end
          end

          has_semicolon = j < length && text[j] == ';'
          digit_text = text[digit_start...j]

          if !digit_text.empty?
            codepoint = is_hex ? digit_text.to_i(16) : digit_text.to_i

            # Apply replacements
            if replacement = NUMERIC_REPLACEMENTS[codepoint]?
              codepoint = replacement
            end

            # Invalid ranges
            if codepoint > 0x10FFFF || (0xD800..0xDFFF).includes?(codepoint)
              codepoint = 0xFFFD
            end

            result << codepoint.chr
            i = has_semicolon ? j + 1 : j
            next
          end

          # Invalid numeric entity, keep as-is
          result << text[i...(has_semicolon ? j + 1 : j)]
          i = has_semicolon ? j + 1 : j
          next
        end

        # Named entity
        while j < length && (text[j].ascii_letter? || text[j].ascii_number?)
          j += 1
        end

        entity_name = text[(i + 1)...j]
        has_semicolon = j < length && text[j] == ';'

        if entity_name.empty?
          result << '&'
          i += 1
          next
        end

        # Try exact match with semicolon
        if has_semicolon && NAMED_ENTITIES.has_key?(entity_name)
          result << NAMED_ENTITIES[entity_name]
          i = j + 1
          next
        end

        # Try without semicolon for legacy entities
        if LEGACY_ENTITIES.includes?(entity_name) && NAMED_ENTITIES.has_key?(entity_name)
          next_char = j < length ? text[j] : nil
          if in_attribute && next_char && (next_char.ascii_alphanumeric? || next_char == '=')
            result << '&'
            i += 1
            next
          end

          result << NAMED_ENTITIES[entity_name]
          i = j
          next
        end

        # Try longest prefix match for legacy entities
        best_match : String? = nil
        best_match_len = 0
        (entity_name.size - 1).downto(1) do |k|
          prefix = entity_name[0...k]
          if LEGACY_ENTITIES.includes?(prefix) && NAMED_ENTITIES.has_key?(prefix)
            best_match = NAMED_ENTITIES[prefix]
            best_match_len = k
            break
          end
        end

        if best_match
          end_pos = i + 1 + best_match_len
          next_char = end_pos < length ? text[end_pos] : nil
          if in_attribute && next_char && (next_char.ascii_alphanumeric? || next_char == '=')
            result << '&'
            i += 1
            next
          end

          result << best_match
          i = i + 1 + best_match_len
          next
        end

        # No match found
        if has_semicolon
          result << text[i..j]
          i = j + 1
        else
          result << '&'
          i += 1
        end
      end

      result.to_s
    end
  end
end
