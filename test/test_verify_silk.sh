#!/usr/bin/env bash

# @TEST-VERIFY-SILK-001@ (FROM: @IMPL-VERIFY-SILK-001@)
# test_verify_silk.sh - Tests for silkscreen uniformity verification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/verify_silk.sh"

oneTimeSetUp() {
	export NO_COLOR=1
	TMPD="$(mktemp -d)"

	# Footprint A: uniformly 0.12 width, 1x1/0.15 text
	cat >"$TMPD/A.kicad_mod" <<'EOF'
(footprint "A" (version 20221018) (generator pcbnew)
  (fp_text reference "REF**" (at 0 0) (layer "F.SilkS")
      (effects (font (size 1 1) (thickness 0.15))))
  (fp_line (start 0 0) (end 1 0)
    (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp a))
  (fp_line (start 1 0) (end 1 1)
    (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp b)))
EOF

	# Footprint B: uniformly 0.15 width, 1x1/0.15 text  (width differs from A)
	cat >"$TMPD/B.kicad_mod" <<'EOF'
(footprint "B" (version 20221018) (generator pcbnew)
  (fp_text reference "REF**" (at 0 0) (layer "F.SilkS")
      (effects (font (size 1 1) (thickness 0.15))))
  (fp_line (start 0 0) (end 1 0)
    (stroke (width 0.15) (type solid)) (layer "F.SilkS") (tstamp a)))
EOF

	# Footprint C: 0.12 width, but 2x2/0.2 text  (text differs from A)
	cat >"$TMPD/C.kicad_mod" <<'EOF'
(footprint "C" (version 20221018) (generator pcbnew)
  (fp_text reference "REF**" (at 0 0) (layer "F.SilkS")
      (effects (font (size 2 2) (thickness 0.2))))
  (fp_line (start 0 0) (end 1 0)
    (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp a)))
EOF

	# Footprint with no silkscreen at all
	cat >"$TMPD/nosilk.kicad_mod" <<'EOF'
(footprint "N" (version 20221018) (generator pcbnew)
  (fp_text value "N" (at 0 0) (layer "F.Fab")
      (effects (font (size 1 1) (thickness 0.15))))
  (fp_line (start 0 0) (end 1 0)
    (stroke (width 0.1) (type solid)) (layer "F.Fab") (tstamp a)))
EOF
}

oneTimeTearDown() {
	rm -rf "$TMPD"
}

setUp() {
	export SILK_EXPECTED_WIDTH=""
	export SILK_EXPECTED_TEXT_SIZE=""
	export SILK_EXPECTED_TEXT_THICKNESS=""
	export VERBOSE=false
	init_silk_stats
}

test_uniform_single_file_passes() {
	verify_silk_file "$TMPD/A.kicad_mod" "A"
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "uniform set is OK" "0" "$?"
}

test_nonuniform_width_across_files_fails() {
	verify_silk_file "$TMPD/A.kicad_mod" "A"
	verify_silk_file "$TMPD/B.kicad_mod" "B"
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "differing widths fail" "1" "$?"
	assertEquals "two distinct widths" "2" "$(_silk_distinct_count "$SILK_ALL_WIDTHS")"
}

test_nonuniform_textsize_across_files_fails() {
	verify_silk_file "$TMPD/A.kicad_mod" "A"
	verify_silk_file "$TMPD/C.kicad_mod" "C"
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "differing text sizes fail" "1" "$?"
	assertEquals "widths still uniform" "1" "$(_silk_distinct_count "$SILK_ALL_WIDTHS")"
	assertEquals "two distinct text sizes" "2" "$(_silk_distinct_count "$SILK_ALL_TEXTDIMS")"
}

test_expected_width_mismatch_fails() {
	export SILK_EXPECTED_WIDTH="0.15"
	verify_silk_file "$TMPD/A.kicad_mod" "A" # A is 0.12
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "0.12 != expected 0.15" "1" "$?"
}

test_expected_width_match_passes() {
	export SILK_EXPECTED_WIDTH="0.12"
	verify_silk_file "$TMPD/A.kicad_mod" "A" # A is 0.12
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "0.12 == expected 0.12" "0" "$?"
}

test_expected_text_size_hxw() {
	export SILK_EXPECTED_TEXT_SIZE="1x1"
	verify_silk_file "$TMPD/A.kicad_mod" "A" # A text is 1x1
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "1x1 matches expected" "0" "$?"

	init_silk_stats
	export SILK_EXPECTED_TEXT_SIZE="1x1"
	verify_silk_file "$TMPD/C.kicad_mod" "C" # C text is 2x2
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "2x2 != expected 1x1" "1" "$?"
}

test_expected_text_thickness() {
	export SILK_EXPECTED_TEXT_THICKNESS="0.15"
	verify_silk_file "$TMPD/C.kicad_mod" "C" # C thickness is 0.2
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "0.2 != expected thickness 0.15" "1" "$?"
}

test_file_without_silk_is_ignored() {
	verify_silk_file "$TMPD/nosilk.kicad_mod" "N"
	assertEquals "file counted" "1" "$SILK_STATS_FILES"
	assertEquals "no silk content" "0" "$SILK_STATS_WITH_SILK"
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "empty set is OK" "0" "$?"
}

test_cross_file_set_combines_all_inputs() {
	verify_silk_file "$TMPD/A.kicad_mod" "A"
	verify_silk_file "$TMPD/B.kicad_mod" "B"
	verify_silk_file "$TMPD/C.kicad_mod" "C"
	# widths: A=0.12, B=0.15, C=0.12 -> distinct {0.12, 0.15} = 2
	assertEquals "distinct widths over set" "2" "$(_silk_distinct_count "$SILK_ALL_WIDTHS")"
	# text: A=1x1/0.15, B=1x1/0.15, C=2x2/0.2 -> distinct = 2
	assertEquals "distinct text dims over set" "2" "$(_silk_distinct_count "$SILK_ALL_TEXTDIMS")"
	evaluate_silk_set >/dev/null 2>&1
	assertEquals "non-uniform set fails" "1" "$?"
}

. "$SCRIPT_DIR/shunit2/shunit2"
