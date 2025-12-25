require "../spec_helper"
require "../support/html5lib_test_macros"

describe "HTML5lib tree construction tests" do
  # Start with a single small file to validate the approach
  generate_tree_construction_tests("tests/html5lib-tests/tree-construction/search-element.dat")
end
