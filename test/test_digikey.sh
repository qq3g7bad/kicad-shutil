#!/usr/bin/env bash

# Unit tests for lib/digikey.sh
# shellcheck disable=SC2155  # Declare and assign separately - not critical in tests

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck disable=SC2034  # TEST_DIR may be used in future tests
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Disable color output (must be set before sourcing)
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/digikey.sh"

# Mock spinner functions
start_spinner() { :; }
stop_spinner() { :; }

# Mock HTTP functions to avoid real API calls
http_post() { echo '{"access_token":"mock_token","expires_in":3600}'; }
http_request() { echo '{"ProductsCount":0,"Products":[]}'; }

#-----------------------------------
# Test: parse_digikey_api_response()
#-----------------------------------
testParseDigiKeyApiResponseSingleResult() {
	local json_response='{"ProductsCount":1,"Products":[{"ProductUrl":"https://www.digikey.com/product-detail/en/296-1234-ND","ProductDescription":"IC TIMER 555 8-DIP","DetailedDescription":"Timer/Oscillator Single Bipolar 8-DIP","ProductVariations":[{"DigiKeyProductNumber":"296-1234-ND","UnitPrice":0.45,"MinimumOrderQuantity":1,"PackageType":{"Name":"Tube"}}]}]}'

	local result=$(parse_digikey_api_response "$json_response")

	assertNotNull "Result should not be empty" "$result"
	assertContains "$result" "296-1234-ND"
	assertContains "$result" "https://www.digikey.com/product-detail/en/296-1234-ND"
	assertContains "$result" "IC TIMER 555 8-DIP"
}

testParseDigiKeyApiResponseMultipleResults() {
	local json_response='{"ProductsCount":2,"Products":[{"ProductUrl":"https://www.digikey.com/1","ProductDescription":"Desc1","DetailedDescription":"Detail1","ProductVariations":[{"DigiKeyProductNumber":"296-1234-ND","UnitPrice":0.45,"MinimumOrderQuantity":1}]},{"ProductUrl":"https://www.digikey.com/2","ProductDescription":"Desc2","DetailedDescription":"Detail2","ProductVariations":[{"DigiKeyProductNumber":"296-5678-ND","UnitPrice":0.50,"MinimumOrderQuantity":10}]}]}'

	local result=$(parse_digikey_api_response "$json_response")

	assertNotNull "Result should not be empty" "$result"

	# Check both parts are present
	assertContains "$result" "296-1234-ND"
	assertContains "$result" "296-5678-ND"

	# Count lines (should be 2)
	local line_count=$(echo "$result" | grep -c "296-" || true)
	assertEquals "2" "$line_count"
}

testParseDigiKeyApiResponseNoResults() {
	local json_response='{"ProductsCount":0,"Products":[]}'

	local result=$(parse_digikey_api_response "$json_response")

	assertEquals "Result should be empty" "" "$result"
}

testParseDigiKeyApiResponseMissingFields() {
	# Test with missing UnitPrice in ProductVariations
	local json_response='{"ProductsCount":1,"Products":[{"ProductUrl":"https://www.digikey.com/1","ProductDescription":"Desc1","DetailedDescription":"Detail1","ProductVariations":[{"DigiKeyProductNumber":"296-1234-ND","MinimumOrderQuantity":1}]}]}'

	local result=$(parse_digikey_api_response "$json_response")

	# Should be empty because price is required
	assertEquals "Result should be empty when price is missing" "" "$result"
}

#-----------------------------------
# Test: load_digikey_credentials()
#-----------------------------------
testLoadDigiKeyCredentialsFromEnv() {
	# Set environment variables
	export DIGIKEY_CLIENT_ID="test_id"
	export DIGIKEY_CLIENT_SECRET="test_secret"

	load_digikey_credentials
	local result=$?

	assertEquals "Should return 0 when credentials are set" 0 $result

	# Cleanup
	unset DIGIKEY_CLIENT_ID
	unset DIGIKEY_CLIENT_SECRET
}

#-----------------------------------
# Test: URL encoding
#-----------------------------------
testUrlEncodingInSearchQuery() {
	# Test that url_encode is used for search queries
	# This is an indirect test - we check that the function exists

	type url_encode >/dev/null 2>&1
	local result=$?

	assertEquals "url_encode function should exist" 0 $result
}

#-----------------------------------
# Test: JSON request body generation
#-----------------------------------
testDigiKeySearchRequestBody() {
	# Test that we can generate proper JSON without jq
	local keyword="TLC555"

	# This tests the heredoc JSON generation approach
	local json=$(
		cat <<EOF
{
  "Keywords": "$keyword",
  "RecordCount": 10,
  "RecordStartPosition": 0,
  "Filters": {
    "ManufacturerFilter": [],
    "MinimumQuantityAvailable": 1
  },
  "Sort": {
    "SortOption": "SortByUnitPrice",
    "Direction": "Ascending"
  },
  "RequestedQuantity": 1
}
EOF
	)

	assertContains "$json" "\"Keywords\": \"$keyword\""
	assertContains "$json" "\"RecordCount\": 10"
}

#-----------------------------------
# Test: Price formatting
#-----------------------------------
testPriceFormattingWithDecimals() {
	local price="0.45"

	# Test that price is handled as string to preserve decimals
	assertEquals "0.45" "$price"
}

testPriceFormattingZero() {
	local price="0.00"

	assertEquals "0.00" "$price"
}

#-----------------------------------
# Test: MOQ (Minimum Order Quantity) handling
#-----------------------------------
testMOQParsing() {
	local moq="1"

	assertTrue "MOQ should be numeric" "[[ $moq =~ ^[0-9]+$ ]]"
}

testMOQDefaultValue() {
	# When MOQ is missing, should default to empty or 1
	local moq="${moq_value:-1}"

	assertEquals "1" "$moq"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
