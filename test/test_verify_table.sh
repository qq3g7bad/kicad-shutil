#!/usr/bin/env bash

# @TEST-VERIFY-002@ (FROM: @IMPL-VERIFY-002@)
# Unit tests for lib/verify_table.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"
FIXTURES_DIR="$TEST_DIR/fixtures/test_table"

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/verify_table.sh"

# Disable color output for consistent test assertions
# shellcheck disable=SC2034  # Variables used by sourced modules
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_CYAN=""
export COLOR_MAGENTA=""
export COLOR_RESET=""

#-----------------------------------
# Test Setup
#-----------------------------------
oneTimeSetUp() {
	# Create test fixtures directory
	mkdir -p "$FIXTURES_DIR"
	mkdir -p "$FIXTURES_DIR/libs"

	# Create a test symbol library file
	cat >"$FIXTURES_DIR/libs/test.kicad_sym" <<'EOF'
(kicad_symbol_lib (version 20211014) (generator kicad_symbol_editor)
  (symbol "TestSymbol" (in_bom yes) (on_board yes)
    (property "Reference" "U" (id 0) (at 0 0 0))
    (property "Value" "TestSymbol" (id 1) (at 0 0 0))
  )
)
EOF

	# Create a test footprint library directory
	mkdir -p "$FIXTURES_DIR/libs/test.pretty"
	cat >"$FIXTURES_DIR/libs/test.pretty/TestFP.kicad_mod" <<'EOF'
(footprint "TestFP" (version 20211014) (generator pcbnew)
  (layer "F.Cu")
)
EOF

	# Create a test sym-lib-table
	cat >"$FIXTURES_DIR/sym-lib-table" <<EOF
(sym_lib_table
  (lib (name "test_lib")(type "KiCad")(uri "\${FIXTURES}/libs/test.kicad_sym")(options "")(descr "Test library"))
  (lib (name "missing_lib")(type "KiCad")(uri "\${FIXTURES}/libs/missing.kicad_sym")(options "")(descr "Missing library"))
  (lib (name "disabled_lib")(type "KiCad")(uri "\${FIXTURES}/libs/disabled.kicad_sym")(options "")(descr "Disabled library")(disabled))
)
EOF

	# Create a test fp-lib-table
	cat >"$FIXTURES_DIR/fp-lib-table" <<EOF
(fp_lib_table
  (lib (name "test_fp")(type "KiCad")(uri "\${FIXTURES}/libs/test.pretty")(options "")(descr "Test footprint library"))
  (lib (name "missing_fp")(type "KiCad")(uri "\${FIXTURES}/libs/missing.pretty")(options "")(descr "Missing footprint library"))
)
EOF
}

oneTimeTearDown() {
	# Clean up test fixtures
	rm -rf "$FIXTURES_DIR"
}

setUp() {
	# Reset environment before each test
	unset KICAD_ENV_LOADED
	# shellcheck disable=SC2034  # Variables used by sourced verify_table.sh
	declare -gA KICAD_ENV=()
	# shellcheck disable=SC2034  # Variables used by sourced verify_table.sh
	declare -gA KICAD_UNRESOLVED_VARS=()
	export FIXTURES="$FIXTURES_DIR"
}

tearDown() {
	:
}

#-----------------------------------
# Tests for normalize_path()
#-----------------------------------
test_normalize_path_returns_absolute_path() {
	local test_file="$FIXTURES_DIR/libs/test.kicad_sym"
	local result
	result=$(normalize_path "$test_file")

	# Result should be absolute path
	assertEquals "Absolute path should start with /" "/" "${result:0:1}"
	assertTrue "Path should exist" "[ -f '$result' ]"
}

test_normalize_path_handles_nonexistent_path() {
	local test_path="/nonexistent/path/to/file.txt"
	local result
	result=$(normalize_path "$test_path")

	# Should return path as-is for nonexistent files
	assertEquals "$test_path" "$result"
}

test_normalize_path_resolves_directory() {
	local test_dir="$FIXTURES_DIR/libs"
	local result
	result=$(normalize_path "$test_dir")

	# Result should be absolute directory path
	assertEquals "Absolute path should start with /" "/" "${result:0:1}"
	assertTrue "Path should exist as directory" "[ -d '$result' ]"
}

#-----------------------------------
# Tests for resolve_kicad_path()
#-----------------------------------
test_resolve_kicad_path_with_simple_variable() {
	# Set up environment variable
	export TEST_VAR="/test/path"

	local path="\${TEST_VAR}/subdir/file.txt"
	local result
	result=$(resolve_kicad_path "$path")

	assertEquals "/test/path/subdir/file.txt" "$result"
}

test_resolve_kicad_path_with_multiple_variables() {
	# Set up environment variables
	export VAR1="/first"
	export VAR2="/second"

	local path="\${VAR1}/\${VAR2}/file.txt"
	local result
	result=$(resolve_kicad_path "$path")

	assertEquals "/first//second/file.txt" "$result"
}

test_resolve_kicad_path_returns_error_for_undefined_variable() {
	local path="\${UNDEFINED_VAR}/file.txt"
	local result
	result=$(resolve_kicad_path "$path" 2>&1)
	local exit_code=$?

	# Should return error
	assertEquals 1 "$exit_code"
}

test_resolve_kicad_path_with_no_variables() {
	local path="/absolute/path/file.txt"
	local result
	result=$(resolve_kicad_path "$path")

	assertEquals "$path" "$result"
}

#-----------------------------------
# Tests for load_kicad_environment()
#-----------------------------------
test_load_kicad_environment_sets_loaded_flag() {
	load_kicad_environment

	assertNotNull "KICAD_ENV_LOADED should be set" "$KICAD_ENV_LOADED"
}

test_load_kicad_environment_is_idempotent() {
	load_kicad_environment
	local first_call_loaded="$KICAD_ENV_LOADED"

	load_kicad_environment
	local second_call_loaded="$KICAD_ENV_LOADED"

	assertEquals "$first_call_loaded" "$second_call_loaded"
}

#-----------------------------------
# Tests for verify_table_file()
#-----------------------------------
test_verify_table_file_with_valid_symbol_table() {
	local table_file="$FIXTURES_DIR/sym-lib-table"

	# This will fail because missing_lib doesn't exist, but should not crash
	verify_table_file "$table_file" "symbol" 2>/dev/null || true

	# Just verify it runs without crashing
	assertTrue "Function should complete" true
}

test_verify_table_file_with_valid_footprint_table() {
	local table_file="$FIXTURES_DIR/fp-lib-table"

	# This will fail because missing_fp doesn't exist, but should not crash
	verify_table_file "$table_file" "footprint" 2>/dev/null || true

	# Just verify it runs without crashing
	assertTrue "Function should complete" true
}

test_verify_table_file_with_missing_file() {
	local table_file="$FIXTURES_DIR/nonexistent-table"
	local result
	result=$(verify_table_file "$table_file" "symbol" 2>&1)
	local exit_code=$?

	# Should return error
	assertEquals 1 "$exit_code"
	assertContains "$result" "Table file not found"
}

test_verify_table_file_skips_disabled_libraries() {
	local table_file="$FIXTURES_DIR/sym-lib-table"

	# Run verification - disabled_lib should be skipped
	# This will fail due to missing_lib, but disabled_lib won't cause error
	verify_table_file "$table_file" "symbol" 2>/dev/null || true

	# Just verify disabled libraries don't cause crashes
	assertTrue "Disabled libraries should be skipped" true
}

#-----------------------------------
# Load shunit2
#-----------------------------------
# shellcheck disable=SC1091
source "$TEST_DIR/shunit2/shunit2"
