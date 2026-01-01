#!/usr/bin/env bash

# @TEST-VERIFY-001@ (FROM: @IMPL-VERIFY-001@)
# Unit tests for lib/verify.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser.sh"
source "$LIB_DIR/verify.sh"

# Disable color output for consistent test results
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

# Mock spinner functions to avoid background processes in tests
start_spinner() { :; }
stop_spinner() { :; }

# Mock http_check_url to avoid real HTTP requests
http_check_url() {
	local url="$1"
	case "$url" in
		*valid.com*)
			echo "200"
			;;
		*broken.com*)
			echo "404"
			;;
		*timeout.com*)
			echo "000"
			;;
		*)
			echo "200"
			;;
	esac
}

#-----------------------------------
# Setup and Teardown
#-----------------------------------
oneTimeSetUp() {
	# Create test fixture directory
	TEST_FIXTURE_DIR="$TEST_DIR/fixtures"
	mkdir -p "$TEST_FIXTURE_DIR"

	# Create test symbol file with various test cases
	TEST_SYMBOL_FILE="$TEST_FIXTURE_DIR/test_verify.kicad_sym"
	cat >"$TEST_SYMBOL_FILE" <<'EOF'
(kicad_symbol_lib (version 20220914) (generator kicad_symbol_editor)
  (symbol "ValidSymbol" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "ValidSymbol" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "https://valid.com/datasheet.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "DigiKey" "296-1234-ND" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
  (symbol "MissingFootprint" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "MissingFootprint" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "https://valid.com/datasheet.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
  (symbol "MissingDatasheet" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "MissingDatasheet" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
  (symbol "BrokenDatasheet" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "BrokenDatasheet" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "https://broken.com/404.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
  (symbol "MissingVendors" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "MissingVendors" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "https://valid.com/datasheet.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
)
EOF
}

oneTimeTearDown() {
	# Clean up test files
	rm -f "$TEST_SYMBOL_FILE"
}

setUp() {
	# Initialize verify stats before each test
	init_verify_stats
}

#-----------------------------------
# Test: init_verify_stats()
#-----------------------------------
testInitVerifyStats() {
	init_verify_stats

	assertEquals "0" "${VERIFY_STATS[total_symbols]}"
	assertEquals "0" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "0" "${VERIFY_STATS[issue_symbols]}"
	assertEquals "0" "${VERIFY_STATS[missing_footprint]}"
	assertEquals "0" "${VERIFY_STATS[missing_datasheet]}"
	assertEquals "0" "${VERIFY_STATS[broken_datasheet]}"
	assertEquals "0" "${VERIFY_STATS[missing_digikey]}"
}

#-----------------------------------
# Test: verify_symbol() with valid symbol
#-----------------------------------
testVerifySymbolValid() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "ValidSymbol"

	assertEquals "1" "${VERIFY_STATS[total_symbols]}"
	assertEquals "1" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "0" "${VERIFY_STATS[issue_symbols]}"
}

#-----------------------------------
# Test: verify_symbol() with missing footprint
#-----------------------------------
testVerifySymbolMissingFootprint() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "MissingFootprint"

	assertEquals "1" "${VERIFY_STATS[total_symbols]}"
	assertEquals "0" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "1" "${VERIFY_STATS[issue_symbols]}"
	assertEquals "1" "${VERIFY_STATS[missing_footprint]}"
}

#-----------------------------------
# Test: verify_symbol() with missing datasheet
#-----------------------------------
testVerifySymbolMissingDatasheet() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "MissingDatasheet"

	assertEquals "1" "${VERIFY_STATS[total_symbols]}"
	assertEquals "0" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "1" "${VERIFY_STATS[issue_symbols]}"
	assertEquals "1" "${VERIFY_STATS[missing_datasheet]}"
}

#-----------------------------------
# Test: verify_symbol() with broken datasheet URL
#-----------------------------------
testVerifySymbolBrokenDatasheet() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "BrokenDatasheet"

	assertEquals "1" "${VERIFY_STATS[total_symbols]}"
	assertEquals "0" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "1" "${VERIFY_STATS[issue_symbols]}"
	assertEquals "1" "${VERIFY_STATS[broken_datasheet]}"
}

#-----------------------------------
# Test: verify_symbol() with missing vendors
#-----------------------------------
testVerifySymbolMissingVendors() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "MissingVendors"

	assertEquals "1" "${VERIFY_STATS[total_symbols]}"
	assertEquals "1" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "0" "${VERIFY_STATS[issue_symbols]}"
	assertEquals "1" "${VERIFY_STATS[missing_digikey]}"
}

#-----------------------------------
# Test: verify_file() with multiple symbols
#-----------------------------------
testVerifyFile() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	verify_file "$TEST_SYMBOL_FILE" "$symbols_data" 2>/dev/null

	assertEquals "5" "${VERIFY_STATS[total_symbols]}"
	assertEquals "2" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "3" "${VERIFY_STATS[issue_symbols]}"
}

#-----------------------------------
# Test: Statistics accumulation across multiple symbols
#-----------------------------------
testStatisticsAccumulation() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")

	# Verify multiple symbols
	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "ValidSymbol"
	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "MissingFootprint"
	verify_symbol "$TEST_SYMBOL_FILE" "$symbols_data" "MissingDatasheet"

	assertEquals "3" "${VERIFY_STATS[total_symbols]}"
	assertEquals "1" "${VERIFY_STATS[ok_symbols]}"
	assertEquals "2" "${VERIFY_STATS[issue_symbols]}"
	assertEquals "1" "${VERIFY_STATS[missing_footprint]}"
	assertEquals "1" "${VERIFY_STATS[missing_datasheet]}"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
