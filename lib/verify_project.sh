#!/usr/bin/env bash

# @IMPL-VERIFY-003@ (FROM: @ARCH-VERIFY-003@)
# verify_project.sh - Verification module for KiCad project files

# Source project parser
PARSER_PROJECT_LOADED="${PARSER_PROJECT_LOADED:-}"
if [[ -z "$PARSER_PROJECT_LOADED" ]]; then
	source "$(dirname "${BASH_SOURCE[0]}")/parser_project.sh"
	PARSER_PROJECT_LOADED="1"
fi

# Source footprint parser
PARSER_FOOTPRINT_LOADED="${PARSER_FOOTPRINT_LOADED:-}"
if [[ -z "$PARSER_FOOTPRINT_LOADED" ]]; then
	source "$(dirname "${BASH_SOURCE[0]}")/parser_footprint.sh"
	PARSER_FOOTPRINT_LOADED="1"
fi

# Source symbol parser (for checking footprint properties)
PARSER_LOADED="${PARSER_LOADED:-}"
if [[ -z "$PARSER_LOADED" ]]; then
	source "$(dirname "${BASH_SOURCE[0]}")/parser.sh"
	PARSER_LOADED="1"
fi

# @IMPL-VERIFY-PROJECT-001@ (FROM: @ARCH-VERIFY-003@)
# Verify a KiCad project file and its associated library tables
# Usage: verify_project_file <project_file>
verify_project_file() {
	local project_file="$1"
	local filename
	filename=$(basename "$project_file")

	if [[ ! -f "$project_file" ]]; then
		error "Project file not found: $project_file"
		return 1
	fi

	info "Verifying KiCad project: $filename"

	# Parse project file
	local project_data
	project_data=$(parse_project_file "$project_file")
	local project_dir
	project_dir=$(get_project_dir "$project_data")

	if [[ -z "$project_dir" ]]; then
		error "Could not determine project directory"
		return 1
	fi

	info "Project directory:$project_dir"

	# Export KIPRJMOD for use in library table resolution
	export KIPRJMOD="$project_dir"

	# Check for text variables
	local text_vars
	text_vars=$(list_text_vars "$project_data")
	if [[ -n "$text_vars" ]]; then
		local var_count
		var_count=$(echo "$text_vars" | wc -l)
		info "Found $var_count text variable(s)"
		while IFS='|' read -r var_name var_value; do
			if [[ -n "$var_name" ]]; then
				info "$var_name = $var_value"
			fi
		done <<<"$text_vars"
	fi

	# Check for environment variables
	local env_vars
	env_vars=$(list_env_vars "$project_data")
	if [[ -n "$env_vars" ]]; then
		local var_count
		var_count=$(echo "$env_vars" | wc -l)
		info "Found $var_count project environment variable(s)"
		while IFS='|' read -r var_name var_value; do
			if [[ -n "$var_name" ]]; then
				info "$var_name = $var_value"
				# Export for use in library table resolution
				export "$var_name=$var_value"
			fi
		done <<<"$env_vars"
	fi

	# Verify library tables in the same directory
	local sym_table="$project_dir/sym-lib-table"
	local fp_table="$project_dir/fp-lib-table"

	local tables_found=0
	local tables_verified=0

	# Statistics for deep verification
	local total_sym_libs=0
	local total_symbols=0
	local total_fp_libs=0
	local total_footprints=0
	local symbols_missing_footprint=0
	local symbols_footprint_not_found=0
	local footprints_missing_3d=0
	local footprints_3d_not_found=0
	local symbols_missing_datasheet=0

	if [[ -f "$sym_table" ]]; then
		((tables_found++))
		info "Found symbol library table: sym-lib-table"
		if verify_table_file "$sym_table" "symbol"; then
			((tables_verified++))
		fi

		# Deep verification: check symbols in each library
		info ""
		info "Deep verification of symbol libraries..."
		local sym_lib_stats
		sym_lib_stats=$(verify_symbol_libraries "$sym_table" "$project_dir" "$fp_table")
		if [[ -n "$sym_lib_stats" ]]; then
			total_sym_libs=$(echo "$sym_lib_stats" | grep "^LIBS|" | cut -d'|' -f2)
			total_symbols=$(echo "$sym_lib_stats" | grep "^SYMBOLS|" | cut -d'|' -f2)
			symbols_missing_footprint=$(echo "$sym_lib_stats" | grep "^MISSING_FP|" | cut -d'|' -f2)
			symbols_footprint_not_found=$(echo "$sym_lib_stats" | grep "^FP_NOT_FOUND|" | cut -d'|' -f2)
			symbols_missing_datasheet=$(echo "$sym_lib_stats" | grep "^MISSING_DS|" | cut -d'|' -f2)
		fi
	else
		warn "Symbol library table not found:sym-lib-table"
		warn "Expected at:$sym_table"
		echo ""
	fi

	if [[ -f "$fp_table" ]]; then
		((tables_found++))
		info "Found footprint library table: fp-lib-table"
		if verify_table_file "$fp_table" "footprint"; then
			((tables_verified++))
		fi

		# Deep verification: check footprints in each library
		info ""
		info "Deep verification of footprint libraries..."
		local fp_lib_stats
		fp_lib_stats=$(verify_footprint_libraries "$fp_table" "$project_dir")
		if [[ -n "$fp_lib_stats" ]]; then
			total_fp_libs=$(echo "$fp_lib_stats" | grep "^LIBS|" | cut -d'|' -f2)
			total_footprints=$(echo "$fp_lib_stats" | grep "^FOOTPRINTS|" | cut -d'|' -f2)
			footprints_missing_3d=$(echo "$fp_lib_stats" | grep "^MISSING_3D|" | cut -d'|' -f2)
			footprints_3d_not_found=$(echo "$fp_lib_stats" | grep "^3D_NOT_FOUND|" | cut -d'|' -f2)
		fi
	else
		warn "Footprint library table not found:fp-lib-table"
		warn "Expected at:$fp_table"
		echo ""
	fi

	# Summary (only in verbose mode)
	if [[ "${VERBOSE:-false}" == "true" ]]; then
		echo "=========================================="
		echo "Project Verification Summary"
		echo "=========================================="
		echo "Project:$filename"
		echo "Directory:$project_dir"
		echo "Library tables found:$tables_found"
		echo "Library tables verified:$tables_verified"
		echo ""
		echo "Symbol Libraries:"
		echo "  Total libraries:$total_sym_libs"
		echo "  Total symbols:$total_symbols"
		if [[ $symbols_missing_footprint -gt 0 ]]; then
			error "  Missing footprint field:$symbols_missing_footprint"
		else
			echo "  Missing footprint field:$symbols_missing_footprint"
		fi
		if [[ $symbols_footprint_not_found -gt 0 ]]; then
			error "  Footprint file not found:$symbols_footprint_not_found"
		else
			echo "  Footprint file not found:$symbols_footprint_not_found"
		fi
		if [[ $symbols_missing_datasheet -gt 0 ]]; then
			warn "  Missing datasheet:$symbols_missing_datasheet"
		else
			echo "  Missing datasheet:$symbols_missing_datasheet"
		fi
		echo ""
		echo "Footprint Libraries:"
		echo "  Total libraries:$total_fp_libs"
		echo "  Total footprints:$total_footprints"
		if [[ $footprints_missing_3d -gt 0 ]]; then
			warn "  Missing 3D model field:$footprints_missing_3d"
		else
			echo "  Missing 3D model field:$footprints_missing_3d"
		fi
		if [[ $footprints_3d_not_found -gt 0 ]]; then
			error "  3D model file not found:$footprints_3d_not_found"
		else
			echo "  3D model file not found:$footprints_3d_not_found"
		fi
		echo "=========================================="

		# Future: verify .kicad_sch files
		# Find all schematic files in the project directory
		local sch_files
		sch_files=$(find "$project_dir" -maxdepth 2 -name "*.kicad_sch" 2>/dev/null)
		if [[ -n "$sch_files" ]]; then
			local sch_count
			sch_count=$(echo "$sch_files" | wc -l)
			info ""
			info "Note: Found $sch_count schematic file(s) in project directory"
			info "      Schematic verification will be supported in a future release"
		fi
	fi

	if [[ $tables_found -eq 0 ]]; then
		warn "No library tables found in project directory"
		show_env_summary
		return 1
	fi

	if [[ $tables_verified -lt $tables_found ]]; then
		show_env_summary
		return 1
	fi

	show_env_summary
	return 0
}

# @IMPL-VERIFY-PROJECT-002@ (FROM: @ARCH-VERIFY-003@)
# Verify all symbol libraries in a symbol library table
# Usage: verify_symbol_libraries <sym_table_file> <project_dir> <fp_table_file>
# Output: Statistics in pipe-delimited format
verify_symbol_libraries() {
	local sym_table="$1"
	local project_dir="$2"
	local fp_table="$3"

	local total_libs=0
	local total_symbols=0
	local missing_footprint=0
	local footprint_not_found=0
	local missing_datasheet=0

	# Build a map of available footprints from fp-lib-table
	declare -A footprint_map
	if [[ -n "$fp_table" && -f "$fp_table" ]]; then
		# Load KiCad environment for path resolution
		if [[ -z "$KICAD_ENV_LOADED" ]]; then
			source "$(dirname "${BASH_SOURCE[0]}")/verify_table.sh"
			load_kicad_environment
		fi

		local table_content
		table_content=$(cat "$fp_table")
		local fp_entries
		fp_entries=$(echo "$table_content" | grep -oP '\(lib\s+\(name\s+"[^"]+"\).*?\)(?=\s*\(lib|\s*\)$)')

		while IFS= read -r entry; do
			if [[ -z "$entry" ]]; then
				continue
			fi

			# Skip disabled libraries
			# <!-- @IMPL-VERIFY-PROJECT-003@ (FROM: @REQ-PROJ-001@) -->
			if echo "$entry" | grep -qE '\(disabled\)'; then
				continue
			fi

			local lib_name
			lib_name=$(echo "$entry" | grep -oP '\(name\s+"\K[^"]+')
			local lib_uri
			lib_uri=$(echo "$entry" | grep -oP '\(uri\s+"\K[^"]+')

			if [[ -z "$lib_uri" ]]; then
				continue
			fi

			# Resolve path
			local resolved_uri
			resolved_uri=$(resolve_kicad_path "$lib_uri")
			if [[ -z "$resolved_uri" || ! -d "$resolved_uri" ]]; then
				continue
			fi

			# Index all footprints in this library
			local mod_files
			mod_files=$(find "$resolved_uri" -maxdepth 1 -name "*.kicad_mod" 2>/dev/null)
			while IFS= read -r mod_file; do
				if [[ -z "$mod_file" || ! -f "$mod_file" ]]; then
					continue
				fi
				local fp_name
				fp_name=$(basename "$mod_file" .kicad_mod)
				# Store as "LibraryName:FootprintName" -> full_path
				footprint_map["$lib_name:$fp_name"]="$mod_file"
			done <<<"$mod_files"
		done <<<"$fp_entries"
	fi

	# Load KiCad environment for path resolution
	if [[ -z "$KICAD_ENV_LOADED" ]]; then
		source "$(dirname "${BASH_SOURCE[0]}")/verify_table.sh"
		load_kicad_environment
	fi

	# Parse library table to get all library paths
	local table_content
	table_content=$(cat "$sym_table")
	local entries
	entries=$(echo "$table_content" | grep -oP '\(lib\s+\(name\s+"[^"]+"\).*?\)(?=\s*\(lib|\s*\)$)')

	while IFS= read -r entry; do
		if [[ -z "$entry" ]]; then
			continue
		fi

		# Skip disabled libraries
		# <!-- @IMPL-VERIFY-PROJECT-001@ (FROM: @REQ-PROJ-001@) -->
		if echo "$entry" | grep -qE '\(disabled\)'; then
			[[ "${VERBOSE:-false}" == "true" ]] && info "Skipping disabled symbol library: $lib_name"
			continue
		fi

		local lib_name
		lib_name=$(echo "$entry" | grep -oP '\(name\s+"\K[^"]+')
		local lib_uri
		lib_uri=$(echo "$entry" | grep -oP '\(uri\s+"\K[^"]+')

		if [[ -z "$lib_uri" ]]; then
			continue
		fi

		# Resolve path
		local resolved_uri
		resolved_uri=$(resolve_kicad_path "$lib_uri")
		if [[ -z "$resolved_uri" || ! -f "$resolved_uri" ]]; then
			continue
		fi

		((total_libs++))
		info "Checking symbol library: $lib_name"

		# Parse symbol file
		local symbols_data
		symbols_data=$(parse_file "$resolved_uri" 2>/dev/null)
		if [[ -z "$symbols_data" ]]; then
			continue
		fi

		local symbols
		symbols=$(list_symbols "$symbols_data")
		while IFS= read -r symbol; do
			if [[ -z "$symbol" ]]; then
				continue
			fi

			((total_symbols++))

			# Check footprint
			local footprint
			footprint=$(get_property "$symbols_data" "$symbol" "Footprint")
			if [[ -z "$footprint" || "$footprint" == "" ]]; then
				((missing_footprint++))
				echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	${COLOR_CYAN}sym-lib${COLOR_RESET}	$lib_name	$symbol	MISSING_FOOTPRINT_FIELD" >&2
			else
				# Verify footprint file exists
				# Footprint format: "LibraryName:FootprintName"
				if [[ ${#footprint_map[@]} -gt 0 ]]; then
					if [[ -z "${footprint_map[$footprint]:-}" ]]; then
						((footprint_not_found++))
						if [[ "${VERBOSE:-false}" == "true" ]]; then
							echo "${COLOR_RED}[ERROR]${COLOR_RESET}	${COLOR_CYAN}sym-lib${COLOR_RESET}	$lib_name	$symbol	FOOTPRINT_NOT_FOUND	$footprint" >&2
						else
							echo "${COLOR_RED}[ERROR]${COLOR_RESET}	${COLOR_CYAN}sym-lib${COLOR_RESET}	$lib_name	$symbol	FOOTPRINT_NOT_FOUND" >&2
						fi
					fi
				fi
			fi

			# Check datasheet
			local datasheet
			datasheet=$(get_property "$symbols_data" "$symbol" "Datasheet")
			if [[ -z "$datasheet" || "$datasheet" == "" ]]; then
				((missing_datasheet++))
			fi
		done <<<"$symbols"

	done <<<"$entries"

	# Output statistics
	echo "LIBS|$total_libs"
	echo "SYMBOLS|$total_symbols"
	echo "MISSING_FP|$missing_footprint"
	echo "FP_NOT_FOUND|$footprint_not_found"
	echo "MISSING_DS|$missing_datasheet"
}

# @IMPL-VERIFY-PROJECT-003@ (FROM: @ARCH-VERIFY-003@)
# Verify all footprint libraries in a footprint library table
# Usage: verify_footprint_libraries <fp_table_file> <project_dir>
# Output: Statistics in pipe-delimited format
verify_footprint_libraries() {
	local fp_table="$1"
	local project_dir="$2"

	local total_libs=0
	local total_footprints=0
	local missing_3d=0
	local model_not_found=0

	# Load KiCad environment for path resolution
	if [[ -z "$KICAD_ENV_LOADED" ]]; then
		source "$(dirname "${BASH_SOURCE[0]}")/verify_table.sh"
		load_kicad_environment
	fi

	# Parse library table to get all library paths
	local table_content
	table_content=$(cat "$fp_table")
	local entries
	entries=$(echo "$table_content" | grep -oP '\(lib\s+\(name\s+"[^"]+"\).*?\)(?=\s*\(lib|\s*\)$)')

	while IFS= read -r entry; do
		if [[ -z "$entry" ]]; then
			continue
		fi

		# Skip disabled libraries
		# <!-- @IMPL-VERIFY-PROJECT-002@ (FROM: @REQ-PROJ-001@) -->
		if echo "$entry" | grep -qE '\(disabled\)'; then
			continue
		fi

		local lib_name
		lib_name=$(echo "$entry" | grep -oP '\(name\s+"\K[^"]+')
		local lib_uri
		lib_uri=$(echo "$entry" | grep -oP '\(uri\s+"\K[^"]+')

		if [[ -z "$lib_uri" ]]; then
			continue
		fi

		# Resolve path
		local resolved_uri
		resolved_uri=$(resolve_kicad_path "$lib_uri")
		if [[ -z "$resolved_uri" || ! -d "$resolved_uri" ]]; then
			continue
		fi

		((total_libs++))

		# Find all .kicad_mod files in the library directory
		local mod_files
		mod_files=$(find "$resolved_uri" -maxdepth 1 -name "*.kicad_mod" 2>/dev/null)

		while IFS= read -r mod_file; do
			if [[ -z "$mod_file" || ! -f "$mod_file" ]]; then
				continue
			fi

			((total_footprints++))

			# Parse footprint file
			local footprint_data
			footprint_data=$(parse_footprint_file "$mod_file" 2>/dev/null)
			if [[ -z "$footprint_data" ]]; then
				continue
			fi

			local fp_name
			fp_name=$(basename "$mod_file" .kicad_mod)

			# Check for 3D models
			local model_count
			model_count=$(count_models "$footprint_data")
			if [[ $model_count -eq 0 ]]; then
				((missing_3d++))
				echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	${COLOR_MAGENTA}fp-lib${COLOR_RESET}	$lib_name	$fp_name	NO_3D_MODEL_FIELD" >&2
			else
				# Verify each 3D model file exists
				local models
				models=$(list_models "$footprint_data")
				while IFS= read -r model_path; do
					if [[ -z "$model_path" ]]; then
						continue
					fi

					# Resolve environment variables in model path
					local resolved_model
					resolved_model=$(resolve_kicad_path "$model_path" "fp-lib")
					if [[ -z "$resolved_model" ]]; then
						((model_not_found++))
						if [[ "${VERBOSE:-false}" == "true" ]]; then
							echo "${COLOR_RED}[ERROR]${COLOR_RESET}	${COLOR_MAGENTA}fp-lib${COLOR_RESET}	$lib_name	$fp_name	CANNOT_RESOLVE_3D_MODEL_PATH	$model_path" >&2
						else
							echo "${COLOR_RED}[ERROR]${COLOR_RESET}	${COLOR_MAGENTA}fp-lib${COLOR_RESET}	$lib_name	$fp_name	CANNOT_RESOLVE_3D_MODEL_PATH" >&2
						fi
					elif [[ ! -f "$resolved_model" ]]; then
						((model_not_found++))
						# Normalize path for cleaner output
						resolved_model=$(normalize_path "$resolved_model")
						if [[ "${VERBOSE:-false}" == "true" ]]; then
							echo "${COLOR_RED}[ERROR]${COLOR_RESET}	${COLOR_MAGENTA}fp-lib${COLOR_RESET}	$lib_name	$fp_name	3D_MODEL_FILE_NOT_FOUND	$resolved_model" >&2
						else
							echo "${COLOR_RED}[ERROR]${COLOR_RESET}	${COLOR_MAGENTA}fp-lib${COLOR_RESET}	$lib_name	$fp_name	3D_MODEL_FILE_NOT_FOUND" >&2
						fi
					fi
				done <<<"$models"
			fi
		done <<<"$mod_files"

	done <<<"$entries"

	# Output statistics
	echo "LIBS|$total_libs"
	echo "FOOTPRINTS|$total_footprints"
	echo "MISSING_3D|$missing_3d"
	echo "3D_NOT_FOUND|$model_not_found"
}
