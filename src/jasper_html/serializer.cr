module JasperHTML
  module Serializer
    # Block-level elements that should have newlines in text output
    BLOCK_ELEMENTS = Set{
      "address", "article", "aside", "blockquote", "br", "dd", "details", "dialog",
      "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
      "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li", "main",
      "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot",
      "th", "thead", "tr", "ul",
    }

    # Elements whose content should be skipped in text extraction
    SKIP_ELEMENTS = Set{"script", "style", "template", "noscript"}

    # Raw text elements (content should not be escaped)
    RAW_TEXT_ELEMENTS = Set{"script", "style", "xmp", "iframe", "noembed", "noframes", "plaintext"}

    def self.to_html(node : Node) : String
      builder = String::Builder.new
      serialize_node(node, builder)
      builder.to_s
    end

    def self.to_text(node : Node) : String
      builder = String::Builder.new
      extract_text(node, builder)
      result = builder.to_s
      # Normalize whitespace: collapse multiple spaces/newlines
      result.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
    end

    private def self.serialize_node(node : Node, builder : String::Builder) : Nil
      case node
      when Document
        node.children.each { |child| serialize_node(child, builder) }
      when DocumentFragment
        node.children.each { |child| serialize_node(child, builder) }
      when DoctypeNode
        serialize_doctype(node, builder)
      when Element
        serialize_element(node, builder)
      when Text
        serialize_text(node, builder, raw: false)
      when Comment
        serialize_comment(node, builder)
      end
    end

    private def self.serialize_doctype(node : DoctypeNode, builder : String::Builder) : Nil
      builder << "<!DOCTYPE "
      builder << (node.doctype_name || "html")
      if public_id = node.public_id
        builder << " PUBLIC \""
        builder << public_id
        builder << "\""
        if system_id = node.system_id
          builder << " \""
          builder << system_id
          builder << "\""
        end
      elsif system_id = node.system_id
        builder << " SYSTEM \""
        builder << system_id
        builder << "\""
      end
      builder << ">"
    end

    private def self.serialize_element(node : Element, builder : String::Builder) : Nil
      name = node.name

      # Opening tag
      builder << "<"
      builder << name

      # Attributes
      node.attrs.each do |attr_name, attr_value|
        builder << " "
        builder << attr_name
        if attr_value
          builder << "=\""
          builder << escape_attribute(attr_value)
          builder << "\""
        end
      end

      builder << ">"

      # Void elements don't have content or closing tag
      if Constants::VOID_ELEMENTS.includes?(name)
        return
      end

      # Content
      is_raw = RAW_TEXT_ELEMENTS.includes?(name)
      node.children.each do |child|
        if child.is_a?(Text)
          serialize_text(child, builder, raw: is_raw)
        else
          serialize_node(child, builder)
        end
      end

      # Closing tag
      builder << "</"
      builder << name
      builder << ">"
    end

    private def self.serialize_text(node : Text, builder : String::Builder, raw : Bool) : Nil
      if raw
        builder << node.data
      else
        builder << escape_text(node.data)
      end
    end

    private def self.serialize_comment(node : Comment, builder : String::Builder) : Nil
      builder << "<!--"
      builder << node.data
      builder << "-->"
    end

    private def self.escape_text(text : String) : String
      text.gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
    end

    private def self.escape_attribute(text : String) : String
      text.gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
    end

    # Text extraction

    private def self.extract_text(node : Node, builder : String::Builder) : Nil
      case node
      when Document, DocumentFragment
        node.children.each { |child| extract_text(child, builder) }
      when Element
        extract_text_from_element(node, builder)
      when Text
        builder << node.data
      end
    end

    private def self.extract_text_from_element(node : Element, builder : String::Builder) : Nil
      name = node.name

      # Skip certain elements
      return if SKIP_ELEMENTS.includes?(name)

      # Add newline before block elements (except first)
      if BLOCK_ELEMENTS.includes?(name) && builder.bytesize > 0
        builder << "\n"
      end

      # Process children
      node.children.each do |child|
        extract_text(child, builder)
      end

      # Add newline after block elements
      if BLOCK_ELEMENTS.includes?(name)
        builder << "\n"
      end
    end
  end
end
