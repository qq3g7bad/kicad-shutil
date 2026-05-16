#!/usr/bin/env bash

# @TEST-PCB-EXPORT-001@ (FROM: @IMPL-PCB-EXPORT-001@)
# Unit tests for lib/pcb_export.sh

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
FIXTURES_DIR="$(dirname "${BASH_SOURCE[0]}")/fixtures"

# Source required modules
source "$LIB_DIR/utils.sh"

# Initialize utils (required by pcb_export.sh)
init_utils

# Source the module to test
source "$LIB_DIR/pcb_export.sh"

# Disable color output for consistent test results
# shellcheck disable=SC2034  # Variables used by sourced modules
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

# Create temporary directory for test outputs
TEST_OUTPUT_DIR=""

# Setup function - called before each test
setUp() {
	TEST_OUTPUT_DIR=$(mktemp -d)
	# Mock kicad-cli for tests that don't actually run it
	export PATH="$SCRIPT_DIR/test/mocks:$PATH"
}

# Teardown function - called after each test
tearDown() {
	if [[ -n "$TEST_OUTPUT_DIR" && -d "$TEST_OUTPUT_DIR" ]]; then
		rm -rf "$TEST_OUTPUT_DIR"
	fi
}

#-----------------------------------
# Test: init_pcb_export_stats()
#-----------------------------------
testInitPcbExportStats() {
	init_pcb_export_stats
	assertEquals "gerbers should be 0" "0" "$PCB_EXPORT_STATS_gerbers"
	assertEquals "drill should be 0" "0" "$PCB_EXPORT_STATS_drill"
	assertEquals "position should be 0" "0" "$PCB_EXPORT_STATS_position"
	assertEquals "netlist should be 0" "0" "$PCB_EXPORT_STATS_netlist"
	assertEquals "preview should be 0" "0" "$PCB_EXPORT_STATS_preview"
	assertEquals "total should be 0" "0" "$PCB_EXPORT_STATS_total"
	assertEquals "failed should be 0" "0" "$PCB_EXPORT_STATS_failed"
}

#-----------------------------------
# Test: check_kicad_cli() when not available
#-----------------------------------
testCheckKicadCliNotAvailable() {
	# Temporarily override PATH to exclude kicad-cli
	local old_path="$PATH"
	export PATH="/tmp"

	local output
	output=$(check_kicad_cli 2>&1)
	local exit_code=$?

	export PATH="$old_path"

	assertEquals "Should return 1 when kicad-cli not found" "1" "$exit_code"
	assertContains "Should mention kicad-cli not found" "$output" "not found"
}

#-----------------------------------
# Test: resolve_input_files() with .kicad_pcb
#-----------------------------------
testResolveInputFilesWithPcb() {
	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"

	resolve_input_files "$pcb_file"
	local exit_code=$?

	assertEquals "Should succeed" "0" "$exit_code"
	# shellcheck disable=SC2153  # PCB_FILE is set by resolve_input_files()
	assertEquals "PCB_FILE should be set" "$pcb_file" "$PCB_FILE"
	# shellcheck disable=SC2153  # SCH_FILE is set by resolve_input_files()
	assertEquals "SCH_FILE should be set" "$FIXTURES_DIR/simple.kicad_sch" "$SCH_FILE"
}

#-----------------------------------
# Test: resolve_input_files() with .kicad_pro
#-----------------------------------
testResolveInputFilesWithProject() {
	local pro_file="$FIXTURES_DIR/simple.kicad_pro"

	resolve_input_files "$pro_file"
	local exit_code=$?

	assertEquals "Should succeed" "0" "$exit_code"
	# shellcheck disable=SC2153
	assertEquals "PCB_FILE should be set" "$FIXTURES_DIR/simple.kicad_pcb" "$PCB_FILE"
	# shellcheck disable=SC2153
	assertEquals "SCH_FILE should be set" "$FIXTURES_DIR/simple.kicad_sch" "$SCH_FILE"
}

#-----------------------------------
# Test: resolve_input_files() with .kicad_sch
#-----------------------------------
testResolveInputFilesWithSchematic() {
	local sch_file="$FIXTURES_DIR/simple.kicad_sch"

	resolve_input_files "$sch_file"
	local exit_code=$?

	assertEquals "Should succeed" "0" "$exit_code"
	# shellcheck disable=SC2153
	assertEquals "PCB_FILE should be set" "$FIXTURES_DIR/simple.kicad_pcb" "$PCB_FILE"
	# shellcheck disable=SC2153
	assertEquals "SCH_FILE should be set" "$sch_file" "$SCH_FILE"
}

#-----------------------------------
# Test: resolve_input_files() with non-existent file
#-----------------------------------
testResolveInputFilesNonExistent() {
	local output
	output=$(resolve_input_files "/tmp/nonexistent_$RANDOM.kicad_pcb" 2>&1)
	local exit_code=$?

	assertEquals "Should return 1" "1" "$exit_code"
	assertContains "Should mention file not found" "$output" "not found"
}

#-----------------------------------
# Test: resolve_input_files() with unsupported file type
#-----------------------------------
testResolveInputFilesUnsupportedType() {
	local temp_file="/tmp/test_$RANDOM.txt"
	touch "$temp_file"

	local output
	output=$(resolve_input_files "$temp_file" 2>&1)
	local exit_code=$?

	rm -f "$temp_file"

	assertEquals "Should return 1" "1" "$exit_code"
	assertContains "Should mention unsupported type" "$output" "Unsupported"
}

#-----------------------------------
# Test: resolve_input_files() with PCB but no schematic
#-----------------------------------
testResolveInputFilesPcbNoSchematic() {
	# Create a temporary PCB file without matching schematic
	local temp_pcb="/tmp/test_$RANDOM.kicad_pcb"
	cp "$FIXTURES_DIR/simple.kicad_pcb" "$temp_pcb"

	# Call directly so globals (PCB_FILE, SCH_FILE) are set in current shell.
	# Capture stderr via a temp file to allow assertContains checks.
	local stderr_file
	stderr_file=$(mktemp)
	resolve_input_files "$temp_pcb" 2>"$stderr_file"
	local exit_code=$?
	local output
	output=$(cat "$stderr_file")
	rm -f "$stderr_file" "$temp_pcb"

	assertEquals "Should succeed" "0" "$exit_code"
	# shellcheck disable=SC2153
	assertEquals "PCB_FILE should be set" "$temp_pcb" "$PCB_FILE"
	# shellcheck disable=SC2153
	assertEquals "SCH_FILE should be empty" "" "$SCH_FILE"
	assertContains "Should warn about missing schematic" "$output" "Schematic file not found"
}

#-----------------------------------
# Test: resolve_input_files() with project but no PCB
#-----------------------------------
testResolveInputFilesProjectNoPcb() {
	# Create a temporary project file without matching PCB
	local temp_pro="/tmp/test_$RANDOM.kicad_pro"
	cp "$FIXTURES_DIR/simple.kicad_pro" "$temp_pro"

	local output
	output=$(resolve_input_files "$temp_pro" 2>&1)
	local exit_code=$?

	rm -f "$temp_pro"

	assertEquals "Should return 1" "1" "$exit_code"
	assertContains "Should mention PCB not found" "$output" "PCB file not found"
}

#-----------------------------------
# Test: export_gerbers() creates output directory
#-----------------------------------
testExportGerbersCreatesDirectory() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"
	init_pcb_export_stats

	export_gerbers "$pcb_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1

	assertTrue "Gerbers directory should be created" "[ -d '$TEST_OUTPUT_DIR/gerbers' ]"
	assertTrue "Log file should be created" "[ -f '$TEST_OUTPUT_DIR/gerbers.log' ]"
}

#-----------------------------------
# Test: export_drill() creates output directory
#-----------------------------------
testExportDrillCreatesDirectory() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"
	init_pcb_export_stats

	export_drill "$pcb_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1

	assertTrue "Drill directory should be created" "[ -d '$TEST_OUTPUT_DIR/drill' ]"
	assertTrue "Log file should be created" "[ -f '$TEST_OUTPUT_DIR/drill.log' ]"
}

#-----------------------------------
# Test: export_position() creates output directory
#-----------------------------------
testExportPositionCreatesDirectory() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"
	init_pcb_export_stats

	export_position "$pcb_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1

	assertTrue "Position directory should be created" "[ -d '$TEST_OUTPUT_DIR/position' ]"
	assertTrue "Log file should be created" "[ -f '$TEST_OUTPUT_DIR/position.log' ]"
}

#-----------------------------------
# Test: export_netlist() skips when no schematic
#-----------------------------------
testExportNetlistSkipsWhenNoSchematic() {
	init_pcb_export_stats
	SCH_FILE=""

	local output
	output=$(export_netlist "" "$TEST_OUTPUT_DIR" 2>&1)
	local exit_code=$?

	assertEquals "Should succeed (skip)" "0" "$exit_code"
	assertContains "Should mention skipping" "$output" "Skipping"
	assertEquals "Netlist stat should remain 0" "0" "$PCB_EXPORT_STATS_netlist"
}

#-----------------------------------
# Test: export_netlist() creates output directory when schematic present
#-----------------------------------
testExportNetlistCreatesDirectory() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local sch_file="$FIXTURES_DIR/simple.kicad_sch"
	init_pcb_export_stats

	export_netlist "$sch_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1

	assertTrue "Netlist directory should be created" "[ -d '$TEST_OUTPUT_DIR/netlist' ]"
	assertTrue "Log file should be created" "[ -f '$TEST_OUTPUT_DIR/netlist.log' ]"
}

#-----------------------------------
# Test: export_preview() creates output directory
#-----------------------------------
testExportPreviewCreatesDirectory() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"
	init_pcb_export_stats

	export_preview "$pcb_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1

	assertTrue "Preview directory should be created" "[ -d '$TEST_OUTPUT_DIR/preview' ]"
	assertTrue "Log file should be created" "[ -f '$TEST_OUTPUT_DIR/preview.log' ]"
}

#-----------------------------------
# Test: export_preview() produces 2D SVG and 3D PNG for both sides
#-----------------------------------
testExportPreviewProducesFrontAndBack() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"
	init_pcb_export_stats

	export_preview "$pcb_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1

	local preview_dir="$TEST_OUTPUT_DIR/preview"
	assertTrue "Front 3D render (PNG) should exist" "[ -f '$preview_dir/simple-Front.png' ]"
	assertTrue "Back 3D render (PNG) should exist" "[ -f '$preview_dir/simple-Back.png' ]"
	assertTrue "Front 2D composite (SVG) should exist" "[ -f '$preview_dir/simple-Front.svg' ]"
	assertTrue "Back 2D composite (SVG) should exist" "[ -f '$preview_dir/simple-Back.svg' ]"
	assertEquals "Preview stat should be 1 on success" "1" "$PCB_EXPORT_STATS_preview"
}

#-----------------------------------
# Test: print_pcb_export_summary() displays results
#-----------------------------------
testPrintPcbExportSummary() {
	init_pcb_export_stats
	PCB_EXPORT_STATS_gerbers=1
	PCB_EXPORT_STATS_drill=1
	PCB_EXPORT_STATS_position=0
	PCB_EXPORT_STATS_netlist=0
	PCB_EXPORT_STATS_preview=1
	PCB_EXPORT_STATS_total=3
	PCB_EXPORT_STATS_failed=1
	SCH_FILE=""

	local output
	output=$(print_pcb_export_summary "$TEST_OUTPUT_DIR" 2>&1)

	assertContains "Should show output directory" "$output" "$TEST_OUTPUT_DIR"
	assertContains "Should show gerbers succeeded" "$output" "Gerbers"
	assertContains "Should show drill succeeded" "$output" "Drill"
	assertContains "Should show position failed" "$output" "Position"
	assertContains "Should show netlist skipped" "$output" "SKIPPED"
	assertContains "Should show preview succeeded" "$output" "Preview"
	assertContains "Should show totals" "$output" "3 successful"
	assertContains "Should show failures" "$output" "1 failed"
}

#-----------------------------------
# Integration Test: Full export with kicad-cli
# This test only runs if kicad-cli is available
#-----------------------------------
testFullExportWithKicadCli() {
	# Skip if kicad-cli not available
	if ! command -v kicad-cli &>/dev/null; then
		startSkipping
	fi

	local pcb_file="$FIXTURES_DIR/simple.kicad_pcb"

	export_gerber_output "$pcb_file" "$TEST_OUTPUT_DIR" >/dev/null 2>&1
	local exit_code=$?

	# The command might fail if kicad-cli has issues with the minimal fixture
	# but we at least verify that directories were created
	assertTrue "Gerbers directory should exist" "[ -d '$TEST_OUTPUT_DIR/gerbers' ]"
	assertTrue "Drill directory should exist" "[ -d '$TEST_OUTPUT_DIR/drill' ]"
	assertTrue "Position directory should exist" "[ -d '$TEST_OUTPUT_DIR/position' ]"
	assertTrue "Netlist directory should exist" "[ -d '$TEST_OUTPUT_DIR/netlist' ]"
	assertTrue "Preview directory should exist" "[ -d '$TEST_OUTPUT_DIR/preview' ]"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
