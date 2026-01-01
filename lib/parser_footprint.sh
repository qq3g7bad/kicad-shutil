#!/usr/bin/env bash

# @IMPL-PARSER-003@ (FROM: @ARCH-PARSER-003@)
# parser_footprint.sh - Parser for KiCad footprint files (.kicad_mod)
# Extracts 3D model information from footprint files

# Parse a .kicad_mod file and extract 3D model paths
# Output format:
#   FOOTPRINT|footprint_name
#   MODEL|/path/to/model.wrl|at|xyz|scale|xyz|rotate|xyz
#   MODEL|...
parse_footprint_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "Footprint file not found: $file"
		return 1
	fi

	# Get footprint name from filename
	local footprint_name
	footprint_name=$(basename "$file" .kicad_mod)
	echo "FOOTPRINT|$footprint_name"

	# Parse 3D models using awk
	# KiCad footprint files use S-expressions like:
	# (model "${KICAD7_3DMODEL_DIR}/Package_SO.3dshapes/SOIC-8_3.9x4.9mm_P1.27mm.wrl"
	#   (at (xyz 0 0 0))
	#   (scale (xyz 1 1 1))
	#   (rotate (xyz 0 0 0))
	# )
	awk '
	BEGIN {
		in_model = 0
		model_path = ""
		at_xyz = ""
		scale_xyz = ""
		rotate_xyz = ""
	}

	# Find model section
	/^\s*\(model/ {
		in_model = 1
		# Extract model path (handle quoted strings and environment variables)
		if (match($0, /\(model\s+"([^"]+)"/, m)) {
			model_path = m[1]
		} else if (match($0, /\(model\s+([^\s\)]+)/, m)) {
			model_path = m[1]
		}
		next
	}

	in_model {
		# Extract at (xyz ...) coordinates
		if (match($0, /\(at\s+\(xyz\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\)/, m)) {
			at_xyz = m[1] " " m[2] " " m[3]
		}

		# Extract scale (xyz ...) values
		if (match($0, /\(scale\s+\(xyz\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\)/, m)) {
			scale_xyz = m[1] " " m[2] " " m[3]
		}

		# Extract rotate (xyz ...) values
		if (match($0, /\(rotate\s+\(xyz\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\)/, m)) {
			rotate_xyz = m[1] " " m[2] " " m[3]
		}

		# End of model section
		if ($0 ~ /^\s*\)$/ && in_model) {
			# Output model information
			if (model_path != "") {
				print "MODEL|" model_path "|at|" at_xyz "|scale|" scale_xyz "|rotate|" rotate_xyz
			}

			# Reset for next model
			in_model = 0
			model_path = ""
			at_xyz = ""
			scale_xyz = ""
			rotate_xyz = ""
		}
	}
	' "$file"
}

# Get footprint name from parsed data
# Usage: get_footprint_name <footprint_data>
get_footprint_name() {
	local footprint_data="$1"
	echo "$footprint_data" | grep "^FOOTPRINT|" | head -n1 | cut -d'|' -f2
}

# List all 3D models in footprint
# Usage: list_models <footprint_data>
# Output: One model path per line
list_models() {
	local footprint_data="$1"
	echo "$footprint_data" | grep "^MODEL|" | cut -d'|' -f2
}

# Get model information
# Usage: get_model_info <footprint_data> <model_path>
# Returns: Full MODEL line for the specified model
get_model_info() {
	local footprint_data="$1"
	local model_path="$2"

	echo "$footprint_data" | grep "^MODEL|" | grep -F "|$model_path|" | head -n1
}

# Count models in footprint
# Usage: count_models <footprint_data>
count_models() {
	local footprint_data="$1"
	local count
	count=$(echo "$footprint_data" | grep -c "^MODEL|" || true)
	echo "$count"
}
