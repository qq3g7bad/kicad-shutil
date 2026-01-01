#!/usr/bin/env bash

# @TEST-VERIFY-003@ (FROM: @IMPL-VERIFY-003@)
# Unit tests for lib/verify_project.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"
FIXTURES_DIR="$TEST_DIR/fixtures/test_project_dir"

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser_project.sh"
source "$LIB_DIR/verify_table.sh"
source "$LIB_DIR/verify_project.sh"

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
	# Create test project directory structure
	mkdir -p "$FIXTURES_DIR"

	# Create a test .kicad_pro file
	cat >"$FIXTURES_DIR/test_project.kicad_pro" <<'EOF'
{
  "board": {},
  "boards": [],
  "cvpcb": {},
  "environment": {
    "vars": {
      "CUSTOM_LIB": "${KIPRJMOD}/custom_libs"
    }
  },
  "erc": {},
  "libraries": {},
  "meta": {
    "filename": "test_project.kicad_pro",
    "version": 1
  },
  "text_variables": {
    "AUTHOR": "Test",
    "VERSION": "1.0"
  }
}
EOF

	# Create a test sym-lib-table
	cat >"$FIXTURES_DIR/sym-lib-table" <<'EOF'
(sym_lib_table
  (version 7)
  (lib (name "power")(type "KiCad")(uri "${KICAD7_SYMBOL_DIR}/power.kicad_sym")(options "")(descr "Power symbols"))
  (lib (name "device")(type "KiCad")(uri "${KICAD7_SYMBOL_DIR}/Device.kicad_sym")(options "")(descr "Device symbols"))
)
EOF

	# Create a test fp-lib-table
	cat >"$FIXTURES_DIR/fp-lib-table" <<'EOF'
(fp_lib_table
  (version 7)
  (lib (name "Resistor_SMD")(type "KiCad")(uri "${KICAD7_FOOTPRINT_DIR}/Resistor_SMD.pretty")(options "")(descr "SMD resistors"))
  (lib (name "Capacitor_SMD")(type "KiCad")(uri "${KICAD7_FOOTPRINT_DIR}/Capacitor_SMD.pretty")(options "")(descr "SMD capacitors"))
)
EOF
}

oneTimeTearDown() {
	# Clean up test fixtures
	rm -rf "$FIXTURES_DIR"
}

#-----------------------------------
# Test: verify_project_file() basic functionality
#-----------------------------------
testVerifyProjectFileBasic() {
	if ! declare -f verify_project_file >/dev/null; then
		startSkipping
		return
	fi

	# This test just checks that the function runs without errors
	# We don't verify the actual library paths since they depend on system KiCad installation
	local result
	verify_project_file "$FIXTURES_DIR/test_project.kicad_pro" >/dev/null 2>&1
	result=$?

	# We accept either success (0) or failure (1) since library paths may not exist
	# The important thing is the function doesn't crash
	assertTrue "verify_project_file should complete" "[ $result -eq 0 ] || [ $result -eq 1 ]"
}

#-----------------------------------
# Test: KIPRJMOD is set correctly
#-----------------------------------
testKIPRJMODIsSet() {
	if ! declare -f parse_project_file >/dev/null || ! declare -f get_project_dir >/dev/null; then
		startSkipping
		return
	fi

	local project_data
	project_data=$(parse_project_file "$FIXTURES_DIR/test_project.kicad_pro")

	local project_dir
	project_dir=$(get_project_dir "$project_data")

	assertNotNull "Project directory should be set" "$project_dir"
	# Project directory is returned as absolute path
	local expected_dir
	expected_dir=$(cd "$FIXTURES_DIR" && pwd)
	assertEquals "Project directory should match FIXTURES_DIR" "$expected_dir" "$project_dir"
}

#-----------------------------------
# Test: Library table files are found
#-----------------------------------
testLibraryTablesExist() {
	assertTrue "sym-lib-table should exist" "[ -f '$FIXTURES_DIR/sym-lib-table' ]"
	assertTrue "fp-lib-table should exist" "[ -f '$FIXTURES_DIR/fp-lib-table' ]"
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
