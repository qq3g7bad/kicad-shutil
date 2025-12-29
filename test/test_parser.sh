#!/usr/bin/env bash

# Unit tests for lib/parser.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"
FIXTURES_DIR="$TEST_DIR/fixtures"

# Disable color output (must be set before sourcing)
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

# Source required modules
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser.sh"

#-----------------------------------
# Test Setup
#-----------------------------------
oneTimeSetUp() {
	# Create test fixture directory if needed
	mkdir -p "$FIXTURES_DIR"

	# Create a minimal test .kicad_sym file
	cat >"$FIXTURES_DIR/test_minimal.kicad_sym" <<'EOF'
(kicad_symbol_lib (version 20220914) (generator kicad_symbol_editor)
  (symbol "TestSymbol1" (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27)))
    )
    (property "Value" "TestSymbol1" (at 0 -2.54 0)
      (effects (font (size 1.27 1.27)))
    )
    (property "Footprint" "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide)
    )
    (property "Datasheet" "https://example.com/datasheet.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide)
    )
  )
  (symbol "TestSymbol2" (in_bom yes) (on_board yes)
    (property "Reference" "R" (at 0 0 0)
      (effects (font (size 1.27 1.27)))
    )
    (property "Value" "TestSymbol2" (at 0 -2.54 0)
      (effects (font (size 1.27 1.27)))
    )
    (property "Footprint" "" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide)
    )
    (property "Datasheet" "" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide)
    )
  )
)
EOF
}

oneTimeTearDown() {
	# Clean up test fixtures
	rm -f "$FIXTURES_DIR/test_minimal.kicad_sym"
}

#-----------------------------------
# Test: parse_file() and list_symbols() function
#-----------------------------------
testListSymbols() {
	if ! declare -f parse_file >/dev/null || ! declare -f list_symbols >/dev/null; then
		startSkipping
		return
	fi

	local parsed_data
	parsed_data=$(parse_file "$FIXTURES_DIR/test_minimal.kicad_sym")

	local symbols
	symbols=$(list_symbols "$parsed_data")

	assertContains "Should find TestSymbol1" "$symbols" "TestSymbol1"
	assertContains "Should find TestSymbol2" "$symbols" "TestSymbol2"
}

#-----------------------------------
# Test: get_property() function
#-----------------------------------
testGetPropertyFootprint() {
	if ! declare -f parse_file >/dev/null || ! declare -f get_property >/dev/null; then
		startSkipping
		return
	fi

	local parsed_data
	parsed_data=$(parse_file "$FIXTURES_DIR/test_minimal.kicad_sym")

	local footprint
	footprint=$(get_property "$parsed_data" "TestSymbol1" "Footprint")

	assertEquals "Should extract footprint" "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm" "$footprint"
}

testGetPropertyDatasheet() {
	if ! declare -f parse_file >/dev/null || ! declare -f get_property >/dev/null; then
		startSkipping
		return
	fi

	local parsed_data
	parsed_data=$(parse_file "$FIXTURES_DIR/test_minimal.kicad_sym")

	local datasheet
	datasheet=$(get_property "$parsed_data" "TestSymbol1" "Datasheet")

	assertEquals "Should extract datasheet URL" "https://example.com/datasheet.pdf" "$datasheet"
}

testGetPropertyEmpty() {
	if ! declare -f parse_file >/dev/null || ! declare -f get_property >/dev/null; then
		startSkipping
		return
	fi

	local parsed_data
	parsed_data=$(parse_file "$FIXTURES_DIR/test_minimal.kicad_sym")

	local footprint
	footprint=$(get_property "$parsed_data" "TestSymbol2" "Footprint")

	assertEquals "Should return empty for missing footprint" "" "$footprint"
}

#-----------------------------------
# Test: count_symbols() function
#-----------------------------------
testCountSymbols() {
	if ! declare -f parse_file >/dev/null || ! declare -f count_symbols >/dev/null; then
		startSkipping
		return
	fi

	local parsed_data
	parsed_data=$(parse_file "$FIXTURES_DIR/test_minimal.kicad_sym")

	local count
	count=$(count_symbols "$parsed_data")

	assertEquals "Should count 2 symbols" "2" "$count"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
