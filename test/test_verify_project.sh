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
	# Create deterministic local fixture structure.
	mkdir -p "$FIXTURES_DIR/libs/sym"
	mkdir -p "$FIXTURES_DIR/libs/fp/Test.pretty"

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

	cat >"$FIXTURES_DIR/test_project.kicad_sch" <<'EOF'
(kicad_sch (version 20230121) (generator eeschema)
	(uuid 00000000-0000-0000-0000-000000000000)
	(paper "A4")

	(symbol (lib_id "device:Resistor") (at 10 10 0)
		(property "Reference" "R1" (at 0 0 0) (effects (font (size 1.27 1.27))))
		(property "Value" "10k" (at 0 -2.54 0) (effects (font (size 1.27 1.27))))
		(property "Footprint" "Test:Existing" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
	)

	(symbol (lib_id "device:Resistor") (at 20 10 0)
		(property "Reference" "R2" (at 0 0 0) (effects (font (size 1.27 1.27))))
		(property "Value" "22k" (at 0 -2.54 0) (effects (font (size 1.27 1.27))))
		(property "Footprint" "Test:Missing" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
	)

	(symbol (lib_id "device:Resistor") (at 30 10 0)
		(property "Reference" "R3" (at 0 0 0) (effects (font (size 1.27 1.27))))
		(property "Value" "33k" (at 0 -2.54 0) (effects (font (size 1.27 1.27))))
		(property "Footprint" "UnknownLib:Any" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
	)

	(symbol (lib_id "device:Resistor") (at 40 10 0)
		(property "Reference" "R4" (at 0 0 0) (effects (font (size 1.27 1.27))))
		(property "Value" "47k" (at 0 -2.54 0) (effects (font (size 1.27 1.27))))
		(property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
	)

	(symbol (lib_id "power:GND") (at 50 10 0)
		(property "Reference" "#PWR01" (at 0 0 0) (effects (font (size 1.27 1.27))))
		(property "Value" "GND" (at 0 -2.54 0) (effects (font (size 1.27 1.27))))
	)

	(sheet_instances
		(path "/" (page "1"))
	)
)
EOF

	cat >"$FIXTURES_DIR/libs/sym/device.kicad_sym" <<'EOF'
(kicad_symbol_lib (version 20220914) (generator kicad_symbol_editor)
	(symbol "Resistor" (pin_names (offset 0.508)) (in_bom yes) (on_board yes)
		(property "Reference" "R" (at 0 0 0)
			(effects (font (size 1.27 1.27)))
		)
		(property "Value" "Resistor" (at 0 -2.54 0)
			(effects (font (size 1.27 1.27)))
		)
		(property "Footprint" "Test:Existing" (at 0 0 0)
			(effects (font (size 1.27 1.27)) hide)
		)
		(property "Datasheet" "" (at 0 0 0)
			(effects (font (size 1.27 1.27)) hide)
		)
	)
)
EOF

	cat >"$FIXTURES_DIR/libs/fp/Test.pretty/Existing.kicad_mod" <<'EOF'
(footprint "Existing" (version 20240108) (generator kicad)
	(layer "F.Cu")
)
EOF

	# Create a test sym-lib-table
	cat >"$FIXTURES_DIR/sym-lib-table" <<'EOF'
(sym_lib_table
  (version 7)
	(lib (name "device")(type "KiCad")(uri "${KIPRJMOD}/libs/sym/device.kicad_sym")(options "")(descr "Device symbols"))
)
EOF

	# Create a test fp-lib-table
	cat >"$FIXTURES_DIR/fp-lib-table" <<'EOF'
(fp_lib_table
  (version 7)
	(lib (name "Test")(type "KiCad")(uri "${KIPRJMOD}/libs/fp/Test.pretty")(options "")(descr "Test footprints"))
)
EOF
}

oneTimeTearDown() {
	# Clean up test fixtures
	rm -rf "$FIXTURES_DIR"
}

#-----------------------------------
# Test: verify_project_file() fails on schematic-instance footprint errors
#-----------------------------------
testVerifyProjectFileFailsOnSchematicErrors() {
	if ! declare -f verify_project_file >/dev/null; then
		startSkipping
		return
	fi

	local output
	output=$(verify_project_file "$FIXTURES_DIR/test_project.kicad_pro" 2>&1)
	local result=$?

	assertEquals "verify_project_file should fail on schematic footprint errors" 1 "$result"
	assertContains "Missing footprint target should be reported" "$output" "SCHEMATIC_FOOTPRINT_NOT_FOUND"
	assertContains "Unavailable footprint library should be reported" "$output" "FOOTPRINT_LIBRARY_UNAVAILABLE"
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

#-----------------------------------
# Test: verify_schematic_instances() stats
#-----------------------------------
testVerifySchematicInstancesStats() {
	if ! declare -f verify_schematic_instances >/dev/null; then
		startSkipping
		return
	fi

	# verify_schematic_instances expects KIPRJMOD for path resolution.
	export KIPRJMOD="$FIXTURES_DIR"

	local stats
	stats=$(verify_schematic_instances "$FIXTURES_DIR/test_project.kicad_pro" "$FIXTURES_DIR" "$FIXTURES_DIR/fp-lib-table" 2>/dev/null)

	local sch_files
	sch_files=$(echo "$stats" | awk -F'|' '$1 == "SCH_FILES" { print $2 }')
	local instances
	instances=$(echo "$stats" | awk -F'|' '$1 == "INSTANCES" { print $2 }')
	local missing_fp
	missing_fp=$(echo "$stats" | awk -F'|' '$1 == "MISSING_FP" { print $2 }')
	local fp_not_found
	fp_not_found=$(echo "$stats" | awk -F'|' '$1 == "FP_NOT_FOUND" { print $2 }')
	local lib_unavailable
	lib_unavailable=$(echo "$stats" | awk -F'|' '$1 == "LIB_UNAVAILABLE" { print $2 }')

	assertEquals "One schematic file should be scanned" "1" "$sch_files"
	assertEquals "Only non-power symbols should be counted" "4" "$instances"
	assertEquals "One symbol should miss footprint field" "1" "$missing_fp"
	assertEquals "One symbol should point to missing footprint" "1" "$fp_not_found"
	assertEquals "One symbol should reference unavailable library" "1" "$lib_unavailable"
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
