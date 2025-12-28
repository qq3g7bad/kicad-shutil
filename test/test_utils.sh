#!/usr/bin/env bash

# Unit tests for lib/utils.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source the module to test
source "$LIB_DIR/utils.sh"

# Disable color output for consistent test results
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_RESET=""

#-----------------------------------
# Test: info() function
#-----------------------------------
testInfoMessage() {
	local output
	output=$(info "test message" 2>&1)
	assertContains "$output" "[INFO]"
	assertContains "$output" "test message"
}

#-----------------------------------
# Test: warn() function
#-----------------------------------
testWarnMessage() {
	local output
	output=$(warn "warning message" 2>&1)
	assertContains "$output" "[WARN]"
	assertContains "$output" "warning message"
}

#-----------------------------------
# Test: error() function
#-----------------------------------
testErrorMessage() {
	local output
	output=$(error "error message" 2>&1)
	assertContains "$output" "[ERROR]"
	assertContains "$output" "error message"
}

#-----------------------------------
# Test: success() function
#-----------------------------------
testSuccessMessage() {
	local output
	output=$(success "success message" 2>&1)
	assertContains "$output" "[OK]"
	assertContains "$output" "success message"
}

#-----------------------------------
# Test: get_timestamp() returns a number
#-----------------------------------
testGetTimestamp() {
	local ts
	ts=$(get_timestamp)
	assertNotNull "Timestamp should not be null" "$ts"
	# Check if it's a number (Unix timestamp)
	[[ "$ts" =~ ^[0-9]+$ ]]
	assertTrue "Timestamp should be numeric" $?
}

#-----------------------------------
# Test: get_file_mtime() with non-existent file
#-----------------------------------
testGetFileMtimeNonExistent() {
	local mtime
	mtime=$(get_file_mtime "/tmp/nonexistent_file_$RANDOM")
	assertEquals "Should return 0 for non-existent file" "0" "$mtime"
}

#-----------------------------------
# Test: get_file_mtime() with existing file
#-----------------------------------
testGetFileMtimeExisting() {
	local test_file="/tmp/kicad_putil_test_$$"
	echo "test" >"$test_file"

	local mtime
	mtime=$(get_file_mtime "$test_file")
	assertNotNull "mtime should not be null" "$mtime"
	[[ "$mtime" =~ ^[0-9]+$ ]]
	assertTrue "mtime should be numeric" $?
	assertNotEquals "mtime should not be 0" "0" "$mtime"

	rm -f "$test_file"
}

#-----------------------------------
# Test: is_cache_valid() with non-existent cache
#-----------------------------------
testIsCacheValidNonExistent() {
	is_cache_valid "/tmp/nonexistent_cache_$RANDOM" 900
	assertEquals "Should return 1 (false) for non-existent cache" 1 $?
}

#-----------------------------------
# Test: is_cache_valid() with fresh cache
#-----------------------------------
testIsCacheValidFresh() {
	local cache_file="/tmp/kicad_putil_cache_$$"
	echo "cached data" >"$cache_file"

	is_cache_valid "$cache_file" 900
	assertEquals "Fresh cache should be valid" 0 $?

	rm -f "$cache_file"
}

#-----------------------------------
# Test: is_cache_valid() with expired cache
#-----------------------------------
testIsCacheValidExpired() {
	local cache_file="/tmp/kicad_putil_cache_$$"
	echo "old cached data" >"$cache_file"

	# Modify file timestamp to be very old (if touch supports -t)
	if touch -t 202001010000 "$cache_file" 2>/dev/null; then
		is_cache_valid "$cache_file" 900
		assertEquals "Old cache should be invalid" 1 $?
	else
		# Skip test if touch -t not supported
		startSkipping
	fi

	rm -f "$cache_file"
}

#-----------------------------------
# Test: sanitize_filename() if it exists
#-----------------------------------
testSanitizeFilename() {
	if declare -f sanitize_filename >/dev/null; then
		local result
		result=$(sanitize_filename "test/file:name*.txt")
		assertNotContains "Should remove invalid chars" "$result" "/"
		assertNotContains "Should remove invalid chars" "$result" ":"
		assertNotContains "Should remove invalid chars" "$result" "*"
	else
		startSkipping
	fi
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
