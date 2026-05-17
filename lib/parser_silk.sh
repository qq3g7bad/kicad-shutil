#!/usr/bin/env bash

# @IMPL-PARSER-004@ (FROM: @ARCH-PARSER-004@)
# parser_silk.sh - Parser for silkscreen graphics in KiCad files
#
# Extracts silkscreen stroke widths and reference-designator text effects
# from both .kicad_pcb (board) and .kicad_mod (footprint) files. The two
# formats share the same S-expression syntax for graphic primitives; the
# board format additionally uses gr_* primitives and wraps footprints.
#
# Output format (pipe-delimited, same convention as parser_footprint.sh):
#   SILK|<layer>|<element_type>|<width>
#   REFTEXT|<layer>|<ref_text>|<size_h>|<size_w>|<thickness>
#
# Only silkscreen layers (F.SilkS / B.SilkS) are reported. REFTEXT is only
# emitted for `fp_text reference` (the symbol name, e.g. U1, C3, REF**);
# `value`/`user` text and board-level gr_text are intentionally ignored.

# Parse a .kicad_pcb or .kicad_mod file and extract silkscreen metadata
# Usage: parse_silk_file <file>
parse_silk_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "File not found: $file"
		return 1
	fi

	# The awk program scans the file character-by-character so that
	# parentheses inside quoted strings never affect nesting depth, and
	# accumulates each graphic element across however many lines it spans
	# (KiCad 7 splits onto 2 lines, KiCad 8 onto many).
	awk '
	# Update g_depth for one line, ignoring parens inside quoted strings.
	# g_instr / g_esc persist across lines (strings never span newlines in
	# practice, but carrying state is harmless and defensive).
	function scan_line(s,   i, c, n) {
		n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 1)
			if (g_esc) { g_esc = 0; continue }
			if (c == "\\") { g_esc = 1; continue }
			if (c == "\"") { g_instr = !g_instr; continue }
			if (g_instr) continue
			if (c == "(") g_depth++
			else if (c == ")") g_depth--
		}
	}

	# Pull a single number that follows a given S-expr keyword, e.g.
	# num_after(buf, "width") -> 0.12  for  (stroke (width 0.12) ...)
	# A dynamic (string) regex is required because awk cannot concatenate
	# /regex/ constants with a variable.
	function num_after(buf, kw,   re, s) {
		re = "\\(" kw " [0-9.eE+-]+"
		if (match(buf, re)) {
			s = substr(buf, RSTART, RLENGTH)
			sub("^\\(" kw " ", "", s)
			return s
		}
		return ""
	}

	function emit_element(buf,   etype, layer, ls, reftext, sz, a, h, w, thick, width) {
		# Element type = first token after the opening paren
		if (!match(buf, /\((fp_line|fp_arc|fp_circle|fp_poly|fp_rect|gr_line|gr_arc|gr_circle|gr_poly|gr_rect|fp_text)/))
			return
		etype = substr(buf, RSTART + 1, RLENGTH - 1)

		# Layer (supports quoted "F.SilkS" and legacy unquoted F.SilkS)
		layer = ""
		if (match(buf, /\(layer "?[A-Za-z0-9._]+"?\)/)) {
			ls = substr(buf, RSTART, RLENGTH)
			sub(/^\(layer "?/, "", ls)
			sub(/"?\)$/, "", ls)
			layer = ls
		}
		if (layer != "F.SilkS" && layer != "B.SilkS")
			return

		if (etype == "fp_text") {
			# Only reference designators (the symbol name)
			if (buf !~ /\(fp_text[[:space:]]+reference[[:space:]]+"/)
				return
			reftext = ""
			if (match(buf, /\(fp_text[[:space:]]+reference[[:space:]]+"[^"]*"/)) {
				reftext = substr(buf, RSTART, RLENGTH)
				sub(/^\(fp_text[[:space:]]+reference[[:space:]]+"/, "", reftext)
				sub(/"$/, "", reftext)
			}
			h = ""; w = ""
			if (match(buf, /\(size [0-9.eE+-]+ [0-9.eE+-]+/)) {
				sz = substr(buf, RSTART, RLENGTH)
				sub(/^\(size /, "", sz)
				split(sz, a, " ")
				h = a[1]; w = a[2]
			}
			thick = num_after(buf, "thickness")
			print "REFTEXT|" layer "|" reftext "|" h "|" w "|" thick
			return
		}

		# Stroke primitive: width lives in (stroke (width W)) or, in very
		# old footprints, directly as (width W).
		width = num_after(buf, "width")
		if (width != "")
			print "SILK|" layer "|" etype "|" width
	}

	BEGIN { cap = 0; g_depth = 0; g_instr = 0; g_esc = 0 }
	{
		line = $0
		if (!cap) {
			if (line ~ /^[[:space:]]*\((fp_line|fp_arc|fp_circle|fp_poly|fp_rect|gr_line|gr_arc|gr_circle|gr_poly|gr_rect|fp_text)([[:space:]]|\(|\)|$)/) {
				cap = 1
				buf = ""
				g_depth = 0
				g_instr = 0
				g_esc = 0
			} else {
				next
			}
		}
		if (cap) {
			buf = (buf == "" ? line : buf "\n" line)
			scan_line(line)
			if (g_depth <= 0) {
				emit_element(buf)
				cap = 0
			}
		}
	}
	' "$file"
}

# List all silkscreen stroke widths (one per line)
# Usage: silk_widths <silk_data>
silk_widths() {
	echo "$1" | grep "^SILK|" | cut -d'|' -f4
}

# List all reference-text dimension signatures as "h|w|thickness"
# Usage: silk_ref_dims <silk_data>
silk_ref_dims() {
	echo "$1" | grep "^REFTEXT|" | cut -d'|' -f4,5,6
}

# Count silkscreen stroke elements
# Usage: silk_stroke_count <silk_data>
silk_stroke_count() {
	local count
	count=$(echo "$1" | grep -c "^SILK|" || true)
	echo "$count"
}

# Count reference-text elements
# Usage: silk_ref_count <silk_data>
silk_ref_count() {
	local count
	count=$(echo "$1" | grep -c "^REFTEXT|" || true)
	echo "$count"
}
