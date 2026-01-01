#!/usr/bin/env bash

# @TEST-PARSER-003@ (FROM: @IMPL-PARSER-003@)
# test_parser_footprint.sh - Tests for footprint parser

# Load test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the module to test
source "$SCRIPT_DIR/../lib/parser_footprint.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# Setup: disable color output for consistent test assertions
oneTimeSetUp() {
	export NO_COLOR=1
}

# Test: parse_footprint_file with a simple footprint
test_parse_footprint_basic() {
	local test_file="$SCRIPT_DIR/fixtures/test_footprint.kicad_mod"

	# Create test fixture
	cat >"$test_file" <<'EOF'
(footprint "SOIC-8_3.9x4.9mm_P1.27mm" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (descr "SOIC, 8 Pin (JEDEC MS-012AA, https://www.analog.com/media/en/package-pcb-resources/package/pkg_pdf/soic_narrow-r/r_8.pdf), generated with kicad-footprint-generator ipc_gullwing_generator.py")
  (tags "SOIC SO")
  (attr smd)
  (fp_text reference "REF**" (at 0 -3.4) (layer "F.SilkS")
      (effects (font (size 1 1) (thickness 0.15)))
  )
  (model "${KICAD7_3DMODEL_DIR}/Package_SO.3dshapes/SOIC-8_3.9x4.9mm_P1.27mm.wrl"
    (at (xyz 0 0 0))
    (scale (xyz 1 1 1))
    (rotate (xyz 0 0 0))
  )
)
EOF

	# Parse the file
	local result
	result=$(parse_footprint_file "$test_file")

	# Check FOOTPRINT line
	echo "$result" | grep -q "^FOOTPRINT|test_footprint$"
	assertTrue "Should find FOOTPRINT line" $?

	# Check MODEL line
	echo "$result" | grep -q "^MODEL|"
	assertTrue "Should find MODEL line" $?

	# Check model path contains the expected value
	echo "$result" | grep -q "KICAD7_3DMODEL_DIR"
	assertTrue "Should find model path with env var" $?

	# Clean up
	rm -f "$test_file"
}

# Test: count_models
test_count_models() {
	local test_file="$SCRIPT_DIR/fixtures/test_footprint_multi.kicad_mod"

	# Create test fixture with multiple models
	cat >"$test_file" <<'EOF'
(footprint "TEST" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (model "${KICAD7_3DMODEL_DIR}/model1.wrl"
    (at (xyz 0 0 0))
    (scale (xyz 1 1 1))
    (rotate (xyz 0 0 0))
  )
  (model "${KICAD7_3DMODEL_DIR}/model2.wrl"
    (at (xyz 0 0 0))
    (scale (xyz 1 1 1))
    (rotate (xyz 0 0 0))
  )
)
EOF

	local result
	result=$(parse_footprint_file "$test_file")
	local count
	count=$(count_models "$result")

	assertEquals "Should find 2 models" "2" "$count"

	# Clean up
	rm -f "$test_file"
}

# Test: footprint with no 3D model
test_footprint_no_model() {
	local test_file="$SCRIPT_DIR/fixtures/test_footprint_nomodel.kicad_mod"

	# Create test fixture without model
	cat >"$test_file" <<'EOF'
(footprint "TEST" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (fp_text reference "REF**" (at 0 -3.4) (layer "F.SilkS")
      (effects (font (size 1 1) (thickness 0.15)))
  )
)
EOF

	local result
	result=$(parse_footprint_file "$test_file")
	local count
	count=$(count_models "$result")

	assertEquals "Should find 0 models" "0" "$count"

	# Clean up
	rm -f "$test_file"
}

# Test: list_models
test_list_models() {
	local test_file="$SCRIPT_DIR/fixtures/test_footprint_list.kicad_mod"

	# Create test fixture
	cat >"$test_file" <<'EOF'
(footprint "TEST" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (model "/path/to/model1.wrl"
    (at (xyz 0 0 0))
    (scale (xyz 1 1 1))
    (rotate (xyz 0 0 0))
  )
  (model "/path/to/model2.step"
    (at (xyz 0 0 0))
    (scale (xyz 1 1 1))
    (rotate (xyz 0 0 0))
  )
)
EOF

	local result
	result=$(parse_footprint_file "$test_file")
	local models
	models=$(list_models "$result")

	# Check that we get both model paths
	echo "$models" | grep -q "/path/to/model1.wrl"
	assertTrue "Should find model1" $?

	echo "$models" | grep -q "/path/to/model2.step"
	assertTrue "Should find model2" $?

	# Clean up
	rm -f "$test_file"
}

# Load shunit2
source "$SCRIPT_DIR/shunit2/shunit2"
