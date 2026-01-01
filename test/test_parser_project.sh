#!/usr/bin/env bash

# @TEST-PARSER-002@ (FROM: @IMPL-PARSER-002@)
# Unit tests for lib/parser_project.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"
FIXTURES_DIR="$TEST_DIR/fixtures"

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser_project.sh"

# Disable color output
# shellcheck disable=SC2034  # Variables used by sourced modules
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

#-----------------------------------
# Test Setup
#-----------------------------------
oneTimeSetUp() {
	# Create test fixture directory if needed
	mkdir -p "$FIXTURES_DIR"

	# Create a test .kicad_pro file
	cat >"$FIXTURES_DIR/test_project.kicad_pro" <<'EOF'
{
  "board": {
    "3dviewports": [],
    "design_settings": {},
    "layer_presets": [],
    "viewports": []
  },
  "boards": [],
  "cvpcb": {
    "equivalence_files": []
  },
  "erc": {},
  "libraries": {},
  "meta": {
    "filename": "test_project.kicad_pro",
    "version": 1
  },
  "net_settings": {},
  "pcbnew": {},
  "schematic": {},
  "sheets": [],
  "text_variables": {
    "AUTHOR": "Test Author",
    "REVISION": "v1.0",
    "COMPANY": "Test Company"
  }
}
EOF

	# Create a test .kicad_pro file with environment variables
	cat >"$FIXTURES_DIR/test_project_env.kicad_pro" <<'EOF'
{
  "board": {},
  "boards": [],
  "cvpcb": {},
  "environment": {
    "vars": {
      "CUSTOM_LIB_PATH": "/home/user/custom_libs",
      "PROJECT_LIBS": "${KIPRJMOD}/libs"
    }
  },
  "erc": {},
  "libraries": {},
  "meta": {
    "filename": "test_project_env.kicad_pro",
    "version": 1
  },
  "text_variables": {
    "VERSION": "2.0"
  }
}
EOF
}

oneTimeTearDown() {
	# Clean up test fixtures
	rm -f "$FIXTURES_DIR/test_project.kicad_pro"
	rm -f "$FIXTURES_DIR/test_project_env.kicad_pro"
}

#-----------------------------------
# Test: parse_project_file() function
#-----------------------------------
testParseProjectFile() {
	if ! declare -f parse_project_file >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project.kicad_pro")

	assertNotNull "Project data should not be null" "$project_data"
	assertContains "Should contain PROJECT_DIR" "$project_data" "PROJECT_DIR|"
}

#-----------------------------------
# Test: get_project_dir() function
#-----------------------------------
testGetProjectDir() {
	if ! declare -f parse_project_file >/dev/null || ! declare -f get_project_dir >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project.kicad_pro")

	local project_dir
	project_dir=$(get_project_dir "$project_data")

	assertNotNull "Project directory should not be null" "$project_dir"
	# Project directory is returned as absolute path, so convert FIXTURES_DIR to absolute path too
	local expected_dir
	expected_dir=$(cd "$FIXTURES_DIR" && pwd)
	assertEquals "Project directory should be FIXTURES_DIR" "$expected_dir" "$project_dir"
}

#-----------------------------------
# Test: get_text_var() function
#-----------------------------------
testGetTextVar() {
	if ! declare -f parse_project_file >/dev/null || ! declare -f get_text_var >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project.kicad_pro")

	local author
	author=$(get_text_var "$project_data" "AUTHOR")

	assertEquals "AUTHOR should be 'Test Author'" "Test Author" "$author"

	local revision
	revision=$(get_text_var "$project_data" "REVISION")

	assertEquals "REVISION should be 'v1.0'" "v1.0" "$revision"
}

#-----------------------------------
# Test: list_text_vars() function
#-----------------------------------
testListTextVars() {
	if ! declare -f parse_project_file >/dev/null || ! declare -f list_text_vars >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project.kicad_pro")

	local text_vars
	text_vars=$(list_text_vars "$project_data")

	assertContains "Should contain AUTHOR" "$text_vars" "AUTHOR"
	assertContains "Should contain REVISION" "$text_vars" "REVISION"
	assertContains "Should contain COMPANY" "$text_vars" "COMPANY"
}

#-----------------------------------
# Test: get_env_var() function
#-----------------------------------
testGetEnvVar() {
	if ! declare -f parse_project_file >/dev/null || ! declare -f get_env_var >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project_env.kicad_pro")

	local custom_lib
	custom_lib=$(get_env_var "$project_data" "CUSTOM_LIB_PATH")

	assertEquals "CUSTOM_LIB_PATH should be '/home/user/custom_libs'" "/home/user/custom_libs" "$custom_lib"
}

#-----------------------------------
# Test: list_env_vars() function
#-----------------------------------
testListEnvVars() {
	if ! declare -f parse_project_file >/dev/null || ! declare -f list_env_vars >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project_env.kicad_pro")

	local env_vars
	env_vars=$(list_env_vars "$project_data")

	assertContains "Should contain CUSTOM_LIB_PATH" "$env_vars" "CUSTOM_LIB_PATH"
	assertContains "Should contain PROJECT_LIBS" "$env_vars" "PROJECT_LIBS"
}

# Load and run shunit2
SHUNIT2="$TEST_DIR/shunit2/shunit2"
if [[ -f "$SHUNIT2" ]]; then
	# shellcheck source=test/shunit2/shunit2
	source "$SHUNIT2"
else
	echo "ERROR: shunit2 not found at $SHUNIT2"
	echo "Please run: git submodule update --init --recursive"
	exit 1
fi
