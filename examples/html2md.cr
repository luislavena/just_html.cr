require "../src/just_html"
require "http/client"

# Convert HTML elements to Markdown format
class MarkdownConverter
  @output : String::Builder
  @list_depth : Int32

  def initialize
    @output = String::Builder.new
    @list_depth = 0
  end

  def convert(node : JustHTML::Node) : String
    traverse(node)
    @output.to_s.strip
  end

  private def traverse(node : JustHTML::Node)
    case node
    when JustHTML::Element
      convert_element(node)
    when JustHTML::Text
      # Only output text if it has non-whitespace content
      text = node.data.strip
      @output << text << " " unless text.empty?
    when JustHTML::Document
      node.children.each { |child| traverse(child) }
    when JustHTML::DocumentFragment
      node.children.each { |child| traverse(child) }
    end
  end

  private def convert_element(element : JustHTML::Element)
    case element.name
    when "h1"
      @output << "\n\n# "
      traverse_children(element)
      @output << "\n"
    when "h2"
      @output << "\n\n## "
      traverse_children(element)
      @output << "\n"
    when "h3"
      @output << "\n\n### "
      traverse_children(element)
      @output << "\n"
    when "h4"
      @output << "\n\n#### "
      traverse_children(element)
      @output << "\n"
    when "h5"
      @output << "\n\n##### "
      traverse_children(element)
      @output << "\n"
    when "h6"
      @output << "\n\n###### "
      traverse_children(element)
      @output << "\n"
    when "p"
      @output << "\n\n"
      traverse_children(element)
      @output << "\n"
    when "a"
      href = element["href"]
      @output << "["
      traverse_children(element)
      @output << "](" << (href || "") << ")"
    when "ul"
      @list_depth += 1
      element.children.each { |child| traverse(child) }
      @list_depth -= 1
      @output << "\n" if @list_depth == 0
    when "ol"
      @list_depth += 1
      element.children.each_with_index do |child, index|
        if child.is_a?(JustHTML::Element) && child.name == "li"
          convert_ordered_list_item(child, index + 1)
        else
          traverse(child)
        end
      end
      @list_depth -= 1
      @output << "\n" if @list_depth == 0
    when "li"
      # Handle unordered list items (ordered items handled in "ol" case)
      @output << "\n"
      @output << "  " * (@list_depth - 1) if @list_depth > 1
      @output << "- "
      traverse_children(element)
    when "br"
      @output << "  \n"
    when "strong", "b"
      @output << "**"
      traverse_children(element)
      @output << "**"
    when "em", "i"
      @output << "*"
      traverse_children(element)
      @output << "*"
    when "code"
      @output << "`"
      traverse_children(element)
      @output << "`"
    when "pre"
      @output << "\n\n```\n"
      traverse_children(element)
      @output << "\n```\n"
    when "blockquote"
      @output << "\n\n> "
      traverse_children(element)
      @output << "\n"
    when "style", "script", "noscript"
      # Skip these elements and their content entirely
    else
      # For all other elements, just traverse children
      traverse_children(element)
    end
  end

  private def convert_ordered_list_item(element : JustHTML::Element, index : Int32)
    @output << "\n"
    @output << "  " * (@list_depth - 1) if @list_depth > 1
    @output << "#{index}. "
    traverse_children(element)
  end

  private def traverse_children(element : JustHTML::Element)
    element.children.each { |child| traverse(child) }
  end
end

# Fetch HTML from URL or read from stdin
def get_html(url : String?) : String
  if url
    # Follow up to 5 redirects
    current_url = url
    5.times do
      uri = URI.parse(current_url)
      HTTP::Client.new(uri) do |client|
        response = client.get(uri.request_target)

        if response.status.redirection?
          location = response.headers["Location"]?
          unless location
            STDERR.puts "Redirect without Location header"
            exit 1
          end
          # Handle relative redirects
          current_url = URI.parse(current_url).resolve(location).to_s
          next
        end

        unless response.success?
          STDERR.puts "Error fetching URL: #{response.status}"
          exit 1
        end

        return response.body
      end
    end

    STDERR.puts "Too many redirects"
    exit 1
  else
    STDIN.gets_to_end
  end
end

# Main execution
if ARGV.size > 1
  STDERR.puts "Usage: #{PROGRAM_NAME} [URL]"
  STDERR.puts "  If URL is provided, fetch and convert that page"
  STDERR.puts "  If no URL is provided, read HTML from stdin"
  exit 1
end

url = ARGV[0]? unless ARGV.empty?
html = get_html(url)

doc = JustHTML.parse(html)
converter = MarkdownConverter.new
markdown = converter.convert(doc)

puts markdown
