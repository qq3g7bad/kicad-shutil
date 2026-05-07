#!/usr/bin/env bash

# parser_schematic.sh - Parser for KiCad schematic files (.kicad_sch)
# Extracts instantiated symbols and sheet references.

# Parse schematic symbol instances from a .kicad_sch file.
# Output format:
#   INSTANCE|lib_id|reference|footprint
parse_schematic_instances() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "Schematic file not found: $file"
		return 1
	fi

	awk '
	BEGIN {
		in_symbol = 0
		symbol_depth = 0
		lib_id = ""
		reference = ""
		footprint = ""
	}

	{
		line = $0

		if (!in_symbol && line ~ /\(symbol([[:space:]]|$)/) {
			in_symbol = 1
			symbol_depth = 0
			lib_id = ""
			reference = ""
			footprint = ""
		}

		if (in_symbol) {
			if (line ~ /\(lib_id[[:space:]]+"[^"]+"/) {
				candidate = line
				sub(/.*\(lib_id[[:space:]]+"/, "", candidate)
				sub(/".*/, "", candidate)
				lib_id = candidate
			}

			if (line ~ /\(property[[:space:]]+"Reference"[[:space:]]+"[^"]*"/) {
				candidate = line
				sub(/.*\(property[[:space:]]+"Reference"[[:space:]]+"/, "", candidate)
				sub(/".*/, "", candidate)
				reference = candidate
			}

			if (line ~ /\(property[[:space:]]+"Footprint"[[:space:]]+"[^"]*"/) {
				candidate = line
				sub(/.*\(property[[:space:]]+"Footprint"[[:space:]]+"/, "", candidate)
				sub(/".*/, "", candidate)
				footprint = candidate
			}
		}

		if (in_symbol) {
			line_copy = line
			open_count = gsub(/\(/, "(", line_copy)
			close_count = gsub(/\)/, ")", line_copy)
			symbol_depth += open_count - close_count

			if (symbol_depth <= 0) {
				# Require lib_id to avoid picking lib_symbols definitions.
				if (lib_id != "") {
					gsub(/\|/, "/", lib_id)
					gsub(/\|/, "/", reference)
					gsub(/\|/, "/", footprint)
					print "INSTANCE|" lib_id "|" reference "|" footprint
				}
				in_symbol = 0
				symbol_depth = 0
			}
		}
	}
	' "$file"
}

# List sheet file references from a .kicad_sch file.
# Output: one file path per line.
list_sheet_files() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "Schematic file not found: $file"
		return 1
	fi

	awk '
	/\(property[[:space:]]+"Sheet file"[[:space:]]+"[^"]+"/ {
		line = $0
		sub(/.*\(property[[:space:]]+"Sheet file"[[:space:]]+"/, "", line)
		sub(/".*/, "", line)
		print line
	}
	' "$file"
}
