# JustHTML

A pure Crystal HTML5 parser that passes the full html5lib-tests suite.

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

# Parse an HTML document
doc = JustHTML.parse("<html><body><p>Hello, world!</p></body></html>")

# Query elements using CSS selectors
p = doc.query_selector("p")
puts p.not_nil!.text_content  # => "Hello, world!"

# Parse an HTML fragment
fragment = JustHTML.parse_fragment("<p>Hello</p><p>World</p>")
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/luislavena/just_html.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Luis Lavena](https://github.com/luislavena) - creator and maintainer
