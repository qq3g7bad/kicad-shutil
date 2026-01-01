#!/usr/bin/env bash

# @TEST-DATASHEET-001@ (FROM: @IMPL-DATASHEET-001@)
# Unit tests for lib/datasheet.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck disable=SC2034  # Used in test functions
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser.sh"
source "$LIB_DIR/datasheet.sh"

# Ensure get_file_extension_from_url is available
if ! type get_file_extension_from_url >/dev/null 2>&1; then
	get_file_extension_from_url() {
		local url="$1"
		local basename
		basename=$(basename "${url%%\?*}")
		local ext="${basename##*.}"
		if [[ "$basename" == "$ext" ]] || [[ -z "$ext" ]]; then
			echo ""
		else
			echo "$ext"
		fi
	}
fi

# Disable color output for consistent test results
# shellcheck disable=SC2034  # Variables used by sourced modules
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

# Mock spinner functions
start_spinner() { :; }
stop_spinner() { :; }

# Export DATASHEET_DIR for use in test functions
# shellcheck disable=SC2034  # Set in each test function
export DATASHEET_DIR=""

# Mock download_file to avoid real downloads
download_file() {
	local url="$1"
	local output="$2"

	# Create directory
	mkdir -p "$(dirname "$output")"

	# Simulate download based on URL
	case "$url" in
		*success.pdf)
			echo "mock pdf content" >"$output"
			return 0
			;;
		*fail.pdf)
			return 1
			;;
		*)
			echo "mock content" >"$output"
			return 0
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

	# Create temporary output directory
	TEST_OUTPUT_DIR="$TEST_FIXTURE_DIR/test_datasheets"
	mkdir -p "$TEST_OUTPUT_DIR"

	# Create test symbol file
	TEST_SYMBOL_FILE="$TEST_FIXTURE_DIR/test_datasheet.kicad_sym"
	cat >"$TEST_SYMBOL_FILE" <<'EOF'
(kicad_symbol_lib (version 20220914) (generator kicad_symbol_editor)
  (symbol "WithHTTPDatasheet" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "WithHTTPDatasheet" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "https://example.com/success.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
  (symbol "WithLocalDatasheet" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "WithLocalDatasheet" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "~/local/datasheet.pdf" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
  (symbol "NoDatasheet" (pin_numbers hide) (pin_names (offset 0.254)) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Value" "NoDatasheet" (at 0 0 0)
      (effects (font (size 1.27 1.27))))
    (property "Footprint" "Package_DIP:DIP-8_W7.62mm" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
    (property "Datasheet" "" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide))
  )
)
EOF
}

oneTimeTearDown() {
	# Clean up test files
	rm -rf "$TEST_OUTPUT_DIR"
	rm -f "$TEST_SYMBOL_FILE"
}

setUp() {
	# Initialize stats before each test
	init_datasheet_stats

	# Clean output directory
	rm -rf "${TEST_OUTPUT_DIR:?}"/*
}

#-----------------------------------
# Test: init_datasheet_stats()
#-----------------------------------
testInitDatasheetStats() {
	init_datasheet_stats

	assertEquals "0" "${DATASHEET_STATS[total]}"
	assertEquals "0" "${DATASHEET_STATS[success]}"
	assertEquals "0" "${DATASHEET_STATS[failed]}"
	assertEquals "0" "${DATASHEET_STATS[missing]}"
	assertEquals "0" "${DATASHEET_STATS[skipped]}"
}

#-----------------------------------
# Test: get_file_extension_from_url()
#-----------------------------------
testGetFileExtensionFromUrlPDF() {
	local url="https://example.com/datasheet.pdf"
	local result
	result=$(get_file_extension_from_url "$url")

	assertEquals "pdf" "$result"
}

testGetFileExtensionFromUrlWithQuery() {
	local url="https://example.com/datasheet.pdf?download=true"
	local result
	result=$(get_file_extension_from_url "$url")

	assertEquals "pdf" "$result"
}

testGetFileExtensionFromUrlNoExtension() {
	local url="https://example.com/datasheet"
	local result
	result=$(get_file_extension_from_url "$url")

	# Should return empty string
	assertEquals "" "$result"
}

testGetFileExtensionFromUrlDOC() {
	local url="https://example.com/datasheet.doc"
	local result
	result=$(get_file_extension_from_url "$url")

	assertEquals "doc" "$result"
}

#-----------------------------------
# Test: download_symbol_datasheet() with HTTP URL
#-----------------------------------
testDownloadSymbolDatasheetHTTP() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")
	DATASHEET_DIR="$TEST_OUTPUT_DIR"

	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "WithHTTPDatasheet" "$TEST_OUTPUT_DIR/test" 2>/dev/null

	assertEquals "1" "${DATASHEET_STATS[total]}"
	assertEquals "1" "${DATASHEET_STATS[success]}"
	assertTrue "Downloaded file should exist" "[[ -f $TEST_OUTPUT_DIR/test/WithHTTPDatasheet.pdf ]]"
}

#-----------------------------------
# Test: download_symbol_datasheet() with local path
#-----------------------------------
testDownloadSymbolDatasheetLocal() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")
	DATASHEET_DIR="$TEST_OUTPUT_DIR"

	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "WithLocalDatasheet" "$TEST_OUTPUT_DIR/test" 2>/dev/null

	assertEquals "1" "${DATASHEET_STATS[total]}"
	assertEquals "1" "${DATASHEET_STATS[skipped]}"
	assertFalse "Should not download local file" "[[ -f $TEST_OUTPUT_DIR/test/WithLocalDatasheet.pdf ]]"
}

#-----------------------------------
# Test: download_symbol_datasheet() with no datasheet
#-----------------------------------
testDownloadSymbolDatasheetMissing() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")
	DATASHEET_DIR="$TEST_OUTPUT_DIR"

	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "NoDatasheet" "$TEST_OUTPUT_DIR/test" 2>/dev/null

	assertEquals "1" "${DATASHEET_STATS[total]}"
	assertEquals "1" "${DATASHEET_STATS[missing]}"
}

#-----------------------------------
# Test: download_symbol_datasheet() skip existing file
#-----------------------------------
testDownloadSymbolDatasheetSkipExisting() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")
	DATASHEET_DIR="$TEST_OUTPUT_DIR"

	# Create output directory and file
	mkdir -p "$TEST_OUTPUT_DIR/test"
	echo "existing content" >"$TEST_OUTPUT_DIR/test/WithHTTPDatasheet.pdf"

	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "WithHTTPDatasheet" "$TEST_OUTPUT_DIR/test" 2>/dev/null

	assertEquals "1" "${DATASHEET_STATS[total]}"
	assertEquals "1" "${DATASHEET_STATS[skipped]}"

	# Content should not change
	local content
	content=$(cat "$TEST_OUTPUT_DIR/test/WithHTTPDatasheet.pdf")
	assertEquals "existing content" "$content"
}

#-----------------------------------
# Test: download_datasheets() for all symbols
#-----------------------------------
testDownloadDatasheetsAll() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")
	DATASHEET_DIR="$TEST_OUTPUT_DIR"

	download_datasheets "$TEST_SYMBOL_FILE" "$symbols_data" "test_category" 2>/dev/null

	assertEquals "3" "${DATASHEET_STATS[total]}"
	assertEquals "1" "${DATASHEET_STATS[success]}"
	assertEquals "1" "${DATASHEET_STATS[skipped]}"
	assertEquals "1" "${DATASHEET_STATS[missing]}"
}

#-----------------------------------
# Test: print_datasheet_summary()
#-----------------------------------
testPrintDatasheetSummary() {
	DATASHEET_STATS[total]=10
	DATASHEET_STATS[success]=7
	DATASHEET_STATS[failed]=1
	DATASHEET_STATS[missing]=1
	DATASHEET_STATS[skipped]=1

	local output
	output=$(print_datasheet_summary 2>&1)

	assertContains "$output" "10"
	assertContains "$output" "7"
}

#-----------------------------------
# Test: Statistics accumulation
#-----------------------------------
testStatisticsAccumulation() {
	local symbols_data
	symbols_data=$(parse_file "$TEST_SYMBOL_FILE")
	DATASHEET_DIR="$TEST_OUTPUT_DIR"

	# Download multiple times
	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "WithHTTPDatasheet" "$TEST_OUTPUT_DIR/test1" 2>/dev/null
	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "NoDatasheet" "$TEST_OUTPUT_DIR/test2" 2>/dev/null
	download_symbol_datasheet "$TEST_SYMBOL_FILE" "$symbols_data" "WithLocalDatasheet" "$TEST_OUTPUT_DIR/test3" 2>/dev/null

	assertEquals "3" "${DATASHEET_STATS[total]}"
	assertEquals "1" "${DATASHEET_STATS[success]}"
	assertEquals "1" "${DATASHEET_STATS[missing]}"
	assertEquals "1" "${DATASHEET_STATS[skipped]}"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
