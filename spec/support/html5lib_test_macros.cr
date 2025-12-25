require "./html5lib_test_data"

# Macro to generate tree construction tests from .dat files at compile time
macro generate_tree_construction_tests(file_path)
  {% content = read_file(file_path.id.stringify) %}
  {% file_name = file_path.id.stringify.split("/").last %}

  describe {{file_name}} do
    # Parse tests at compile time
    {% tests_data = run("../../scripts/parse_dat_file.cr", file_path.id.stringify).split("\n---TEST---\n") %}

    {% for test_data in tests_data %}
      {% if test_data.strip != "" %}
        {% parts = test_data.split("\n===\n") %}
        {% test_num = parts[0] %}
        {% test_input = parts[1] %}
        {% test_expected = parts[2] %}
        {% test_fragment = parts[3] %}
        {% test_script = parts[4] %}

        it "test #" + {{test_num}} do
          input = {{test_input}}
          expected = {{test_expected}}
          fragment_context = {{test_fragment}}
          script_directive = {{test_script}}

          # Skip scripting tests
          if script_directive == "script-on"
            pending "scripting-enabled test (not supported)"
            next
          end

          # Skip fragment tests for now
          if fragment_context != ""
            pending "fragment parsing not yet supported"
            next
          end

          # Parse and serialize
          doc = JustHTML.parse(input)
          actual = HTML5LibTestData.serialize_to_test_format(doc)

          # Compare
          actual.should eq(expected)
        end
      {% end %}
    {% end %}
  end
end
