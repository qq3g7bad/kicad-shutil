#!/usr/bin/env bash

# verify_table.sh - Library table verification (sym-lib-table, fp-lib-table)

# Global variables for KiCad environment
declare -A KICAD_ENV
declare KICAD_ENV_LOADED=""

# Verify a library table file
# Usage: verify_table_file <table_file> <table_type>
#   table_type: "symbol" or "footprint"
verify_table_file() {
	local table_file="$1"
	local table_type="$2" # "symbol" or "footprint"

	if [[ ! -f "$table_file" ]]; then
		error "Table file not found: $table_file"
		return 1
	fi

	info "Verifying $table_type library table: $(basename "$table_file")"

	# Read and parse the table
	local table_content=$(cat "$table_file")

	# Extract library entries
	local entries=$(echo "$table_content" | grep -oP '\(lib\s+\(name\s+"[^"]+"\).*?\)(?=\s*\(lib|\s*\)$)')

	if [[ -z "$entries" ]]; then
		warn "No library entries found in $table_file"
		return 0
	fi

	# Counters
	local total=0
	local ok=0
	local missing=0
	local unresolved=0

	# Parse each library entry
	while IFS= read -r entry; do
		if [[ -z "$entry" ]]; then
			continue
		fi

		((total++))

		# Extract library properties
		local lib_name=$(echo "$entry" | grep -oP '\(name\s+"\K[^"]+')
		local lib_uri=$(echo "$entry" | grep -oP '\(uri\s+"\K[^"]+')

		if [[ -z "$lib_uri" ]]; then
			warn "  ⚠ $lib_name: No URI specified"
			((unresolved++))
			continue
		fi

		# Resolve environment variables in URI
		local resolved_uri=$(resolve_kicad_path "$lib_uri")

		if [[ -z "$resolved_uri" ]]; then
			error "  ✗ $lib_name: Could not resolve URI: $lib_uri"
			((unresolved++))
			continue
		fi

		# Check if path exists
		if [[ "$table_type" == "symbol" ]]; then
			# Symbol libraries are files
			if [[ -f "$resolved_uri" ]]; then
				success "  ✓ $lib_name: $resolved_uri"
				((ok++))
			else
				error "  ✗ $lib_name: File not found: $resolved_uri"
				((missing++))
			fi
		else
			# Footprint libraries are directories (.pretty)
			if [[ -d "$resolved_uri" ]]; then
				success "  ✓ $lib_name: $resolved_uri"
				((ok++))
			else
				error "  ✗ $lib_name: Directory not found: $resolved_uri"
				((missing++))
			fi
		fi
	done <<<"$entries"

	# Print summary
	echo ""
	echo "=========================================="
	echo "Library Table Verification Summary"
	echo "=========================================="
	echo "Total libraries: $total"
	echo "  ✓ Found: $ok"
	echo "  ✗ Missing: $missing"
	echo "  ⚠ Unresolved: $unresolved"
	echo "=========================================="

	if [[ $missing -gt 0 || $unresolved -gt 0 ]]; then
		return 1
	fi

	return 0
}

# Resolve KiCad environment variables in a path
# Usage: resolve_kicad_path <path>
resolve_kicad_path() {
	local path="$1"

	# Initialize KiCad environment if not done yet
	if [[ -z "${KICAD_ENV_LOADED:-}" ]]; then
		load_kicad_environment
	fi

	# Resolve environment variables
	# Handle ${VAR} format
	local resolved="$path"

	# Extract all ${VAR} patterns
	local vars=$(echo "$path" | grep -oP '\$\{[^}]+\}' | sort -u)

	for var_expr in $vars; do
		# Remove ${ and }
		local var_name="${var_expr#\$\{}"
		var_name="${var_name%\}}"

		# Skip KIPRJMOD as it's project-specific and can't be resolved here
		if [[ "$var_name" == "KIPRJMOD" ]]; then
			# Return the path as-is with warning
			return 1
		fi

		# Get value from environment
		local var_value="${!var_name:-}"

		if [[ -z "$var_value" ]]; then
			# Try to get from KiCad environment
			var_value="${KICAD_ENV[$var_name]:-}"
		fi

		if [[ -n "$var_value" ]]; then
			resolved="${resolved//$var_expr/$var_value}"
		else
			warn "Unresolved environment variable: $var_name"
			return 1
		fi
	done

	echo "$resolved"
}

# Load KiCad environment variables
load_kicad_environment() {
	# Skip if already loaded
	if [[ -n "${KICAD_ENV_LOADED:-}" ]]; then
		return 0
	fi

	local kicad_version="7.0"

	# Detect platform-specific KiCad config location
	local config_file=""
	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		config_file="$HOME/.config/kicad/$kicad_version/kicad_common.json"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		config_file="$HOME/Library/Preferences/kicad/$kicad_version/kicad_common.json"
	elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
		config_file="$APPDATA/kicad/$kicad_version/kicad_common.json"
	fi

	# Detect KiCad library installation paths
	# These are standard environment variables that KiCad sets internally
	local symbol_dir=""
	local footprint_dir=""
	local model_3d_dir=""

	# Linux / Unix
	if [[ -d "/usr/share/kicad/symbols" ]]; then
		symbol_dir="/usr/share/kicad/symbols"
		footprint_dir="/usr/share/kicad/footprints"
		model_3d_dir="/usr/share/kicad/3dmodels"
	elif [[ -d "/usr/local/share/kicad/symbols" ]]; then
		symbol_dir="/usr/local/share/kicad/symbols"
		footprint_dir="/usr/local/share/kicad/footprints"
		model_3d_dir="/usr/local/share/kicad/3dmodels"
	# macOS
	elif [[ -d "/Library/Application Support/kicad/symbols" ]]; then
		symbol_dir="/Library/Application Support/kicad/symbols"
		footprint_dir="/Library/Application Support/kicad/footprints"
		model_3d_dir="/Library/Application Support/kicad/3dmodels"
	# Windows (common paths)
	elif [[ -d "$PROGRAMFILES/KiCad/share/kicad/symbols" ]]; then
		symbol_dir="$PROGRAMFILES/KiCad/share/kicad/symbols"
		footprint_dir="$PROGRAMFILES/KiCad/share/kicad/footprints"
		model_3d_dir="$PROGRAMFILES/KiCad/share/kicad/3dmodels"
	fi

	# Set standard KiCad environment variables
	if [[ -n "$symbol_dir" ]]; then
		KICAD_ENV[KICAD7_SYMBOL_DIR]="$symbol_dir"
		KICAD_ENV[KICAD_SYMBOL_DIR]="$symbol_dir" # v6 compat
	fi

	if [[ -n "$footprint_dir" ]]; then
		KICAD_ENV[KICAD7_FOOTPRINT_DIR]="$footprint_dir"
		KICAD_ENV[KICAD_FOOTPRINT_DIR]="$footprint_dir" # v6 compat
	fi

	if [[ -n "$model_3d_dir" ]]; then
		KICAD_ENV[KICAD7_3DMODEL_DIR]="$model_3d_dir"
		KICAD_ENV[KICAD_3DMODEL_DIR]="$model_3d_dir" # v6 compat
	fi

	# Parse custom variables from kicad_common.json if it exists
	if [[ -f "$config_file" ]]; then
		# Get custom vars from environment.vars section
		local custom_vars=$(grep -A 100 '"environment"' "$config_file" \
			| grep -A 50 '"vars"' \
			| grep -oP '"\K[^"]+(?="\s*:\s*")' || true)

		# Read each custom variable
		while IFS= read -r var_name; do
			if [[ -z "$var_name" ]]; then
				continue
			fi

			# Extract value
			local var_value=$(grep -A 100 '"environment"' "$config_file" \
				| grep -A 50 '"vars"' \
				| grep -oP "\"$var_name\"\s*:\s*\"\K[^\"]+")

			if [[ -n "$var_value" ]]; then
				KICAD_ENV[$var_name]="$var_value"
			fi
		done <<<"$custom_vars"
	else
		warn "KiCad config file not found: $config_file"
	fi

	# Add system environment variables (override if set)
	for var in KICAD7_SYMBOL_DIR KICAD7_FOOTPRINT_DIR KICAD7_3DMODEL_DIR \
		KIPRJMOD KICAD_USER_TEMPLATE_DIR; do
		if [[ -n "${!var:-}" ]]; then
			KICAD_ENV[$var]="${!var}"
		fi
	done

	KICAD_ENV_LOADED="1"

	# Debug: show loaded environment (only on first load)
	local var_count=${#KICAD_ENV[@]}
	if [[ $var_count -gt 0 ]]; then
		# Show key paths  (suppress repeated messages by checking if already shown)
		if [[ -z "${_KICAD_ENV_SHOWN:-}" ]]; then
			info "Loaded $var_count KiCad environment variables"
			if [[ -n "${KICAD_ENV[KICAD7_SYMBOL_DIR]:-}" ]]; then
				info "  KICAD7_SYMBOL_DIR=${KICAD_ENV[KICAD7_SYMBOL_DIR]}"
			fi
			if [[ -n "${KICAD_ENV[KICAD7_FOOTPRINT_DIR]:-}" ]]; then
				info "  KICAD7_FOOTPRINT_DIR=${KICAD_ENV[KICAD7_FOOTPRINT_DIR]}"
			fi
			export _KICAD_ENV_SHOWN="1"
		fi
	else
		warn "No KiCad environment variables found - library resolution may fail"
	fi
}
