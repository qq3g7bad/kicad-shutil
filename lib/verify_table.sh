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
	local line
	local new_env=""

	# Rebuild map without existing key entry.
	while IFS= read -r line; do
		if [[ -z "$line" ]]; then
			continue
		fi
		if [[ "$line" == "${key}|"* ]]; then
			continue
		fi
		new_env="${new_env}${line}"$'\n'
	done <<<"$KICAD_ENV"

	# Add/replace entry
	KICAD_ENV="${new_env}${key}|${value}"$'\n'
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

		# Support legacy KiCad path syntax :VAR: in addition to ${VAR}
		# Handle both :VAR:/foo and :VAR:foo forms.
		resolved=$(echo "$resolved" | sed -E 's/:([A-Za-z_][A-Za-z0-9_]*):\//${\1}\//g; s/:([A-Za-z_][A-Za-z0-9_]*):([^/])/${\1}\/\2/g')

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

# Get KiCad config base directory for current platform
get_kicad_config_base_dir() {
	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		echo "$HOME/.config/kicad"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		echo "$HOME/Library/Preferences/kicad"
	elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
		echo "$APPDATA/kicad"
	fi
}

# Detect KiCad version from kicad-cli output (returns major.minor when possible)
detect_kicad_cli_version() {
	if ! command -v kicad-cli >/dev/null 2>&1; then
		return 0
	fi

	local raw_version
	raw_version=$(kicad-cli --version 2>/dev/null | head -1)

	if [[ -z "$raw_version" ]]; then
		return 0
	fi

	local version
	version=$(echo "$raw_version" | grep -Eo '[0-9]+\.[0-9]+' | head -1 || true)
	if [[ -n "$version" ]]; then
		echo "$version"
		return 0
	fi

	local major
	major=$(echo "$raw_version" | grep -Eo '[0-9]+' | head -1 || true)
	if [[ -n "$major" ]]; then
		echo "${major}.0"
	fi
}

# Return major version from a version string (e.g. "8.0" -> "8")
kicad_version_major() {
	local version="$1"
	local major
	major=$(echo "$version" | sed -n 's/^\([0-9][0-9]*\)\(\.[0-9][0-9]*\)\{0,1\}$/\1/p')
	echo "$major"
}

# Pick config file from KiCad config root
# Output: "<version>|<path/to/kicad_common.json>"
select_kicad_config_file() {
	local config_root="$1"
	local preferred_version="${2:-}"

	if [[ -z "$config_root" || ! -d "$config_root" ]]; then
		return 0
	fi

	# Prefer requested version first (typically from kicad-cli --version)
	if [[ -n "$preferred_version" && -f "$config_root/$preferred_version/kicad_common.json" ]]; then
		echo "$preferred_version|$config_root/$preferred_version/kicad_common.json"
		return 0
	fi

	# Fallback: choose highest available version that has kicad_common.json
	local best_version=""
	local best_score=-1
	local dir
	for dir in "$config_root"/*; do
		if [[ ! -d "$dir" ]]; then
			continue
		fi

		local dir_name
		dir_name=$(basename "$dir")

		if ! echo "$dir_name" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
			continue
		fi

		if [[ ! -f "$dir/kicad_common.json" ]]; then
			continue
		fi

		local major minor score
		major="${dir_name%%.*}"
		if [[ "$dir_name" == *.* ]]; then
			minor="${dir_name#*.}"
		else
			minor="0"
		fi

		score=$((major * 1000 + minor))
		if ((score > best_score)); then
			best_score=$score
			best_version="$dir_name"
		fi
	done

	if [[ -n "$best_version" ]]; then
		echo "$best_version|$config_root/$best_version/kicad_common.json"
	fi
}

# Load KiCad environment variables
load_kicad_environment() {
	# Skip if already loaded
	if [[ -n "${KICAD_ENV_LOADED:-}" ]]; then
		return 0
	fi

	local kicad_version=""
	kicad_version=$(detect_kicad_cli_version)
	local kicad_major=""

	# Detect platform-specific KiCad config location
	local config_root=""
	local config_file=""
	config_root=$(get_kicad_config_base_dir)
	if [[ -n "$config_root" ]]; then
		local selected_config
		selected_config=$(select_kicad_config_file "$config_root" "$kicad_version")
		if [[ -n "$selected_config" ]]; then
			kicad_version="${selected_config%%|*}"
			config_file="${selected_config#*|}"
		fi
	fi

	if [[ -z "$kicad_version" ]]; then
		kicad_version="7.0"
	fi
	kicad_major=$(kicad_version_major "$kicad_version")
	if [[ -z "$kicad_major" ]]; then
		kicad_major="7"
		kicad_version="${kicad_major}.0"
	fi
	if [[ -z "$config_file" && -n "$config_root" ]]; then
		config_file="$config_root/$kicad_version/kicad_common.json"
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
	# Windows versioned install path (e.g. KiCad/9.0/share/kicad)
	elif [[ -d "$PROGRAMFILES/KiCad/$kicad_version/share/kicad/symbols" ]]; then
		symbol_dir="$PROGRAMFILES/KiCad/$kicad_version/share/kicad/symbols"
		footprint_dir="$PROGRAMFILES/KiCad/$kicad_version/share/kicad/footprints"
		model_3d_dir="$PROGRAMFILES/KiCad/$kicad_version/share/kicad/3dmodels"
	fi

	# Fallback: derive share/kicad from kicad-cli location (handles custom installs)
	if [[ -z "$symbol_dir" ]] && command -v kicad-cli >/dev/null 2>&1; then
		local cli_path cli_dir candidate
		cli_path=$(command -v kicad-cli)
		cli_dir=$(cd "$(dirname "$cli_path")" && pwd)

		for candidate in "$cli_dir/../share/kicad" "$cli_dir/../../share/kicad"; do
			if candidate=$(cd "$candidate" 2>/dev/null && pwd); then
				:
			else
				candidate=""
			fi
			if [[ -n "$candidate" && -d "$candidate/symbols" ]]; then
				symbol_dir="$candidate/symbols"
				footprint_dir="$candidate/footprints"
				model_3d_dir="$candidate/3dmodels"
				break
			fi
		done
	fi

	# Fallback: derive share/kicad from interpreter_path in kicad_common.json
	if [[ -z "$symbol_dir" && -f "$config_file" ]]; then
		local interpreter_path interpreter_unix bin_dir candidate
		interpreter_path=$(awk -F'"' '/"interpreter_path"[[:space:]]*:/ { print $4; exit }' "$config_file" || true)

		if [[ -n "$interpreter_path" ]]; then
			# Convert Windows path to POSIX-like path for Git Bash (e.g. D:\\foo -> /d/foo)
			interpreter_unix="${interpreter_path//\\//}"
			if [[ "$interpreter_unix" =~ ^([A-Za-z]):/(.*)$ ]]; then
				local drive_letter
				drive_letter=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
				interpreter_unix="/${drive_letter}/${BASH_REMATCH[2]}"
			fi

			if bin_dir=$(cd "$(dirname "$interpreter_unix")" 2>/dev/null && pwd); then
				:
			else
				bin_dir=""
			fi
			for candidate in "$bin_dir/../share/kicad" "$bin_dir/../../share/kicad"; do
				if candidate=$(cd "$candidate" 2>/dev/null && pwd); then
					:
				else
					candidate=""
				fi
				if [[ -n "$candidate" && -d "$candidate/symbols" ]]; then
					symbol_dir="$candidate/symbols"
					footprint_dir="$candidate/footprints"
					model_3d_dir="$candidate/3dmodels"
					break
				fi
			done
		fi
	fi

	# Set standard KiCad environment variables
	if [[ -n "$symbol_dir" ]]; then
		kicad_env_set "KICAD${kicad_major}_SYMBOL_DIR" "$symbol_dir"
		kicad_env_set "KICAD_SYMBOL_DIR" "$symbol_dir" # v6 compat
		for compat_major in 6 7 8 9; do
			kicad_env_set "KICAD${compat_major}_SYMBOL_DIR" "$symbol_dir"
		done
	fi

	if [[ -n "$footprint_dir" ]]; then
		kicad_env_set "KICAD${kicad_major}_FOOTPRINT_DIR" "$footprint_dir"
		kicad_env_set "KICAD_FOOTPRINT_DIR" "$footprint_dir" # v6 compat
		for compat_major in 6 7 8 9; do
			kicad_env_set "KICAD${compat_major}_FOOTPRINT_DIR" "$footprint_dir"
		done
	fi

	if [[ -n "$model_3d_dir" ]]; then
		kicad_env_set "KICAD${kicad_major}_3DMODEL_DIR" "$model_3d_dir"
		kicad_env_set "KICAD_3DMODEL_DIR" "$model_3d_dir" # v6 compat
		for compat_major in 6 7 8 9; do
			kicad_env_set "KICAD${compat_major}_3DMODEL_DIR" "$model_3d_dir"
		done
	fi

	# Parse custom variables from kicad_common.json if it exists
	if [[ -f "$config_file" ]]; then
		# Read only environment.vars key-value pairs from JSON (BSD awk compatible)
		local custom_var_pairs
		custom_var_pairs=$(awk '
		BEGIN {
			in_environment = 0
			in_vars = 0
			vars_depth = 0
		}

		!in_environment && /"environment"[[:space:]]*:/ {
			in_environment = 1
			next
		}

		in_environment && !in_vars && /"vars"[[:space:]]*:/ {
			in_vars = 1
			next
		}

		in_vars {
			line = $0

			for (i = 1; i <= length(line); i++) {
				c = substr(line, i, 1)
				if (c == "{") vars_depth++
				if (c == "}") vars_depth--
			}

			if (line ~ /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"[[:space:]]*,?[[:space:]]*$/) {
				key = line
				sub(/^[[:space:]]*"/, "", key)
				sub(/".*/, "", key)

				val = line
				sub(/^[^:]*:[[:space:]]*"/, "", val)
				sub(/"[[:space:]]*,?[[:space:]]*$/, "", val)

				# JSON unescape (minimal, path-safe)
				gsub(/\\\\/, "\\", val)

				print key "|" val
			}

			if (vars_depth < 0) {
				in_vars = 0
				in_environment = 0
			}
		}
		' "$config_file" || true)

		while IFS='|' read -r var_name var_value; do
			if [[ -n "$var_name" && -n "$var_value" ]]; then
				kicad_env_set "$var_name" "$var_value"
			fi
		done <<<"$custom_var_pairs"
	else
		warn "KiCad config file not found: $config_file"
	fi

	# Add system environment variables (override if set)
	for var in KICAD_SYMBOL_DIR KICAD_FOOTPRINT_DIR KICAD_3DMODEL_DIR \
		KIPRJMOD KICAD_USER_TEMPLATE_DIR; do
		if [[ -n "${!var:-}" ]]; then
			kicad_env_set "$var" "${!var}"
		fi
	done
	while IFS= read -r var; do
		if [[ -n "${!var:-}" ]]; then
			kicad_env_set "$var" "${!var}"
		fi
	done < <(env | awk -F= '/^KICAD[0-9]+_(SYMBOL_DIR|FOOTPRINT_DIR|3DMODEL_DIR)=/ { print $1 }')

	KICAD_ENV_LOADED="1"

	env_info "Detected KiCad version: $kicad_version"

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
