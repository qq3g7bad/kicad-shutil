#!/usr/bin/env bash

# Unit tests for lib/parser_schematic.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"
FIXTURES_DIR="$TEST_DIR/fixtures"

source "$LIB_DIR/utils.sh"
source "$LIB_DIR/parser_schematic.sh"

# shellcheck disable=SC2034
export COLOR_RED=""
export COLOR_GREEN=""
export COLOR_YELLOW=""
export COLOR_BLUE=""
export COLOR_RESET=""

oneTimeSetUp() {
	mkdir -p "$FIXTURES_DIR"

	cat >"$FIXTURES_DIR/test_parser_schematic.kicad_sch" <<'EOF'
(kicad_sch (version 20230121) (generator eeschema)
  (uuid 00000000-0000-0000-0000-000000000000)

  (symbol (lib_id "Device:R") (at 10 10 0)
    (property "Reference" "R1" (at 0 0 0) (effects (font (size 1.27 1.27))))
    (property "Footprint" "Test:Existing" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))
  )

  (sheet (at 10 10) (size 20 20)
    (property "Sheet file" "child.kicad_sch" (at 10 10 0) (effects (font (size 1.27 1.27))))
  )
)
EOF
}

oneTimeTearDown() {
	rm -f "$FIXTURES_DIR/test_parser_schematic.kicad_sch"
}

testParseSchematicInstances() {
	local parsed
	parsed=$(parse_schematic_instances "$FIXTURES_DIR/test_parser_schematic.kicad_sch")

	assertContains "Parser should emit INSTANCE records" "$parsed" "INSTANCE|Device:R|R1|Test:Existing"
}

testListSheetFiles() {
	local sheet_files
	sheet_files=$(list_sheet_files "$FIXTURES_DIR/test_parser_schematic.kicad_sch")

	assertContains "Sheet file should be extracted" "$sheet_files" "child.kicad_sch"
}

source "$TEST_DIR/shunit2/shunit2"
