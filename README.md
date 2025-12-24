# JustHTML

A pure Crystal HTML5 parser aiming to pass the full html5lib-tests suite.

## Why use JustHTML?

### Correct

It implements the official WHATWG HTML5 specification exactly. If a browser can parse it, JustHTML can parse it.

- **Work in progress**: Currently passes ~59% (4,872/8,191) of the official [html5lib-tests](https://github.com/html5lib/html5lib-tests) suite (tree construction and tokenizer tests)
- **Living standard**: Tracks the current WHATWG specification, not a snapshot from years ago

### Pure Crystal

JustHTML has zero dependencies. It's pure Crystal.

- **Just install**: No C extensions to compile, no system libraries required
- **Debuggable**: Step through the code with a debugger to understand exactly how your HTML is being parsed
- **Simple types**: Returns plain Crystal objects you can iterate over and inspect

### Query

Find elements with CSS selectors. Use `query_selector` and `query_selector_all` with syntax you already know.

```crystal
doc.query_selector("div.container > p")   # Child combinator
doc.query_selector("#main, .sidebar")     # Selector groups
doc.query_selector("li:nth-child(2n+1)")  # Pseudo-classes
doc.query_selector("a[href^='https']")    # Attribute selectors
```

### Fast

Crystal compiles to native code, providing good performance without sacrificing correctness.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     just_html:
       github: luislavena/just_html.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "just_html"

# Parse a complete HTML document
doc = JustHTML.parse("<html><body><p class='intro'>Hello!</p></body></html>")

# Query with CSS selectors
p = doc.query_selector("p.intro")
puts p.not_nil!.text_content  # => "Hello!"

# Query all matching elements
paragraphs = doc.query_selector_all("p")
paragraphs.each do |para|
  puts para.text_content
end

# Parse an HTML fragment
fragment = JustHTML.parse_fragment("<p>Hello</p><p>World</p>")

# Parse fragment with context element (for proper parsing of elements like <li>)
list_items = JustHTML.parse_fragment("<li>One</li><li>Two</li>", context: "ul")

# Serialize back to HTML
puts p.not_nil!.to_html  # => "<p class=\"intro\">Hello!</p>"

# Tree traversal
doc.document_element.not_nil!.children.each do |child|
  puts child.node_name
end
```

## Development

### Running tests

```console
crystal spec
```

### Running html5lib-tests

JustHTML is verified against the official html5lib-tests suite. To run these tests:

1. Clone the html5lib-tests repository (if not already available):

   ```console
   git clone https://github.com/html5lib/html5lib-tests.git
   ```

2. Create the required symlinks in the `tests` directory:

   ```console
   mkdir -p tests
   ln -s ../html5lib-tests/tree-construction tests/html5lib-tests-tree
   ln -s ../html5lib-tests/tokenizer tests/html5lib-tests-tokenizer
   ```

3. Build and run the test runner:

   ```console
   crystal build run_tests.cr -o run_tests
   ./run_tests
   ```

#### Test runner options

- `-v`, `--verbose`: Show details of failing tests
- `-x`, `--fail-fast`: Stop on first failure
- `-q`, `--quiet`: Only show summary
- `--test-specs SPECS`: Run specific tests (e.g., `tests1.dat:0,1,2`)

## Contributing

1. Fork it (<https://github.com/luislavena/just_html.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Acknowledgments

This Crystal implementation was entirely produced using [Claude Code](https://claude.ai/claude-code)
with the Opus model. The architecture is inspired by [justhtml](https://github.com/EmilStenstrom/justhtml),
a Python HTML5 parser, which itself drew from [html5ever](https://github.com/servo/html5ever),
the HTML5 parser from Mozilla's Servo browser engine.

## Contributors

- [Luis Lavena](https://github.com/luislavena) - creator and maintainer
