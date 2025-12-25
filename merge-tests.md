# Plan: Integrate html5lib tests into crystal spec

## Current state

Two separate testing systems exist:

| System | Tests | Command | Purpose |
|--------|-------|---------|---------|
| Crystal spec | 166 examples | `crystal spec` | Unit tests for components |
| run_tests.cr | 8,580 tests | `./run_tests` | html5lib conformance suite |

### Problems with current approach

1. **Duplication**: `html5lib_runner_spec.cr` duplicates parsing logic from `run_tests.cr`
   (TreeConstructionTest, serialize_to_test_format, etc.) but is less complete

2. **Two commands needed**: Developers must run both `crystal spec` AND `./run_tests`
   to verify all tests pass

3. **Different output formats**: Crystal spec uses standard spec output while
   run_tests.cr has custom progress/summary display

4. **Separate maintenance**: Bug fixes in test parsing logic must be applied in
   multiple places

## Proposed approach

**Strategy: Dynamic spec generation using compile-time macros**

Extract shared test infrastructure into a module, then use Crystal's macro system
to read html5lib test files at compile time and generate spec blocks dynamically.

### Why this approach

- **Single command**: `crystal spec` runs everything
- **Native output**: Standard spec format with per-test granularity
- **CI-friendly**: Works with standard Crystal CI patterns
- **No duplication**: Shared parsing logic in one place
- **Maintains run_tests.cr**: Keep as optional standalone tool for quick iteration

### Alternative approaches considered

| Approach | Pros | Cons |
|----------|------|------|
| Runtime test loading | Simpler code | Crystal spec doesn't support runtime-generated `it` blocks |
| Shell out to run_tests | Quick to implement | Loses per-test granularity, double compilation |
| Convert tests to Crystal files | Native specs | Impractical with 8,580 tests, maintenance nightmare |

## TDD validation strategy

Each phase includes validation steps to ensure progress is correct before moving
forward. The principle: **write the test first, then make it pass**.

### Validation checkpoints

After each phase, run this validation sequence:

```bash
# 1. Existing tests must still pass
crystal spec spec/just_html_spec.cr spec/tokenizer_spec.cr spec/tree_builder_spec.cr

# 2. New infrastructure tests pass
crystal spec spec/support/

# 3. Full suite passes (once implemented)
crystal spec
```

## Implementation plan

### Phase 1: Extract shared test infrastructure (with TDD)

Create `spec/support/html5lib_test_data.cr` with shared types and parsing logic.

**TDD approach:**

1. First, create `spec/support/html5lib_test_data_spec.cr` with tests for:
   - Parsing a simple .dat file with one test case
   - Parsing a .dat file with multiple test cases
   - Parsing a .dat file with fragment context
   - Parsing a .test JSON file
   - Serializing a document to test format

2. Then implement the module to make tests pass.

**Tests to write first:**

```crystal
# spec/support/html5lib_test_data_spec.cr
require "../spec_helper"
require "./html5lib_test_data"

describe HTML5LibTestData do
  describe ".parse_tree_construction_tests" do
    it "parses simple test case" do
      content = <<-DAT
      #data
      <p>Hello
      #errors
      #document
      | <html>
      |   <head>
      |   <body>
      |     <p>
      |       "Hello"
      DAT

      tests = HTML5LibTestData.parse_tree_construction_tests(content)
      tests.size.should eq(1)
      tests[0].input.should eq("<p>Hello")
    end

    it "parses fragment context" do
      # ... test with #document-fragment section
    end
  end

  describe ".serialize_to_test_format" do
    it "serializes simple document" do
      doc = JustHTML.parse("<p>Hello")
      result = HTML5LibTestData.serialize_to_test_format(doc)
      result.should contain("| <html>")
      result.should contain("|   <body>")
    end
  end
end
```

**Tasks:**

1. [ ] Create `spec/support/` directory
2. [ ] Write test for parsing single .dat test case
3. [ ] Implement parser to make test pass
4. [ ] Write test for parsing multiple test cases
5. [ ] Extend parser to handle multiple cases
6. [ ] Write test for fragment context parsing
7. [ ] Implement fragment context handling
8. [ ] Write test for .test JSON parsing
9. [ ] Implement JSON parser
10. [ ] Write test for serialize_to_test_format
11. [ ] Extract serialization logic from run_tests.cr
12. [ ] Validate: all support tests pass

**Validation checkpoint:**

```bash
crystal spec spec/support/html5lib_test_data_spec.cr
```

### Phase 2: Create macro-based test generators (with TDD)

Create macros that read test files at compile time and generate spec blocks.

**TDD approach:**

1. Start with ONE test file (smallest .dat file) to validate the macro approach
2. Write a spec that uses the macro with that single file
3. Verify generated tests match expected count
4. Verify pass/fail matches run_tests.cr output for that file

**Tasks:**

1. [ ] Identify smallest .dat file for initial testing
2. [ ] Create `spec/support/html5lib_test_macros.cr` with basic macro
3. [ ] Create `spec/html5lib/tree_construction_spec.cr` with single file
4. [ ] Run spec and verify test count matches run_tests.cr for that file
5. [ ] Compare pass/fail results with run_tests.cr
6. [ ] Fix any discrepancies
7. [ ] Validate: single file tests match expected results

**Validation checkpoint:**

```bash
# Compare with run_tests.cr output for same file
./run_tests --test-specs "adoption01.dat" 2>&1 | tail -5
crystal spec spec/html5lib/tree_construction_spec.cr
```

### Phase 3: Expand to all test files (incremental)

**TDD approach:**

1. Add files one category at a time
2. After each addition, validate test count and results match

**Order of expansion:**

1. [ ] Add all tree-construction .dat files
2. [ ] Validate: tree-construction count matches run_tests.cr
3. [ ] Add tokenizer .test files (start with one)
4. [ ] Validate: tokenizer results match
5. [ ] Add all tokenizer files
6. [ ] Validate: full tokenizer count matches

**Validation checkpoint:**

```bash
# Tree construction count should match
./run_tests 2>&1 | grep "tree-construction"
crystal spec spec/html5lib/tree_construction_spec.cr --format summary

# Tokenizer count should match
./run_tests 2>&1 | grep "tokenizer"
crystal spec spec/html5lib/tokenizer_spec.cr --format summary
```

### Phase 4: Clean up and refactor

**Tasks:**

1. [ ] Remove duplicated code from `html5lib_runner_spec.cr`
2. [ ] Keep only sanity tests or remove entirely
3. [ ] Update run_tests.cr to use shared module (optional)
4. [ ] Add tags for category filtering
5. [ ] Validate: full spec suite runs clean

**Validation checkpoint:**

```bash
# Full suite
crystal spec

# Verify same failures as run_tests.cr
./run_tests -q 2>&1 | grep -E "^(PASS|FAIL)"
```

### Phase 5: Final validation

**Tasks:**

1. [ ] Run full test suite
2. [ ] Verify test count: 8,580 html5lib + 166 unit = 8,746+ examples
3. [ ] Document discrepancies (if any) with justification
4. [ ] Check compile time is acceptable
5. [ ] Update README

## Technical challenges

### 1. Compile-time macro limitations

Crystal macros can read files but have limited string parsing capability. May need to:

- Use simpler parsing logic in macros
- Pre-process test files into a more macro-friendly format
- Use `{{ run("./parse_tests") }}` to run a helper script

### 2. Large test count

8,580 tests may cause:

- Long compile times
- Large binary size
- Memory pressure during compilation

Mitigations:

- Split into multiple spec files by category
- Use `--tag` filtering for focused runs
- Consider lazy test loading if compile time becomes prohibitive

### 3. Error message quality

Ensure failure messages are useful:

```crystal
it "test #42: <div><p>Hello" do
  result = serialize_to_test_format(JustHTML.parse(input))
  result.should eq(expected), "Input: #{input.inspect}\nExpected:\n#{expected}\nGot:\n#{result}"
end
```

### 4. Skipped tests

Some tests are skipped (scripting-enabled tests). Need to:

- Mark as pending rather than skip entirely
- Document why they're skipped

## File structure after implementation

```
spec/
├── spec_helper.cr
├── support/
│   ├── html5lib_test_data.cr      # Shared types and parsing
│   ├── html5lib_test_data_spec.cr # Tests for the support module
│   └── html5lib_test_macros.cr    # Compile-time test generators
├── html5lib/
│   ├── tree_construction_spec.cr  # All tree-construction tests
│   └── tokenizer_spec.cr          # All tokenizer tests
├── just_html_spec.cr              # Keep as-is
├── tokenizer_spec.cr              # Keep as-is (unit tests)
├── tree_builder_spec.cr           # Keep as-is
└── ... other existing specs
```

## Success criteria

1. `crystal spec` runs all tests (unit + html5lib conformance)
2. Test count: 8,580 html5lib tests + 166 unit tests = 8,746+ examples
3. Same tests pass/fail as current run_tests.cr
4. Compile time under 30 seconds (ideally under 15)
5. Clear failure messages showing input, expected, and actual output

## Commit strategy

Commit after each validated phase:

1. Phase 1 complete: "Add html5lib test data parsing infrastructure"
2. Phase 2 complete: "Add macro-based test generation for tree-construction"
3. Phase 3 complete: "Expand html5lib spec coverage to all test files"
4. Phase 4 complete: "Clean up duplicated test code"
5. Phase 5 complete: "Finalize html5lib spec integration"

## Rollback plan

If compile-time macro approach proves too complex or slow:

1. Keep run_tests.cr as primary html5lib test runner
2. Create a simple wrapper spec that invokes run_tests and parses output
3. Focus on removing duplication between run_tests.cr and html5lib_runner_spec.cr

## Open questions

1. Should run_tests.cr be kept as a standalone tool or deprecated?
   - Recommendation: Keep for quick iteration, document as optional

2. How to handle new html5lib test files added to submodule?
   - Option A: Manually add macro invocations
   - Option B: Use glob macro to auto-discover files

3. Should tags be per-file or per-category?
   - Recommendation: Both - category tags (tree-construction, tokenizer) and
     file-based filtering via spec path
