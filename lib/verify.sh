#!/usr/bin/env bash

# verify.sh - Validation module for KiCad files
# Dispatches verification based on file type:
#   - *.kicad_sym: Symbol library files
#   - sym-lib-table: Symbol library table
#   - fp-lib-table: Footprint library table

# Source verification modules
VERIFY_TABLE_LOADED="${VERIFY_TABLE_LOADED:-}"
if [[ -z "$VERIFY_TABLE_LOADED" ]]; then
	source "$(dirname "${BASH_SOURCE[0]}")/verify_table.sh"
	VERIFY_TABLE_LOADED="1"
fi

# Global array to store verification results
declare -a VERIFY_RESULTS
declare -A VERIFY_STATS

# Initialize verification statistics
init_verify_stats() {
	VERIFY_STATS[total_symbols]=0
	VERIFY_STATS[ok_symbols]=0
	VERIFY_STATS[issue_symbols]=0
	VERIFY_STATS[missing_footprint]=0
	VERIFY_STATS[missing_datasheet]=0
	VERIFY_STATS[broken_datasheet]=0
	VERIFY_STATS[missing_digikey]=0
	VERIFY_RESULTS=()
}

# Main verification dispatcher
# Routes to appropriate verification function based on file type
# Usage: verify_file <file> [symbols_data]
verify_file() {
	local file="$1"
	local symbols_data="$2" # Only used for .kicad_sym files
	local filename=$(basename "$file")

	case "$filename" in
		*.kicad_sym)
			verify_symbol_file "$file" "$symbols_data"
			;;
		sym-lib-table)
			verify_table_file "$file" "symbol"
			;;
		fp-lib-table)
			verify_table_file "$file" "footprint"
			;;
		*)
			warn "Unknown file type: $filename (skipping verification)"
			return 1
			;;
	esac
}

# Verify all symbols in a .kicad_sym file
# Usage: verify_symbol_file <file> <symbols_data>
verify_symbol_file() {
	local file="$1"
	local symbols_data="$2"
	local filename=$(basename "$file")

	# Get list of all symbols
	local symbols=$(list_symbols "$symbols_data")

	if [[ -z "$symbols" ]]; then
		return
	fi

	info "  Verifying symbols..."

	while IFS= read -r symbol; do
		if [[ -z "$symbol" ]]; then
			continue
		fi

		verify_symbol "$file" "$symbols_data" "$symbol"
	done <<<"$symbols"

	local total=${VERIFY_STATS[total_symbols]}
	local ok=${VERIFY_STATS[ok_symbols]}
	local issues=${VERIFY_STATS[issue_symbols]}

	if [[ $issues -eq 0 ]]; then
		success "  All $total symbol(s) verified successfully"
	else
		warn "  Found issues in $issues symbol(s), $ok OK"
	fi
}

# Verify a single symbol
# Returns: 0 if OK, 1 if issues found
verify_symbol() {
	local file="$1"
	local symbols_data="$2"
	local symbol="$3"
	local filename=$(basename "$file")

	((VERIFY_STATS[total_symbols]++)) || true

	local issues=()

	# Get all properties for this symbol
	local footprint=$(get_property "$symbols_data" "$symbol" "Footprint")
	local datasheet=$(get_property "$symbols_data" "$symbol" "Datasheet")
	local value=$(get_property "$symbols_data" "$symbol" "Value")
	local reference=$(get_property "$symbols_data" "$symbol" "Reference")
	local digikey=$(get_property "$symbols_data" "$symbol" "DigiKey")

	# Check 1: Footprint exists and is not empty
	if [[ -z "$footprint" ]]; then
		issues+=("MISSING_FOOTPRINT|")
		((VERIFY_STATS[missing_footprint]++)) || true
	elif [[ "$footprint" == "" ]]; then
		issues+=("EMPTY_FOOTPRINT|")
	fi

	# Check 2: Datasheet URL validation
	if [[ -z "$datasheet" ]]; then
		issues+=("MISSING_DATASHEET|")
		((VERIFY_STATS[missing_datasheet]++)) || true
	elif [[ "$datasheet" == "" ]]; then
		issues+=("EMPTY_DATASHEET|")
	else
		# Validate the datasheet URL (with spinner for HTTP checks)
		local ds_status
		if [[ "$datasheet" =~ ^https?:// ]]; then
			start_spinner "Checking $symbol datasheet..."
			ds_status=$(validate_datasheet_url "$datasheet")
			stop_spinner

			# Print immediate feedback with color
			if [[ "$ds_status" == "OK" ]]; then
				success "  ✓ $symbol: Datasheet OK"
			elif [[ "$ds_status" == "BROKEN" ]]; then
				error "  ✗ $symbol: Datasheet broken ($datasheet)"
			else
				warn "  ⚠ $symbol: Datasheet $ds_status ($datasheet)"
			fi
		else
			ds_status=$(validate_datasheet_url "$datasheet")
		fi

		if [[ "$ds_status" == "BROKEN" ]]; then
			issues+=("DATASHEET_BROKEN|$datasheet")
			((VERIFY_STATS[broken_datasheet]++)) || true
		elif [[ "$ds_status" != "OK" ]]; then
			issues+=("DATASHEET_$ds_status|$datasheet")
		fi
	fi

	# Check 3: Value property should exist
	if [[ -z "$value" ]]; then
		issues+=("MISSING_VALUE|")
	fi

	# Check 4: Reference property should exist
	if [[ -z "$reference" ]]; then
		issues+=("MISSING_REFERENCE|")
	fi

	# Check 5: DigiKey (optional, for statistics)
	if [[ -z "$digikey" ]]; then
		((VERIFY_STATS[missing_digikey]++)) || true
	fi

	# Store result
	if [[ ${#issues[@]} -gt 0 ]]; then
		local issues_str=$(
			IFS=,
			echo "${issues[*]}"
		)
		VERIFY_RESULTS+=("$filename|$symbol|ISSUES|$issues_str")
		((VERIFY_STATS[issue_symbols]++)) || true
		return 1
	else
		VERIFY_RESULTS+=("$filename|$symbol|OK|")
		((VERIFY_STATS[ok_symbols]++)) || true
		return 0
	fi
}

# Print detailed verification report
print_verify_report() {
	local total=${VERIFY_STATS[total_symbols]}
	local ok=${VERIFY_STATS[ok_symbols]}
	local issues=${VERIFY_STATS[issue_symbols]}

	echo ""
	echo "=========================================="
	echo "Verification Report"
	echo "=========================================="
	echo "Total Symbols: $total"
	echo "  ${COLOR_GREEN}✓${COLOR_RESET} OK: $ok"
	echo "  ${COLOR_RED}✗${COLOR_RESET} Issues: $issues"
	echo ""

	if [[ $issues -gt 0 ]]; then
		echo "Issues Breakdown:"
		echo "  • Missing Footprint: ${VERIFY_STATS[missing_footprint]}"
		echo "  • Missing Datasheet: ${VERIFY_STATS[missing_datasheet]}"
		echo "  • Broken Datasheet: ${VERIFY_STATS[broken_datasheet]}"
		echo "  • Missing DigiKey: ${VERIFY_STATS[missing_digikey]}"
		echo ""

		if [[ ${#VERIFY_RESULTS[@]} -gt 0 ]]; then
			echo "Symbols with Issues:"
			echo "----------------------------------------"

			# Group by file
			local current_file=""
			for result_line in "${VERIFY_RESULTS[@]}"; do
				IFS='|' read -r file symbol status issues_str <<<"$result_line"

				# Skip OK entries
				if [[ "$status" == "OK" ]]; then
					continue
				fi

				if [[ "$file" != "$current_file" ]]; then
					if [[ -n "$current_file" ]]; then
						echo ""
					fi
					echo "${COLOR_BLUE}[$file]${COLOR_RESET}"
					current_file="$file"
				fi

				echo "  ${COLOR_RED}✗${COLOR_RESET} $symbol"

				# Parse and display issues with URLs where applicable
				IFS=',' read -ra issue_array <<<"$issues_str"
				for issue in "${issue_array[@]}"; do
					IFS='|' read -r issue_type issue_url <<<"$issue"

					if [[ -n "$issue_url" ]]; then
						# Issue with URL (datasheet problems)
						if [[ "$issue_type" == "DATASHEET_BROKEN" ]]; then
							echo "    ${COLOR_RED}• $issue_type${COLOR_RESET} ($issue_url)"
						elif [[ "$issue_type" =~ ^DATASHEET_ ]]; then
							echo "    ${COLOR_YELLOW}• $issue_type${COLOR_RESET} ($issue_url)"
						else
							echo "    ${COLOR_YELLOW}• $issue_type${COLOR_RESET}"
						fi
					else
						# Issue without URL
						echo "    ${COLOR_YELLOW}• $issue_type${COLOR_RESET}"
					fi
				done
			done
		fi
	fi

	echo "=========================================="
}

# Print verification results (called by summary module)
get_verify_results() {
	printf "%s\n" "${VERIFY_RESULTS[@]}"
}

# Clear verification results
clear_verify_results() {
	VERIFY_RESULTS=()
}
