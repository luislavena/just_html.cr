require "./jasper_html/version"
require "./jasper_html/errors"
require "./jasper_html/tokens"
require "./jasper_html/constants"
require "./jasper_html/node"
require "./jasper_html/entities"
require "./jasper_html/selector"
require "./jasper_html/element"
require "./jasper_html/tokenizer"
require "./jasper_html/tree_builder"
require "./jasper_html/serializer"
require "./jasper_html/encoding"

module JasperHTML
  # Parse an HTML document string into a Document
  def self.parse(html : String, collect_errors : Bool = false) : Document
    TreeBuilder.parse(html, collect_errors)
  end

  # Parse an HTML fragment string into a DocumentFragment
  def self.parse_fragment(html : String, context : String = "body", collect_errors : Bool = false) : DocumentFragment
    FragmentBuilder.parse(html, context, collect_errors)
  end
end
