#!/usr/bin/env bash

# Integration test for DigiKey API functionality
# This test requires valid DigiKey API credentials

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/digikey.sh" 2>/dev/null || true

# Disable color output (exported for sourced scripts)
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
	# Check if DigiKey credentials are available
	if [[ -z "$DIGIKEY_CLIENT_ID" ]] || [[ -z "$DIGIKEY_CLIENT_SECRET" ]]; then
		echo "SKIP: DigiKey credentials not configured"
		echo "Set DIGIKEY_CLIENT_ID and DIGIKEY_CLIENT_SECRET to run integration tests"
		startSkipping
	fi

	# Check if DigiKey functions are available
	if ! declare -f digikey_search >/dev/null; then
		echo "SKIP: DigiKey module not available"
		startSkipping
	fi
}

#-----------------------------------
# Test: DigiKey token acquisition
#-----------------------------------
testDigiKeyToken() {
	if ! declare -f digikey_get_token >/dev/null; then
		startSkipping
		return
	fi

	local token
	token=$(digikey_get_token)

	assertNotNull "Token should not be null" "$token"
	assertTrue "Token should be non-empty" "[ -n '$token' ]"
}

#-----------------------------------
# Test: DigiKey search for known part
#-----------------------------------
testDigiKeySearch() {
	if ! declare -f digikey_search >/dev/null; then
		startSkipping
		return
	fi

	# Search for a common part
	local results
	results=$(digikey_search "LM358")

	assertNotNull "Search results should not be null" "$results"
	assertContains "Should find LM358 related parts" "$results" "LM358"
}

#-----------------------------------
# Note: Add more integration tests as needed
# These tests require network access and valid credentials
#-----------------------------------

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$TEST_DIR/shunit2/shunit2"
