require "./spec/support/html5lib_test_data"
require "option_parser"

module HTML5LibTests
  VERSION = "1.0.0"

  # Alias for convenience
  alias TreeConstructionTest = HTML5LibTestData::TreeConstructionTest

  # Test result for tracking
  class TestResult
    property passed : Bool
    property input : String
    property expected : String
    property actual : String

    def initialize(@passed : Bool, @input : String, @expected : String, @actual : String)
    end
  end

  # File results for reporting
  class FileResult
    property passed : Int32 = 0
    property failed : Int32 = 0
    property skipped : Int32 = 0
    property test_indices : Array(Tuple(Symbol, Int32))

    def initialize
      @test_indices = [] of Tuple(Symbol, Int32)
    end
  end

  class TestRunner
    getter test_dir : String
    getter verbosity : Int32
    getter fail_fast : Bool
    getter quiet : Bool
    getter test_specs : Array(String)
    getter file_results : Hash(String, FileResult)

    def initialize(@test_dir : String, @verbosity : Int32 = 0, @fail_fast : Bool = false,
                   @quiet : Bool = false, @test_specs : Array(String) = [] of String)
      @file_results = {} of String => FileResult
    end

    # Parse .dat file into test cases - delegates to shared module
    def parse_dat_file(path : String) : Array(TreeConstructionTest)
      content = File.read(path)
      HTML5LibTestData.parse_tree_construction_tests(content)
    end

    # Run a single tree construction test
    def run_single_tree_test(test : TreeConstructionTest) : TestResult
      begin
        if fragment_context = test.document_fragment
          # Parse fragment context - handle "svg path", "math mi", or just "body"
          parts = fragment_context.split(' ', 2)
          if parts.size == 2
            namespace = parts[0]
            # Normalize namespace: test files use "math", but internally we use "mathml"
            namespace = "mathml" if namespace == "math"
            context = parts[1]
          else
            namespace = "html"
            context = parts[0]
          end
          doc = JustHTML.parse_fragment(test.data, context, namespace)
          actual = HTML5LibTestData.serialize_to_test_format(doc)
        else
          doc = JustHTML.parse(test.data)
          actual = HTML5LibTestData.serialize_to_test_format(doc)
        end

        expected = test.document.strip
        passed = compare_outputs(expected, actual)

        TestResult.new(passed, test.data, expected, actual)
      rescue ex
        TestResult.new(false, test.data, test.document.strip, "ERROR: #{ex.message}")
      end
    end

    # Compare expected and actual outputs with whitespace normalization
    private def compare_outputs(expected : String, actual : String) : Bool
      normalize(expected) == normalize(actual)
    end

    private def normalize(text : String) : String
      text.strip.split('\n').map(&.rstrip).join('\n')
    end

    # Check if test should be run based on specs
    private def should_run_test?(filename : String, index : Int32) : Bool
      return true if @test_specs.empty?

      @test_specs.any? do |spec|
        if spec.includes?(':')
          spec_file, indices = spec.split(':', 2)
          filename.includes?(spec_file) && indices.split(',').includes?(index.to_s)
        else
          filename.includes?(spec)
        end
      end
    end

    # Run tree construction tests
    def run_tree_tests : Tuple(Int32, Int32, Int32)
      passed = 0
      failed = 0
      skipped = 0

      tree_dir = File.join(@test_dir, "html5lib-tests", "tree-construction")
      return {0, 0, 0} unless File.exists?(tree_dir)

      files = Dir.glob(File.join(tree_dir, "**", "*.dat")).sort_by { |f| natural_sort_key(f) }

      files.each do |path|
        # Skip scripted tests
        next if path.includes?("scripted")

        filename = path.sub("#{@test_dir}/", "")

        # Check if we should run this file based on specs
        next unless should_run_test?(filename, -1) || @test_specs.empty? || @test_specs.any? { |s| filename.includes?(s.split(':').first) }

        file_result = FileResult.new
        tests = parse_dat_file(path)

        tests.each_with_index do |test, i|
          # Skip if not in test specs
          unless should_run_test?(filename, i) || @test_specs.empty?
            next
          end

          # Skip script-on tests
          if test.script_directive == "script-on"
            file_result.skipped += 1
            file_result.test_indices << {:skip, i}
            skipped += 1
            next
          end

          result = run_single_tree_test(test)
          if result.passed
            file_result.passed += 1
            file_result.test_indices << {:pass, i}
            passed += 1
          else
            file_result.failed += 1
            file_result.test_indices << {:fail, i}
            failed += 1
            print_failure(path, i, result) if @verbosity >= 1
            return {passed, failed, skipped} if @fail_fast
          end
        end

        @file_results[filename] = file_result if file_result.test_indices.size > 0
      end

      {passed, failed, skipped}
    end

    private def print_failure(path : String, index : Int32, result : TestResult) : Nil
      puts "\nFAILED: #{File.basename(path)} test ##{index}"
      puts "=== INPUT HTML ==="
      puts result.input
      puts "\n=== EXPECTED ==="
      puts result.expected
      puts "\n=== ACTUAL ==="
      puts result.actual
      puts
    end

    # Natural sort key for file ordering - returns tuple for comparison
    private def natural_sort_key(path : String) : String
      # Pad numbers with zeros for natural sorting
      path.gsub(/\d+/) { |match| match.rjust(10, '0') }.downcase
    end

    # Run tokenizer tests from JSON files
    def run_tokenizer_tests : Tuple(Int32, Int32)
      passed = 0
      failed = 0

      tokenizer_dir = File.join(@test_dir, "html5lib-tests", "tokenizer")
      return {0, 0} unless File.exists?(tokenizer_dir)

      files = Dir.glob(File.join(tokenizer_dir, "*.test")).sort_by { |f| natural_sort_key(f) }

      files.each do |path|
        filename = path.sub("#{@test_dir}/", "")

        # Check if we should run this file
        next unless should_run_test?(filename, -1) || @test_specs.empty? || @test_specs.any? { |s| filename.includes?(s.split(':').first) }

        file_result = FileResult.new

        begin
          content = File.read(path)
          data = JSON.parse(content)

          test_key = data["tests"]? ? "tests" : "xmlViolationTests"
          tests = data[test_key].as_a

          tests.each_with_index do |test, i|
            # Skip if not in test specs
            unless should_run_test?(filename, i) || @test_specs.empty?
              next
            end

            if run_single_tokenizer_test(test, path, i)
              file_result.passed += 1
              file_result.test_indices << {:pass, i}
              passed += 1
            else
              file_result.failed += 1
              file_result.test_indices << {:fail, i}
              failed += 1
              return {passed, failed} if @fail_fast
            end
          end
        rescue ex
          STDERR.puts "Error processing #{path}: #{ex.message}"
        end

        @file_results[filename] = file_result if file_result.test_indices.size > 0
      end

      {passed, failed}
    end

    # Initial state mapping for tokenizer
    INITIAL_STATES = {
      "Data state"          => :data,
      "PLAINTEXT state"     => :plaintext,
      "RCDATA state"        => :rcdata,
      "RAWTEXT state"       => :rawtext,
      "Script data state"   => :script_data,
      "CDATA section state" => :cdata_section,
    }

    # Run a single tokenizer test
    private def run_single_tokenizer_test(test : JSON::Any, path : String, index : Int32) : Bool
      input = test["input"].as_s
      expected = test["output"].as_a

      # Handle doubleEscaped
      if test["doubleEscaped"]?.try(&.as_bool?)
        input = unescape_unicode(input)
        expected = unescape_unicode_in_tokens(expected)
      end

      initial_states = test["initialStates"]?.try(&.as_a?) || [JSON::Any.new("Data state")]
      last_start_tag = test["lastStartTag"]?.try(&.as_s?)

      initial_states.all? do |state_name|
        state = INITIAL_STATES[state_name.as_s]?
        next false unless state

        tokens = tokenize(input, state, last_start_tag)
        actual = collapse_characters(tokens)

        if actual == expected.map { |t| token_to_json(t) }
          true
        else
          if @verbosity >= 1
            puts "\nTOKENIZER FAIL: #{File.basename(path)} test ##{index}"
            puts "Input: #{input.inspect}"
            puts "State: #{state_name}"
            puts "Expected: #{expected}"
            puts "Actual: #{actual}"
          end
          false
        end
      end
    end

    # Convert test token to comparable format
    private def token_to_json(token : JSON::Any) : JSON::Any
      token
    end

    # Tokenize input and return tokens as JSON-compatible format
    private def tokenize(input : String, state : Symbol, last_start_tag : String?) : Array(JSON::Any)
      tokens = [] of JSON::Any
      sink = HTML5LibTestData::TokenCollector.new(tokens)
      tokenizer = JustHTML::Tokenizer.new(sink)

      # Set initial state based on the symbol
      case state
      when :data
        tokenizer.set_state(JustHTML::Tokenizer::State::Data)
      when :plaintext
        tokenizer.set_state(JustHTML::Tokenizer::State::PLAINTEXT)
      when :rcdata
        tokenizer.set_state(JustHTML::Tokenizer::State::RCDATA)
      when :rawtext
        tokenizer.set_state(JustHTML::Tokenizer::State::RAWTEXT)
      when :script_data
        tokenizer.set_state(JustHTML::Tokenizer::State::ScriptData)
      when :cdata_section
        tokenizer.set_state(JustHTML::Tokenizer::State::CDATASection)
      end

      # Set last start tag name if provided
      if last_start_tag
        tokenizer.set_last_start_tag_name(last_start_tag)
      end

      tokenizer.run(input)
      tokens
    end

    # Collapse consecutive character tokens
    private def collapse_characters(tokens : Array(JSON::Any)) : Array(JSON::Any)
      result = [] of JSON::Any
      tokens.each do |token|
        arr = token.as_a?
        if arr && arr[0].as_s? == "Character"
          if !result.empty?
            last = result.last.as_a?
            if last && last[0].as_s? == "Character"
              # Merge with previous character token
              combined = last[1].as_s + arr[1].as_s
              result[-1] = JSON.parse(["Character", combined].to_json)
              next
            end
          end
        end
        result << token
      end
      result
    end

    # Unescape \uNNNN sequences (for JSON double-escaped content)
    private def unescape_unicode(text : String) : String
      text.gsub(/\\u([0-9A-Fa-f]{4})/) do |match|
        code = match[2, 4].to_i(16)
        safe_chr(code).to_s
      end
    end

    # Safely convert codepoint to character, handling surrogates
    private def safe_chr(code : Int32) : Char
      # Surrogate range (0xD800-0xDFFF) is invalid in UTF-8
      # Replace with replacement character
      if code >= 0xD800 && code <= 0xDFFF
        '\uFFFD'
      else
        code.chr
      end
    end

    private def unescape_unicode_in_tokens(tokens : Array(JSON::Any)) : Array(JSON::Any)
      tokens.map do |token|
        unescape_token(token)
      end
    end

    private def unescape_token(value : JSON::Any) : JSON::Any
      case value.raw
      when String
        JSON::Any.new(unescape_unicode(value.as_s))
      when Array
        JSON::Any.new(value.as_a.map { |v| unescape_token(v) })
      when Hash
        hash = {} of String => JSON::Any
        value.as_h.each { |k, v| hash[k] = unescape_token(v) }
        JSON::Any.new(hash)
      else
        value
      end
    end

    # Print summary
    def print_summary(total_passed : Int32, total_failed : Int32, skipped : Int32) : Nil
      total = total_passed + total_failed
      percentage = total > 0 ? (total_passed * 1000 / total) / 10.0 : 0.0
      result_str = total_failed > 0 ? "FAILED" : "PASSED"

      unless @quiet
        @file_results.keys.sort_by { |f| natural_sort_key(f) }.each do |filename|
          fr = @file_results[filename]
          runnable = fr.passed + fr.failed
          pct = runnable > 0 ? (fr.passed * 100 / runnable) : 0
          pattern = fr.test_indices.map { |s, _| s == :pass ? '.' : (s == :fail ? 'x' : 's') }.join
          line = "#{filename}: #{fr.passed}/#{runnable} (#{pct}%) [#{pattern}]"
          line += " (#{fr.skipped} skipped)" if fr.skipped > 0
          puts line
        end
        puts
      end

      summary = "#{result_str}: #{total_passed}/#{total} passed (#{percentage}%)"
      summary += ", #{skipped} skipped" if skipped > 0
      puts summary
    end
  end
end

# Main entry point
def main
  test_dir = "tests"
  verbosity = 0
  fail_fast = false
  quiet = false
  test_specs = [] of String

  OptionParser.parse do |parser|
    parser.banner = "Usage: crystal run run_tests.cr -- [options]"

    parser.on("-v", "--verbose", "Increase verbosity (show failures)") { verbosity += 1 }
    parser.on("-x", "--fail-fast", "Stop on first failure") { fail_fast = true }
    parser.on("-q", "--quiet", "Only show summary") { quiet = true }
    parser.on("--test-specs SPECS", "Run specific tests (file:indices, comma-separated)") { |s| test_specs << s }
    parser.on("-h", "--help", "Show help") do
      puts parser
      exit
    end
  end

  # Verify test directories exist
  html5lib_tests = File.join(test_dir, "html5lib-tests")
  tree_tests = File.join(html5lib_tests, "tree-construction")
  tok_tests = File.join(html5lib_tests, "tokenizer")

  unless File.exists?(html5lib_tests)
    STDERR.puts "ERROR: html5lib-tests submodule not found."
    STDERR.puts
    STDERR.puts "To set up, run:"
    STDERR.puts "  git submodule update --init"
    exit 1
  end

  missing = [] of String
  missing << tree_tests unless File.exists?(tree_tests)
  missing << tok_tests unless File.exists?(tok_tests)

  unless missing.empty?
    STDERR.puts "ERROR: html5lib-tests directories not found:"
    missing.each { |p| STDERR.puts "  #{p}" }
    STDERR.puts
    STDERR.puts "Try updating the submodule:"
    STDERR.puts "  git submodule update --init"
    exit 1
  end

  runner = HTML5LibTests::TestRunner.new(test_dir, verbosity, fail_fast, quiet, test_specs)

  tree_passed, tree_failed, skipped = runner.run_tree_tests
  tok_passed, tok_failed = runner.run_tokenizer_tests

  total_passed = tree_passed + tok_passed
  total_failed = tree_failed + tok_failed

  runner.print_summary(total_passed, total_failed, skipped)

  exit 1 if total_failed > 0
end

main
