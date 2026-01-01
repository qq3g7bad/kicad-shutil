#!/usr/bin/env bash

# @IMPL-PARSER-PROJECT-001@ (FROM: @ARCH-PARSER-002@)
# parser_project.sh - Parser for KiCad project files (.kicad_pro)
# Extracts environment variables, text variables, and KIPRJMOD path

# Parse a .kicad_pro file and extract project information
# Output format:
#   PROJECT_DIR|/absolute/path/to/project/dir
#   TEXT_VAR|var_name|var_value
#   ENV_VAR|var_name|var_value
parse_project_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "Project file not found: $file"
		return 1
	fi

	# Get project directory (KIPRJMOD)
	local project_dir
	project_dir=$(cd "$(dirname "$file")" && pwd)
	echo "PROJECT_DIR|$project_dir"

	# Parse JSON file using awk to extract text_variables
	# .kicad_pro files are JSON, but we want to avoid jq dependency
	# Extract text_variables section
	awk '
	BEGIN {
		in_text_vars = 0
		brace_depth = 0
	}

	# Find text_variables section
	/"text_variables"/ {
		in_text_vars = 1
		next
	}

	in_text_vars {
		# Track brace depth
		for (i = 1; i <= length($0); i++) {
			c = substr($0, i, 1)
			if (c == "{") brace_depth++
			if (c == "}") brace_depth--
		}

		# Extract key-value pairs
		if (match($0, /"([^"]+)"\s*:\s*"([^"]*)"/, m)) {
			var_name = m[1]
			var_value = m[2]
			print "TEXT_VAR|" var_name "|" var_value
		}

		# Exit text_variables section when closing brace
		if (brace_depth < 0) {
			in_text_vars = 0
		}
	}
	' "$file"

	# Parse environment section if present
	awk '
	BEGIN {
		in_environment = 0
		in_vars = 0
		brace_depth = 0
		var_depth = 0
	}

	# Find environment section
	/"environment"/ {
		in_environment = 1
		next
	}

	in_environment && /"vars"/ {
		in_vars = 1
		next
	}

	in_vars {
		# Track brace depth
		for (i = 1; i <= length($0); i++) {
			c = substr($0, i, 1)
			if (c == "{") var_depth++
			if (c == "}") var_depth--
		}

		# Extract key-value pairs
		if (match($0, /"([^"]+)"\s*:\s*"([^"]*)"/, m)) {
			var_name = m[1]
			var_value = m[2]
			print "ENV_VAR|" var_name "|" var_value
		}

		# Exit vars section when closing brace
		if (var_depth < 0) {
			in_vars = 0
			in_environment = 0
		}
	}
	' "$file"
}

# @IMPL-PARSER-PROJECT-002@ (FROM: @ARCH-PARSER-002@)
# Get project directory (KIPRJMOD equivalent)
# Usage: get_project_dir <project_data>
get_project_dir() {
	local project_data="$1"

	echo "$project_data" | awk -F'|' '
		$1 == "PROJECT_DIR" { print $2; exit }
	'
}

# @IMPL-PARSER-PROJECT-003@ (FROM: @ARCH-PARSER-002@)
# Get text variable value
# Usage: get_text_var <project_data> <var_name>
get_text_var() {
	local project_data="$1"
	local var_name="$2"

	echo "$project_data" | awk -F'|' -v var="$var_name" '
		$1 == "TEXT_VAR" && $2 == var { print $3; exit }
	'
}

# @IMPL-PARSER-PROJECT-004@ (FROM: @ARCH-PARSER-002@)
# Get environment variable value from project
# Usage: get_env_var <project_data> <var_name>
get_env_var() {
	local project_data="$1"
	local var_name="$2"

	echo "$project_data" | awk -F'|' -v var="$var_name" '
		$1 == "ENV_VAR" && $2 == var { print $3; exit }
	'
}

# @IMPL-PARSER-PROJECT-005@ (FROM: @ARCH-PARSER-002@)
# List all text variables
# Output: var_name|var_value (one per line)
list_text_vars() {
	local project_data="$1"

	echo "$project_data" | awk -F'|' '
		$1 == "TEXT_VAR" { print $2 "|" $3 }
	'
}

# @IMPL-PARSER-PROJECT-006@ (FROM: @ARCH-PARSER-002@)
# List all environment variables
# Output: var_name|var_value (one per line)
list_env_vars() {
	local project_data="$1"

	echo "$project_data" | awk -F'|' '
		$1 == "ENV_VAR" { print $2 "|" $3 }
	'
}
