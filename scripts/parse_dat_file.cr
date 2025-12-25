#!/usr/bin/env crystal

# Helper script for compile-time parsing of .dat files
# Output format: test_num\n===\ninput\n===\nexpected\n===\nfragment\n===\nscript\n---TEST---

require "../spec/support/html5lib_test_data"

file_path = ARGV[0]
content = File.read(file_path)
tests = HTML5LibTestData.parse_tree_construction_tests(content)

tests.each_with_index do |test, index|
  puts index
  puts "==="
  puts test.data
  puts "==="
  puts test.document
  puts "==="
  puts test.document_fragment || ""
  puts "==="
  puts test.script_directive || ""
  puts "---TEST---"
end
