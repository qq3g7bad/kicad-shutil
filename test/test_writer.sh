#!/usr/bin/env bash

# Unit tests for lib/writer.sh

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

# Source dependencies
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser.sh"
source "$LIB_DIR/writer.sh"

#-----------------------------------
# Test Setup
#-----------------------------------
oneTimeSetUp() {
	mkdir -p "$FIXTURES_DIR"
}

oneTimeTearDown() {
	# Clean up any test files
	rm -f "$FIXTURES_DIR"/test_write_*.kicad_sym
	rm -f "$FIXTURES_DIR"/test_write_*.bak
}

#-----------------------------------
# Test: create_backup() function
#-----------------------------------
testCreateBackup() {
	if ! declare -f create_backup >/dev/null; then
		startSkipping
		return
	fi

	local test_file="$FIXTURES_DIR/test_write_backup.kicad_sym"
	echo "original content" >"$test_file"

	create_backup "$test_file"

	assertTrue "Backup file should exist" "[ -f ${test_file}.bak ]"

	local backup_content
	backup_content=$(cat "${test_file}.bak")
	assertEquals "Backup should have same content" "original content" "$backup_content"

	rm -f "$test_file" "${test_file}.bak"
}

#-----------------------------------
# Test: set_property() function
#-----------------------------------
testSetProperty() {
	if ! declare -f set_property >/dev/null; then
		startSkipping
		return
	fi

	# Create a test symbol file
	local test_file="$FIXTURES_DIR/test_write_setprop.kicad_sym"
	cat >"$test_file" <<'EOF'
(kicad_symbol_lib (version 20220914) (generator kicad_symbol_editor)
  (symbol "TestChip" (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27)))
    )
    (property "Value" "TestChip" (at 0 -2.54 0)
      (effects (font (size 1.27 1.27)))
    )
    (property "Footprint" "" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide)
    )
    (property "ki_keywords" "test chip" (at 0 0 0)
      (effects (font (size 1.27 1.27)) hide)
    )
  )
)
EOF

	# Test setting a property
	set_property "$test_file" "TestChip" "Digi-Key_PN" "TEST123-ND"

	# Verify the property was added
	local result
	result=$(grep -c "Digi-Key_PN" "$test_file" || echo "0")

	assertTrue "Property should be added to file" "[ $result -gt 0 ]"

	rm -f "$test_file" "${test_file}.bak"
}

#-----------------------------------
# Test: validate_kicad_sym() function
#-----------------------------------
testValidateKicadSym() {
	if ! declare -f validate_kicad_sym >/dev/null; then
		startSkipping
		return
	fi

	local valid_file="$FIXTURES_DIR/test_validate_valid.kicad_sym"
	cat >"$valid_file" <<'EOF'
(kicad_symbol_lib (version 20220914) (generator kicad_symbol_editor)
  (symbol "Valid" (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 0 0)
      (effects (font (size 1.27 1.27)))
    )
  )
)
EOF

	validate_kicad_sym "$valid_file"
	assertEquals "Valid file should pass validation" 0 $?

	rm -f "$valid_file"
}

testValidateKicadSymInvalid() {
	if ! declare -f validate_kicad_sym >/dev/null; then
		startSkipping
		return
	fi

	local invalid_file="$FIXTURES_DIR/test_validate_invalid.kicad_sym"
	echo "This is not a valid kicad symbol file" >"$invalid_file"

	validate_kicad_sym "$invalid_file"
	assertNotEquals "Invalid file should fail validation" 0 $?

	rm -f "$invalid_file"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2/shunit2"
