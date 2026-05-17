#!/usr/bin/env bash

# @IMPL-VERIFY-SILK-001@ (FROM: @ARCH-VERIFY-001@)
# verify_silk.sh - Silkscreen uniformity verification
#
# The input set (one .kicad_pcb board, or every .kicad_mod discovered under
# the given files/directories) is treated as a single library that should
# look consistent. The set is OK when it uses a single silkscreen line width
# and a single reference-designator text size; two or more distinct values
# anywhere in the set is an issue. Each value is reported together with the
# files that use it so the outlier footprint is easy to find.
#
# Optionally exact values can be enforced via configuration:
#   SILK_EXPECTED_WIDTH           e.g. 0.15      (mm)
#   SILK_EXPECTED_TEXT_SIZE       e.g. 1  or  1x1
#   SILK_EXPECTED_TEXT_THICKNESS  e.g. 0.15      (mm)
#
# Output follows the project convention: [WARN]/[ERROR] to stderr, a
# summary at the end, non-zero exit when issues are found. bash 3.2 safe
# (no associative arrays at shell scope; grouping is done in awk).

# Prevent multiple sourcing
if [[ -n "${_KICAD_SHUTIL_VERIFY_SILK_SH_:-}" ]]; then
	return 0
fi
readonly _KICAD_SHUTIL_VERIFY_SILK_SH_=1

# Parser dependency
PARSER_SILK_LOADED="${PARSER_SILK_LOADED:-}"
if [[ -z "$PARSER_SILK_LOADED" ]]; then
	source "$(dirname "${BASH_SOURCE[0]}")/parser_silk.sh"
	PARSER_SILK_LOADED="1"
fi

# Configuration (set by cmd_mod / cmd_pcb from CLI flags; empty = unset)
SILK_EXPECTED_WIDTH="${SILK_EXPECTED_WIDTH:-}"
SILK_EXPECTED_TEXT_SIZE="${SILK_EXPECTED_TEXT_SIZE:-}"
SILK_EXPECTED_TEXT_THICKNESS="${SILK_EXPECTED_TEXT_THICKNESS:-}"

# Statistics / cross-file accumulators.
# SILK_ALL_WIDTHS / SILK_ALL_TEXTDIMS hold one "value|file" line per
# distinct value per file (the building block for the set-wide verdict).
SILK_STATS_FILES=0
SILK_STATS_WITH_SILK=0
SILK_ALL_WIDTHS=""
SILK_ALL_TEXTDIMS=""

# Initialize silk verification state
init_silk_stats() {
	SILK_STATS_FILES=0
	SILK_STATS_WITH_SILK=0
	SILK_ALL_WIDTHS=""
	SILK_ALL_TEXTDIMS=""
}

# Summarize one file's parsed silk data into distinct-value buckets.
# Reads SILK|/REFTEXT| lines on stdin, writes tab-separated records:
#   WIDTH   <norm> <count> <sample_etype>
#   TEXTDIM <h> <w> <thk> <count> <sample_ref>
_silk_summarize() {
	awk -F'|' '
	function n4(x) { if (x == "" || x == "-") return "-"; return sprintf("%.4f", x + 0) }
	$1 == "SILK" {
		k = n4($4)
		if (!(k in wseen)) { wcount++; worder[wcount] = k; wsample[k] = $3 }
		wseen[k]++
	}
	$1 == "REFTEXT" {
		kh = n4($4); kw = n4($5); kt = n4($6)
		key = kh "/" kw "/" kt
		if (!(key in tseen)) {
			tcount++; torder[tcount] = key; tsample[key] = $3
			th_arr[key] = kh; tw_arr[key] = kw; tt_arr[key] = kt
		}
		tseen[key]++
	}
	END {
		for (i = 1; i <= wcount; i++) { k = worder[i]; print "WIDTH\t" k "\t" wseen[k] "\t" wsample[k] }
		for (i = 1; i <= tcount; i++) {
			k = torder[i]
			print "TEXTDIM\t" th_arr[k] "\t" tw_arr[k] "\t" tt_arr[k] "\t" tseen[k] "\t" tsample[k]
		}
	}
	'
}

# @IMPL-VERIFY-SILK-002@ (FROM: @ARCH-VERIFY-001@)
# Accumulate one file's silkscreen values into the set.
# Usage: verify_silk_file <file> <display_label>
verify_silk_file() {
	local file="$1"
	local label="$2"

	SILK_STATS_FILES=$((SILK_STATS_FILES + 1))

	local data
	data="$(parse_silk_file "$file" 2>/dev/null || true)"
	if [[ -z "$data" ]]; then
		info "  $label: no silkscreen graphics found"
		return 0
	fi
	SILK_STATS_WITH_SILK=$((SILK_STATS_WITH_SILK + 1))

	local summary
	summary="$(printf '%s\n' "$data" | _silk_summarize)"

	# Verbose per-file breakdown of every distinct value seen
	if [[ "${VERBOSE:-false}" == "true" ]]; then
		awk -F'\t' -v f="$label" \
			'$1=="WIDTH"{print "  ["f"] silk width "$2" mm  x"$3"  (e.g. "$4")"}
			 $1=="TEXTDIM"{print "  ["f"] ref text  "$2"x"$3" thk="$4"  x"$5"  (e.g. "$6")"}' \
			<<<"$summary" >&2
	fi

	# Accumulate this file's distinct values for the set-wide verdict
	local v
	while IFS= read -r v; do
		if [[ -n "$v" ]]; then
			SILK_ALL_WIDTHS="${SILK_ALL_WIDTHS}${v}|${label}"$'\n'
		fi
	done < <(awk -F'\t' '$1=="WIDTH"{print $2}' <<<"$summary")
	while IFS= read -r v; do
		if [[ -n "$v" ]]; then
			SILK_ALL_TEXTDIMS="${SILK_ALL_TEXTDIMS}${v}|${label}"$'\n'
		fi
	done < <(awk -F'\t' '$1=="TEXTDIM"{print $2"x"$3"/"$4}' <<<"$summary")

	return 0
}

# Normalize a number the same way the parser/summarizer does (%.4f)
_silk_norm() {
	awk -v x="$1" 'BEGIN { if (x == "") print ""; else printf "%.4f", x + 0 }'
}

# Count distinct values (field 1, "value|file" lines) in an accumulator.
# Pure awk (no grep) so the exit status is always 0 under `set -e`.
_silk_distinct_count() {
	printf '%s' "$1" \
		| awk -F'|' '$0!=""{ a[$1]=1 } END { n=0; for (k in a) n++; print n }'
}

# Print "value unit — file, file, ..." for each value, to stderr.
# $1 accumulator, $2 unit suffix, $3 (optional) expected value: when set,
# only values different from it are printed (the offenders).
# Note: awk variable must not be named `exp` (gawk builtin function).
_silk_print_value_files() {
	printf '%s' "$1" | sort -u 2>/dev/null \
		| awk -F'|' -v unit="$2" -v want="$3" '
			$0 == "" { next }
			want != "" && $1 == want { next }
			{ if (!($1 in seen)) { order[++n] = $1; seen[$1] = 1 }
			  files[$1] = files[$1] (files[$1] == "" ? "" : ", ") $2 }
			END { for (i = 1; i <= n; i++) { k = order[i]; print "    " k " " unit " — " files[k] } }
		' >&2 || true
}

# @IMPL-VERIFY-SILK-003@ (FROM: @ARCH-VERIFY-001@)
# Evaluate the whole accumulated set. Returns 1 if any issue is found.
evaluate_silk_set() {
	local issue=0

	# ---- silkscreen line width ----
	if [[ -n "$SILK_ALL_WIDTHS" ]]; then
		if [[ -n "$SILK_EXPECTED_WIDTH" ]]; then
			local enw bad
			enw="$(_silk_norm "$SILK_EXPECTED_WIDTH")"
			bad="$(printf '%s' "$SILK_ALL_WIDTHS" | grep -v '^$' | awk -F'|' -v e="$enw" '$1!=e' || true)"
			if [[ -n "$bad" ]]; then
				error "SILK_WIDTH_NOT_EXPECTED — expected ${enw} mm, but found:"
				_silk_print_value_files "$SILK_ALL_WIDTHS" "mm" "$enw"
				issue=1
			fi
		else
			local dw
			dw="$(_silk_distinct_count "$SILK_ALL_WIDTHS")"
			if [[ "${dw:-0}" -gt 1 ]]; then
				warn "NON_UNIFORM_SILK_WIDTH — ${dw} distinct line widths in the set:"
				_silk_print_value_files "$SILK_ALL_WIDTHS" "mm" ""
				issue=1
			fi
		fi
	fi

	# ---- reference-designator text size ----
	if [[ -n "$SILK_ALL_TEXTDIMS" ]]; then
		if [[ -n "$SILK_EXPECTED_TEXT_SIZE" || -n "$SILK_EXPECTED_TEXT_THICKNESS" ]]; then
			local eh ew et bad
			eh="$(_silk_norm "${SILK_EXPECTED_TEXT_SIZE%%x*}")"
			if [[ "$SILK_EXPECTED_TEXT_SIZE" == *x* ]]; then
				ew="$(_silk_norm "${SILK_EXPECTED_TEXT_SIZE#*x}")"
			else
				ew="$eh"
			fi
			et="$(_silk_norm "$SILK_EXPECTED_TEXT_THICKNESS")"
			# A textdim signature is "h x w / thk"; build the matcher.
			bad="$(printf '%s' "$SILK_ALL_TEXTDIMS" | grep -v '^$' | awk -F'|' \
				-v eh="$eh" -v ew="$ew" -v et="$et" -v chk_s="$SILK_EXPECTED_TEXT_SIZE" -v chk_t="$SILK_EXPECTED_TEXT_THICKNESS" '
				{ split($1, a, "x"); h = a[1]; rest = a[2]; split(rest, b, "/"); w = b[1]; t = b[2]
				  bad = 0
				  if (chk_s != "" && (h != eh || w != ew)) bad = 1
				  if (chk_t != "" && t != et) bad = 1
				  if (bad) print }' || true)"
			if [[ -n "$bad" ]]; then
				local want="${SILK_EXPECTED_TEXT_SIZE:-any}"
				[[ -n "$SILK_EXPECTED_TEXT_THICKNESS" ]] && want="${want} / thk ${SILK_EXPECTED_TEXT_THICKNESS}"
				error "REF_TEXT_SIZE_NOT_EXPECTED — expected ${want}, but found:"
				_silk_print_value_files "$SILK_ALL_TEXTDIMS" "(HxW/thk)" ""
				issue=1
			fi
		else
			local dt
			dt="$(_silk_distinct_count "$SILK_ALL_TEXTDIMS")"
			if [[ "${dt:-0}" -gt 1 ]]; then
				warn "NON_UNIFORM_REF_TEXT_SIZE — ${dt} distinct reference text sizes in the set:"
				_silk_print_value_files "$SILK_ALL_TEXTDIMS" "(HxW/thk)" ""
				issue=1
			fi
		fi
	fi

	if [[ $issue -eq 0 ]]; then
		success "Silkscreen is uniform across the set"
	fi
	return $issue
}

# @IMPL-VERIFY-SILK-004@ (FROM: @ARCH-VERIFY-001@)
# Print the observed-values summary.
print_silk_summary() {
	echo
	echo "=========================================="
	echo "Silkscreen Uniformity Summary"
	echo "=========================================="
	echo "Files checked:        $SILK_STATS_FILES"
	echo "Files with silk:      $SILK_STATS_WITH_SILK"

	if [[ -n "$SILK_ALL_WIDTHS" ]]; then
		echo
		echo "Silk line widths observed:"
		printf '%s' "$SILK_ALL_WIDTHS" | grep -v '^$' | sort -u 2>/dev/null \
			| awk -F'|' '{c[$1]++} END{for(k in c) print "  "k" mm — "c[k]" file(s)"}' \
			| sort || true
	fi

	if [[ -n "$SILK_ALL_TEXTDIMS" ]]; then
		echo
		echo "Reference text sizes observed (HxW/thickness):"
		printf '%s' "$SILK_ALL_TEXTDIMS" | grep -v '^$' | sort -u 2>/dev/null \
			| awk -F'|' '{c[$1]++} END{for(k in c) print "  "k" — "c[k]" file(s)"}' \
			| sort || true
	fi
	echo "=========================================="
}
