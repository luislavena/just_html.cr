require "./just_html/version"
require "./just_html/errors"
require "./just_html/tokens"
require "./just_html/constants"
require "./just_html/node"
require "./just_html/entities"
require "./just_html/selector"
require "./just_html/element"
require "./just_html/tokenizer"
require "./just_html/tree_builder"
require "./just_html/serializer"
require "./just_html/encoding"

module JustHTML
  # Parse an HTML document string into a Document
  def self.parse(html : String, collect_errors : Bool = false) : Document
    TreeBuilder.parse(html, collect_errors)
  end

  # Parse an HTML fragment string into a DocumentFragment
  def self.parse_fragment(html : String, context : String = "body", context_namespace : String? = nil, collect_errors : Bool = false) : DocumentFragment
    # Normalize "html" namespace to nil for consistency with spec
    ns = context_namespace == "html" ? nil : context_namespace
    TreeBuilder.parse_fragment(html, context, ns, collect_errors)
  end
end
