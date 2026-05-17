#!/usr/bin/env bash

# @TEST-PARSER-004@ (FROM: @IMPL-PARSER-004@)
# test_parser_silk.sh - Tests for the silkscreen parser

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/parser_silk.sh"

oneTimeSetUp() {
	export NO_COLOR=1
	TMPD="$(mktemp -d)"
}

oneTimeTearDown() {
	rm -rf "$TMPD"
}

# KiCad 7 style: each element on 1-2 lines, layer quoted
test_parse_kicad7_footprint() {
	local f="$TMPD/k7.kicad_mod"
	cat >"$f" <<'EOF'
(footprint "K7" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (fp_text reference "REF**" (at 0 -3.4) (layer "F.SilkS")
      (effects (font (size 1 1) (thickness 0.15))))
  (fp_text value "K7" (at 0 3.4) (layer "F.Fab")
      (effects (font (size 1 1) (thickness 0.15))))
  (fp_line (start -1 -1) (end 1 -1)
    (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp a))
  (fp_circle (center 0 0) (end 1 0)
    (stroke (width 0.2) (type solid)) (fill none) (layer "F.Fab") (tstamp b)))
EOF
	local out
	out=$(parse_silk_file "$f")

	echo "$out" | grep -q '^SILK|F.SilkS|fp_line|0.12$'
	assertTrue "fp_line on F.SilkS captured" $?

	echo "$out" | grep -q '^REFTEXT|F.SilkS|REF\*\*|1|1|0.15$'
	assertTrue "reference text on F.SilkS captured" $?

	# value text (F.Fab) and fp_circle (F.Fab) must be ignored
	assertEquals "no F.Fab elements" "" "$(echo "$out" | grep 'F.Fab' || true)"
	assertEquals "exactly one REFTEXT" "1" "$(echo "$out" | grep -c '^REFTEXT|' || true)"
	assertEquals "exactly one SILK" "1" "$(echo "$out" | grep -c '^SILK|' || true)"
}

# KiCad 8 style: deeply multi-line, (uuid ...) present
test_parse_kicad8_multiline() {
	local f="$TMPD/k8.kicad_mod"
	cat >"$f" <<'EOF'
(footprint "K8"
	(version 20240108)
	(fp_text reference "REF**"
		(at 0 -3.4 0)
		(layer "F.SilkS")
		(uuid "x")
		(effects
			(font
				(size 1.2 1.2)
				(thickness 0.2)
			)
		)
	)
	(fp_line
		(start -2.7 -1.4)
		(end -2.7 1.4)
		(stroke
			(width 0.12)
			(type solid)
		)
		(layer "F.SilkS")
		(uuid "y")
	)
)
EOF
	local out
	out=$(parse_silk_file "$f")

	echo "$out" | grep -q '^SILK|F.SilkS|fp_line|0.12$'
	assertTrue "K8 multi-line fp_line captured" $?

	echo "$out" | grep -q '^REFTEXT|F.SilkS|REF\*\*|1.2|1.2|0.2$'
	assertTrue "K8 multi-line reference captured" $?
}

# Board: gr_* primitives, layer filtering, B.SilkS, thickness-absent
test_parse_board_and_layers() {
	local f="$TMPD/board.kicad_pcb"
	cat >"$f" <<'EOF'
(kicad_pcb (version 20221018) (generator pcbnew)
  (gr_line (start 0 0) (end 10 0)
    (stroke (width 0.05) (type solid)) (layer "Edge.Cuts") (tstamp 1))
  (gr_line (start 0 0) (end 5 0)
    (stroke (width 0.15) (type solid)) (layer "F.SilkS") (tstamp 2))
  (gr_arc (start 0 0) (mid 1 1) (end 2 0)
    (stroke (width 0.1) (type solid)) (layer "B.SilkS") (tstamp 3))
  (footprint "R" (layer "F.Cu") (at 1 1)
    (fp_text reference "R1" (at 0 -1) (layer "F.SilkS")
      (effects (font (size 1 1))))
    (fp_line (start 0 0) (end 1 0)
      (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp 4))))
EOF
	local out
	out=$(parse_silk_file "$f")

	# Edge.Cuts gr_line ignored
	assertEquals "Edge.Cuts ignored" "" "$(echo "$out" | grep 'Edge.Cuts' || true)"

	echo "$out" | grep -q '^SILK|F.SilkS|gr_line|0.15$'
	assertTrue "gr_line on F.SilkS captured" $?

	echo "$out" | grep -q '^SILK|B.SilkS|gr_arc|0.1$'
	assertTrue "gr_arc on B.SilkS captured" $?

	echo "$out" | grep -q '^SILK|F.SilkS|fp_line|0.12$'
	assertTrue "footprint fp_line captured" $?

	# thickness absent -> empty 6th field
	echo "$out" | grep -q '^REFTEXT|F.SilkS|R1|1|1|$'
	assertTrue "reference with no thickness has empty field" $?
}

test_helper_functions() {
	local f="$TMPD/h.kicad_mod"
	cat >"$f" <<'EOF'
(footprint "H" (version 20221018) (generator pcbnew)
  (fp_text reference "REF**" (at 0 0) (layer "F.SilkS")
      (effects (font (size 1 1) (thickness 0.15))))
  (fp_line (start 0 0) (end 1 0)
    (stroke (width 0.12) (type solid)) (layer "F.SilkS") (tstamp a))
  (fp_line (start 1 0) (end 1 1)
    (stroke (width 0.15) (type solid)) (layer "F.SilkS") (tstamp b)))
EOF
	local out
	out=$(parse_silk_file "$f")

	assertEquals "stroke count" "2" "$(silk_stroke_count "$out")"
	assertEquals "ref count" "1" "$(silk_ref_count "$out")"

	local widths
	widths=$(silk_widths "$out" | sort | tr '\n' ' ')
	assertEquals "widths list" "0.12 0.15 " "$widths"

	assertEquals "ref dims" "1|1|0.15" "$(silk_ref_dims "$out")"
}

test_missing_file() {
	parse_silk_file "$TMPD/does_not_exist.kicad_mod" >/dev/null 2>&1
	assertFalse "missing file returns non-zero" $?
}

. "$SCRIPT_DIR/shunit2/shunit2"
