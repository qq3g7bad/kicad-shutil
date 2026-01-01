#!/usr/bin/env bash

# parser.sh - S-expression parser for KiCad symbol files
# Parses .kicad_sym files and extracts symbol metadata

# @IMPL-PARSER-001@ (FROM: @ARCH-PARSER-001@)
# Parse a .kicad_sym file and extract all symbols with their properties
# Output format:
#   SYMBOL|symbol_name|start_line|props_end_line
#   PROP|property_name|property_value|line_number
#   PROP|...
#   SYMBOL|next_symbol|...
parse_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "File not found: $file"
		return 1
	fi

	awk '
    BEGIN {
        in_symbol = 0
        symbol_depth = 0
        symbol_start = 0
        props_end = 0
        symbol_name = ""
        property_section_done = 0
        in_property = 0
        property_depth = 0
        delete properties
        delete prop_lines
    }

    # Detect main symbol start: (symbol "NAME" where NAME doesnt match _N_M pattern
    /^[[:space:]]*\(symbol "[^"]+"/ {
        # Extract the candidate symbol name (BSD awk compatible)
        candidate_name = ""
        pos = match($0, /"[^"]+"/)
        if (pos > 0) {
            candidate_name = substr($0, RSTART+1, RLENGTH-2)
        }

        # Check if this is a nested graphical symbol (contains _N_M pattern at end)
        # Pattern: NAME_1_1, NAME_2_1, NAME_0_0, etc.
        is_nested = (candidate_name ~ /_[0-9]+_[0-9]+$/)

        if (!in_symbol && !is_nested) {
            # Start of main symbol (not already in a symbol, and not a nested one)
            in_symbol = 1
            symbol_start = NR
            symbol_name = candidate_name
            property_section_done = 0
        }

        # Mark when we enter nested symbols (property section is done)
        if (in_symbol && is_nested) {
            property_section_done = 1
        }
    }

    # Track properties while in main symbol (before nested symbols)
    in_symbol && !property_section_done && /^[[:space:]]*\(property "[^"]+"/ {
        in_property = 1
        property_depth = 0

        # Extract property name and value (BSD awk compatible)
        # Handle multi-line by only capturing on the opening line
        if ($0 ~ /\(property "[^"]+" "[^"]*"/) {
            # Find first quoted string (property name)
            line = $0
            pos = match(line, /"[^"]+"/)
            if (pos > 0) {
                prop_name = substr(line, RSTART+1, RLENGTH-2)
                # Remove first quoted part and find second quoted string (value)
                line = substr(line, RSTART+RLENGTH)
                pos = match(line, /"[^"]*"/)
                if (pos > 0) {
                    prop_value = substr(line, RSTART+1, RLENGTH-2)
                    properties[prop_name] = prop_value
                    prop_lines[prop_name] = NR
                }
            }
        }
    }

    # Track brace depth for the entire symbol
    {
        if (in_symbol) {
            # Count braces
            line_copy = $0
            open_count = gsub(/\(/, "(", line_copy)
            close_count = gsub(/\)/, ")", line_copy)

            symbol_depth += open_count - close_count

            # Track property depth if we are in a property
            if (in_property) {
                property_depth += open_count - close_count
                # Property closed (depth returns to 0)
                if (property_depth <= 0) {
                    props_end = NR
                    in_property = 0
                    property_depth = 0
                }
            }

            # End of main symbol (back to depth 0)
            if (symbol_depth <= 0) {
                # Output symbol info
                print "SYMBOL|" symbol_name "|" symbol_start "|" props_end

                # Output properties
                for (pname in properties) {
                    print "PROP|" pname "|" properties[pname] "|" prop_lines[pname]
                }

                # Reset for next symbol
                in_symbol = 0
                symbol_depth = 0
                symbol_start = 0
                props_end = 0
                symbol_name = ""
                property_section_done = 0
                in_property = 0
                property_depth = 0
                delete properties
                delete prop_lines
            }
        }
    }

    END {
        if (in_symbol) {
            # Unclosed symbol (malformed file)
            print "ERROR|Unclosed symbol: " symbol_name "|0|0" > "/dev/stderr"
        }
    }
    ' "$file"
}

# @IMPL-PARSER-002@ (FROM: @ARCH-PARSER-001@)
# Get property value for a specific symbol
# Usage: get_property <symbols_data> <symbol_name> <property_name>
get_property() {
	local symbols_data="$1"
	local symbol_name="$2"
	local property_name="$3"

	# Extract properties for the given symbol
	echo "$symbols_data" | awk -F'|' -v sym="$symbol_name" -v prop="$property_name" '
        $1 == "SYMBOL" && $2 == sym { in_symbol = 1; next }
        $1 == "SYMBOL" && $2 != sym { in_symbol = 0 }
        in_symbol && $1 == "PROP" && $2 == prop { print $3; exit }
    '
}

# @IMPL-PARSER-003@ (FROM: @ARCH-PARSER-001@)
# Get all properties for a symbol
# Output: property_name|property_value|line_number (one per line)
get_all_properties() {
	local symbols_data="$1"
	local symbol_name="$2"

	echo "$symbols_data" | awk -F'|' -v sym="$symbol_name" '
        $1 == "SYMBOL" && $2 == sym { in_symbol = 1; next }
        $1 == "SYMBOL" && $2 != sym { in_symbol = 0 }
        in_symbol && $1 == "PROP" { print $2 "|" $3 "|" $4 }
    '
}

# @IMPL-PARSER-004@ (FROM: @ARCH-PARSER-001@)
# Get symbol metadata (start_line, props_end_line)
# Output: start_line|props_end_line
get_symbol_metadata() {
	local symbols_data="$1"
	local symbol_name="$2"

	echo "$symbols_data" | awk -F'|' -v sym="$symbol_name" '
        $1 == "SYMBOL" && $2 == sym { print $3 "|" $4; exit }
    '
}

# @IMPL-PARSER-005@ (FROM: @ARCH-PARSER-001@)
# List all symbol names in the file
list_symbols() {
	local symbols_data="$1"

	echo "$symbols_data" | awk -F'|' '
        $1 == "SYMBOL" { print $2 }
    '
}

# @IMPL-PARSER-006@ (FROM: @ARCH-PARSER-001@)
# Count symbols in the parsed data
count_symbols() {
	local symbols_data="$1"

	echo "$symbols_data" | grep -c "^SYMBOL|" || echo "0"
}

# @IMPL-PARSER-007@ (FROM: @ARCH-PARSER-001@)
# Check if a property exists for a symbol
# Returns 0 if exists, 1 if not
has_property() {
	local symbols_data="$1"
	local symbol_name="$2"
	local property_name="$3"

	local value
	value=$(get_property "$symbols_data" "$symbol_name" "$property_name")
	[[ -n "$value" ]]
}

# Parse symbols and print human-readable summary (for debugging)
print_symbols_summary() {
	local symbols_data="$1"

	local symbols
	symbols=$(list_symbols "$symbols_data")
	local count
	count=$(count_symbols "$symbols_data")

	echo "Found $count symbol(s):"
	echo

	while IFS= read -r symbol; do
		echo "Symbol: $symbol"

		local props
		props=$(get_all_properties "$symbols_data" "$symbol")
		while IFS='|' read -r prop_name prop_value prop_line; do
			printf "  %-20s = %s (line %s)\n" "$prop_name" "$prop_value" "$prop_line"
		done <<<"$props"

		echo
	done <<<"$symbols"
}
