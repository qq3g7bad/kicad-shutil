#!/usr/bin/env bash

# @IMPL-WRITER-001@ (FROM: @ARCH-WRITER-001@)
# writer.sh - Property insertion and modification for KiCad symbol files
# Handles atomic writes with backup

# Add or update a property in a symbol
# Usage: add_or_update_property <file> <symbol_name> <property_name> <property_value>
add_or_update_property() {
	local file="$1"
	local symbol_name="$2"
	local prop_name="$3"
	local prop_value="$4"

	if [[ ! -f "$file" ]]; then
		error "File not found: $file"
		return 1
	fi

	# Create backup
	if ! backup_file "$file"; then
		error "Failed to create backup for: $file"
		return 1
	fi

	# Parse file to get symbol metadata
	local symbols_data
	symbols_data=$(parse_file "$file")
	local metadata
	metadata=$(get_symbol_metadata "$symbols_data" "$symbol_name")

	if [[ -z "$metadata" ]]; then
		error "Symbol not found: $symbol_name in $file"
		restore_from_backup "$file"
		return 1
	fi

	local props_end
	props_end=$(echo "$metadata" | cut -d'|' -f2)

	# Check if property already exists
	if has_property "$symbols_data" "$symbol_name" "$prop_name"; then
		# Update existing property
		update_property_value "$file" "$symbol_name" "$prop_name" "$prop_value"
	else
		# Insert new property
		insert_property "$file" "$symbol_name" "$prop_name" "$prop_value" "$props_end"
	fi

	# Verify the file is still valid after modification
	if ! verify_file_integrity "$file"; then
		error "File integrity check failed after modification"
		restore_from_backup "$file"
		return 1
	fi

	# Success - remove backup
	remove_backup "$file"
	return 0
}

# Insert a new property after the last existing property
insert_property() {
	local file="$1"
	local symbol_name="$2"
	local prop_name="$3"
	local prop_value="$4"
	local insert_after_line="$5"

	# Get indentation from the previous property line
	local indent
	indent=$(sed -n "${insert_after_line}p" "$file" | sed 's/^\(\s*\).*/\1/')

	# If no indent found (no properties yet), use default 4 spaces
	if [[ -z "$indent" ]]; then
		indent="    "
	fi

	# Format the new property (multi-line, KiCad style)
	local new_property
	new_property=$(
		cat <<EOF
${indent}(property "$prop_name" "$prop_value" (at 0 0 0)
${indent}  (effects (font (size 0 0)) hide)
${indent})
EOF
	)

	# Insert after the last property line
	# Use a temporary file for atomic write
	local temp_file="${file}.tmp.$$"

	if awk -v line="$insert_after_line" -v prop="$new_property" '
        NR == line { print; print prop; next }
        { print }
    ' "$file" >"$temp_file"; then
		mv "$temp_file" "$file"
		return 0
	else
		rm -f "$temp_file"
		return 1
	fi
}

# Update an existing property value
update_property_value() {
	local file="$1"
	local symbol_name="$2"
	local prop_name="$3"
	local new_value="$4"

	# Parse to find the property line
	local symbols_data
	symbols_data=$(parse_file "$file")
	local prop_info
	prop_info=$(get_all_properties "$symbols_data" "$symbol_name" | grep "^${prop_name}|")

	if [[ -z "$prop_info" ]]; then
		error "Property not found: $prop_name in symbol $symbol_name"
		return 1
	fi

	local prop_line
	prop_line=$(echo "$prop_info" | cut -d'|' -f3)

	# Replace the property value on that line
	local temp_file="${file}.tmp.$$"

	if awk -v line="$prop_line" -v prop="$prop_name" -v newval="$new_value" '
        NR == line {
            # Replace the value in the property definition
            # Match: (property "name" "old_value" ...
            # Replace with: (property "name" "new_value" ...
            sub(/"[^"]*"/, "\"" newval "\"", $0)
            print
            next
        }
        { print }
    ' "$file" >"$temp_file"; then
		mv "$temp_file" "$file"
		return 0
	else
		rm -f "$temp_file"
		return 1
	fi
}

# Verify file integrity (basic check: can we parse it?)
verify_file_integrity() {
	local file="$1"

	# Try to parse the file
	local symbols_data
	symbols_data=$(parse_file "$file" 2>/dev/null)

	if [[ -z "$symbols_data" ]]; then
		return 1 # Parse failed
	fi

	# Check for error markers
	if echo "$symbols_data" | grep -q "^ERROR|"; then
		return 1
	fi

	return 0
}

# Add multiple properties to a symbol (batch operation)
# Usage: add_properties_batch <file> <symbol_name> <prop1_name> <prop1_value> <prop2_name> <prop2_value> ...
add_properties_batch() {
	local file="$1"
	local symbol_name="$2"
	shift 2

	# Create backup once
	if ! backup_file "$file"; then
		error "Failed to create backup for: $file"
		return 1
	fi

	local success=true

	# Add properties one by one
	while [[ $# -ge 2 ]]; do
		local prop_name="$1"
		local prop_value="$2"
		shift 2

		# Don't create backup again (already done)
		if ! add_or_update_property_no_backup "$file" "$symbol_name" "$prop_name" "$prop_value"; then
			success=false
			break
		fi
	done

	if $success; then
		# Verify integrity
		if verify_file_integrity "$file"; then
			remove_backup "$file"
			return 0
		fi
	fi

	# Failed - restore backup
	restore_from_backup "$file"
	return 1
}

# Internal: add/update property without creating backup (for batch operations)
add_or_update_property_no_backup() {
	local file="$1"
	local symbol_name="$2"
	local prop_name="$3"
	local prop_value="$4"

	local symbols_data
	symbols_data=$(parse_file "$file")
	local metadata
	metadata=$(get_symbol_metadata "$symbols_data" "$symbol_name")

	if [[ -z "$metadata" ]]; then
		return 1
	fi

	local props_end
	props_end=$(echo "$metadata" | cut -d'|' -f2)

	if has_property "$symbols_data" "$symbol_name" "$prop_name"; then
		update_property_value "$file" "$symbol_name" "$prop_name" "$prop_value"
	else
		insert_property "$file" "$symbol_name" "$prop_name" "$prop_value" "$props_end"
	fi
}

# Delete a property from a symbol
# Usage: delete_property <file> <symbol_name> <property_name>
delete_property() {
	local file="$1"
	local symbol_name="$2"
	local prop_name="$3"

	if [[ ! -f "$file" ]]; then
		error "File not found: $file"
		return 1
	fi

	# Create backup
	if ! backup_file "$file"; then
		error "Failed to create backup for: $file"
		return 1
	fi

	# Parse file to get symbol metadata
	local symbols_data
	symbols_data=$(parse_file "$file")

	# Check if property exists
	if ! has_property "$symbols_data" "$symbol_name" "$prop_name"; then
		# Property doesn't exist, nothing to delete
		remove_backup "$file"
		return 0
	fi

	# Find the property lines to delete
	# A property spans multiple lines in KiCad format:
	# (property "Name" "Value" (at 0 0 0)
	#   (effects (font (size 0 0)) hide)
	# )

	local temp_file="${file}.tmp.$$"

	awk -v symbol="$symbol_name" -v prop="$prop_name" '
    BEGIN {
        in_symbol = 0
        in_property = 0
        skip_property = 0
        depth = 0
        prop_depth = 0
    }
    
    # Track when we enter the target symbol
    /^\s*\(symbol/ {
        if ($0 ~ "\\(symbol \"" symbol "\"") {
            in_symbol = 1
        }
    }
    
    # If in target symbol, check for the property
    in_symbol && /^\s*\(property/ {
        if ($0 ~ "\\(property \"" prop "\"") {
            in_property = 1
            skip_property = 1
            prop_depth = gsub(/\(/, "(", $0) - gsub(/\)/, ")", $0)
            next  # Skip this line
        }
    }
    
    # If we are skipping a property, track parentheses to know when it ends
    skip_property {
        prop_depth += gsub(/\(/, "(", $0) - gsub(/\)/, ")", $0)
        if (prop_depth <= 0) {
            skip_property = 0
            in_property = 0
        }
        next  # Skip lines within the property
    }
    
    # Exit symbol when we find the closing parenthesis at depth 0
    in_symbol && /^\s*\)/ {
        # Simple heuristic: if line is just ")" or "  )", it might close the symbol
        if ($0 ~ /^\s*\)\s*$/) {
            in_symbol = 0
        }
    }
    
    # Print all other lines
    { print }
    ' "$file" >"$temp_file"

	if mv "$temp_file" "$file"; then
		# Verify the file is still valid after modification
		if ! verify_file_integrity "$file"; then
			error "File integrity check failed after property deletion"
			restore_from_backup "$file"
			return 1
		fi

		remove_backup "$file"
		return 0
	else
		rm -f "$temp_file"
		restore_from_backup "$file"
		return 1
	fi
}
