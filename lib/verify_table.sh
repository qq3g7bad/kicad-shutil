#!/usr/bin/env bash

# @IMPL-VERIFY-002@ (FROM: @ARCH-VERIFY-002@)
# verify_table.sh - Library table verification (sym-lib-table, fp-lib-table)

# Note: Ctrl-C handling is done in main script

# Global variables for KiCad environment (bash 3.2 compatible)
# Format: "key1|value1\nkey2|value2\n..."
KICAD_ENV=""
KICAD_ENV_LOADED=""
KICAD_UNRESOLVED_VARS=""

# Helper: Set key-value in KICAD_ENV
kicad_env_set() {
	local key="$1"
	local value="$2"
	# Remove existing entry if present
	KICAD_ENV=$(echo "$KICAD_ENV" | grep -v "^${key}|" || true)
	# Add new entry
	KICAD_ENV="${KICAD_ENV}${key}|${value}"$'\n'
}

# Helper: Get value from KICAD_ENV
kicad_env_get() {
	local key="$1"
	echo "$KICAD_ENV" | grep "^${key}|" | head -1 | cut -d'|' -f2-
}

# Helper: Count entries in KICAD_ENV
kicad_env_count() {
	echo "$KICAD_ENV" | grep -c '^[^[:space:]]' || true
}

# Helper: List all keys in KICAD_ENV
kicad_env_list_keys() {
	echo "$KICAD_ENV" | grep '^[^[:space:]]' | cut -d'|' -f1
}

# Helper: Add variable to unresolved list
kicad_unresolved_add() {
	local var_name="$1"
	# Only add if not already in list
	if ! echo "$KICAD_UNRESOLVED_VARS" | grep -q "^${var_name}$"; then
		KICAD_UNRESOLVED_VARS="${KICAD_UNRESOLVED_VARS}${var_name}"$'\n'
	fi
}

# Helper: Check if variable is in unresolved list
kicad_unresolved_has() {
	local var_name="$1"
	echo "$KICAD_UNRESOLVED_VARS" | grep -q "^${var_name}$"
}

# Helper: Count unresolved variables
kicad_unresolved_count() {
	echo "$KICAD_UNRESOLVED_VARS" | grep -c '^[^[:space:]]' || true
}

# Helper: List all unresolved variables
kicad_unresolved_list() {
	echo "$KICAD_UNRESOLVED_VARS" | grep '^[^[:space:]]'
}

# Normalize path to absolute clean path
# Usage: normalize_path <path>
normalize_path() {
	local path="$1"

	# If path doesn't exist, return as-is
	if [[ ! -e "$path" ]]; then
		echo "$path"
		return
	fi

	# Get absolute path and resolve .. and .
	local normalized
	if [[ -d "$path" ]]; then
		normalized="$(cd "$path" && pwd)"
	else
		normalized="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
	fi

	echo "$normalized"
}

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

	# Load KiCad environment once at the start
	load_kicad_environment

	# Read and parse the table
	local table_content
	table_content=$(cat "$table_file")

	# Extract library entries using awk (BSD compatible)
	local entries
	entries=$(echo "$table_content" | awk '
		/^[[:space:]]*\(lib[[:space:]]+\(name[[:space:]]+"[^"]+"/ {
			entry = $0
			paren_depth = gsub(/\(/, "&") - gsub(/\)/, "&")
			while (paren_depth > 0 && getline > 0) {
				entry = entry "\n" $0
				paren_depth += gsub(/\(/, "&") - gsub(/\)/, "&")
			}
			print entry
			print "---LIBSEP---"
		}
	')

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
		# Skip separator lines
		if [[ "$entry" == "---LIBSEP---" ]] || [[ -z "$entry" ]]; then
			continue
		fi

		# Skip disabled libraries
		if echo "$entry" | grep -qE '\(disabled\)'; then
			continue
		fi

		((total++))

		# Extract library properties using sed (POSIX BRE compatible)
		local lib_name
		lib_name=$(echo "$entry" | sed -n 's/.*(name[[:space:]]*"\([^"]*\)".*/\1/p')
		local lib_uri
		lib_uri=$(echo "$entry" | sed -n 's/.*(uri[[:space:]]*"\([^"]*\)".*/\1/p')

		if [[ -z "$lib_uri" ]]; then
			warn "$lib_name:No URI specified"
			((unresolved++))
			continue
		fi

		# Resolve environment variables in URI
		local resolved_uri
		resolved_uri=$(resolve_kicad_path "$lib_uri")

		if [[ -z "$resolved_uri" ]]; then
			error "$lib_name:Could not resolve URI:$lib_uri"
			((unresolved++))
			continue
		fi

		# Normalize path
		resolved_uri=$(normalize_path "$resolved_uri")

		# Check if path exists
		if [[ "$table_type" == "symbol" ]]; then
			# Symbol libraries are files
			if [[ -f "$resolved_uri" ]]; then
				((ok++))
			else
				echo "${COLOR_RED}[ERROR]:${COLOR_RESET}symbol:$lib_name:File not found:$resolved_uri" >&2
				((missing++))
			fi
		else
			# Footprint libraries are directories (.pretty)
			if [[ -d "$resolved_uri" ]]; then
				((ok++))
			else
				echo "${COLOR_RED}[ERROR]:${COLOR_RESET}footprint:$lib_name:Directory not found:$resolved_uri" >&2
				((missing++))
			fi
		fi
	done <<<"$entries"

	if [[ $missing -gt 0 || $unresolved -gt 0 ]]; then
		return 1
	fi

	return 0
}

# Resolve KiCad environment variables in a path
# Usage: resolve_kicad_path <path> [context]
# context: optional, 'sym-lib' or 'fp-lib' for error message categorization
# Note: load_kicad_environment() should be called before using this function
resolve_kicad_path() {
	local path="$1"
	local context="${2:-}"

	# Resolve environment variables recursively
	# Handle ${VAR} format, including nested variables like ${VAR1} -> ${VAR2} -> value
	local resolved="$path"
	local max_iterations=10
	local iteration=0

	while [[ $iteration -lt $max_iterations ]]; do
		((iteration++))

		# Extract all ${VAR} patterns using awk (BSD compatible)
		local vars
		vars=$(echo "$resolved" | awk '{
			while ((pos = match($0, /\$\{[^}]+\}/)) > 0) {
				print substr($0, RSTART, RLENGTH)
				$0 = substr($0, RSTART + RLENGTH)
			}
		}' | sort -u)

		# If no more variables to expand, we're done
		if [[ -z "$vars" ]]; then
			break
		fi

		local changed=false
		for var_expr in $vars; do
			# Remove ${ and }
			local var_name="${var_expr#\$\{}"
			var_name="${var_name%\}}"

			# Get value from environment (including KIPRJMOD if set by verify_project_file)
			local var_value="${!var_name:-}"

			if [[ -z "$var_value" ]]; then
				# Try to get from KiCad environment
				var_value=$(kicad_env_get "$var_name")
			fi

			if [[ -n "$var_value" ]]; then
				resolved="${resolved//$var_expr/$var_value}"
				changed=true
			else
				# Special case: KIPRJMOD needs project context
				if [[ "$var_name" == "KIPRJMOD" ]]; then
					if [[ -n "$context" ]]; then
						if [[ "$context" == "fp-lib" ]]; then
							echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	${COLOR_MAGENTA}$context${COLOR_RESET}	KIPRJMOD_NOT_IN_PROJECT_CONTEXT" >&2
							echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	${COLOR_MAGENTA}$context${COLOR_RESET}	USE_PROJECT_FILE_TO_VERIFY" >&2
						else
							echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	${COLOR_CYAN}$context${COLOR_RESET}	KIPRJMOD_NOT_IN_PROJECT_CONTEXT" >&2
							echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	${COLOR_CYAN}$context${COLOR_RESET}	USE_PROJECT_FILE_TO_VERIFY" >&2
						fi
					else
						echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	KIPRJMOD_NOT_IN_PROJECT_CONTEXT" >&2
						echo "${COLOR_YELLOW}[WARN]${COLOR_RESET}	USE_PROJECT_FILE_TO_VERIFY" >&2
					fi
				else
					# Track unresolved variable for verbose summary
					kicad_unresolved_add "$var_name"
				fi
				return 1
			fi
		done

		# If nothing changed in this iteration, break to avoid infinite loop
		if [[ "$changed" == "false" ]]; then
			break
		fi
	done

	# Check if we hit max iterations (circular reference)
	if [[ $iteration -eq $max_iterations ]] && echo "$resolved" | grep -qE '\$\{[^}]+\}'; then
		warn "Circular or too deeply nested environment variable references in: $path"
		return 1
	fi

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
		kicad_env_set "KICAD7_SYMBOL_DIR" "$symbol_dir"
		kicad_env_set "KICAD_SYMBOL_DIR" "$symbol_dir" # v6 compat
	fi

	if [[ -n "$footprint_dir" ]]; then
		kicad_env_set "KICAD7_FOOTPRINT_DIR" "$footprint_dir"
		kicad_env_set "KICAD_FOOTPRINT_DIR" "$footprint_dir" # v6 compat
	fi

	if [[ -n "$model_3d_dir" ]]; then
		kicad_env_set "KICAD7_3DMODEL_DIR" "$model_3d_dir"
		kicad_env_set "KICAD_3DMODEL_DIR" "$model_3d_dir" # v6 compat
	fi

	# Parse custom variables from kicad_common.json if it exists
	if [[ -f "$config_file" ]]; then
		# Get custom vars from environment.vars section using awk (BSD compatible)
		local custom_vars
		custom_vars=$(grep -A 100 '"environment"' "$config_file" \
			| grep -A 50 '"vars"' \
			| awk -F'"' '/"[^"]+"[[:space:]]*:[[:space:]]*"/ {print $2}' || true)

		# Read each custom variable
		while IFS= read -r var_name; do
			if [[ -z "$var_name" ]]; then
				continue
			fi

			# Extract value using awk (BSD compatible)
			local var_value
			var_value=$(grep -A 100 '"environment"' "$config_file" \
				| grep -A 50 '"vars"' \
				| awk -F'"' -v var="$var_name" '
					$0 ~ "\"" var "\"[[:space:]]*:[[:space:]]*\"" {
						for (i=1; i<=NF; i++) {
							if ($i == var && $(i+2) !~ /[:,{}]/) {
								print $(i+2)
								exit
							}
						}
					}')
			if [[ -n "$var_value" ]]; then
				kicad_env_set "$var_name" "$var_value"
			fi
		done <<<"$custom_vars"
	else
		warn "KiCad config file not found: $config_file"
	fi

	# Add system environment variables (override if set)
	for var in KICAD7_SYMBOL_DIR KICAD7_FOOTPRINT_DIR KICAD7_3DMODEL_DIR \
		KIPRJMOD KICAD_USER_TEMPLATE_DIR; do
		if [[ -n "${!var:-}" ]]; then
			kicad_env_set "$var" "${!var}"
		fi
	done

	KICAD_ENV_LOADED="1"

	# Debug: show loaded environment (only on first load)
	local var_count
	var_count=$(kicad_env_count)
	if [[ $var_count -gt 0 ]]; then
		# Show all environment variables only once
		if [[ "${_KICAD_ENV_MSG_SHOWN:-0}" != "1" ]]; then
			env_info "Loaded $var_count KiCad environment variables"
			# Sort and display all variables
			while IFS= read -r var_name; do
				local var_value
				var_value=$(kicad_env_get "$var_name")
				env_info "${var_name}=${var_value}"
			done < <(kicad_env_list_keys) | sort
			_KICAD_ENV_MSG_SHOWN="1"
		fi
	else
		if [[ "${_KICAD_ENV_MSG_SHOWN:-0}" != "1" ]]; then
			warn "No KiCad environment variables found - library resolution may fail"
			_KICAD_ENV_MSG_SHOWN="1"
		fi
	fi
}

# Show summary of unresolved environment variables (verbose mode only)
show_env_summary() {
	local unresolved_count
	unresolved_count=$(kicad_unresolved_count)

	if [[ "$unresolved_count" -eq 0 ]]; then
		return 0
	fi

	env_info ""
	env_info "=== Unresolved Environment Variables ==="
	env_info "Found $unresolved_count unresolved environment variable(s):"
	while IFS= read -r var_name; do
		env_info "  - $var_name"
	done < <(kicad_unresolved_list) | sort
	env_info ""
	env_info "These variables were referenced in library paths but not found in:"
	env_info "  - kicad_common.json"
	env_info "  - Environment variable exports"
	env_info ""
	env_info "To resolve, either:"
	env_info "  1. Add to kicad_common.json environment.vars section"
	env_info "  2. Export in shell: export VAR_NAME=/path/to/value"
}
