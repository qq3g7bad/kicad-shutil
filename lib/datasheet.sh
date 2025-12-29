#!/usr/bin/env bash

# datasheet.sh - Datasheet download module for kicad-shutil
# Bulk download datasheets from symbol Datasheet properties

# Global statistics (bash 3.2 compatible - no associative arrays)
DATASHEET_STATS_TOTAL=0
DATASHEET_STATS_SUCCESS=0
DATASHEET_STATS_FAILED=0
DATASHEET_STATS_MISSING=0
DATASHEET_STATS_SKIPPED=0

# Initialize datasheet statistics
init_datasheet_stats() {
	DATASHEET_STATS_TOTAL=0
	DATASHEET_STATS_SUCCESS=0
	DATASHEET_STATS_FAILED=0
	DATASHEET_STATS_MISSING=0
	DATASHEET_STATS_SKIPPED=0
}

# Download datasheets for all symbols in a file
# Usage: download_datasheets <file> <symbols_data> <category>
download_datasheets() {
	local file="$1"
	local symbols_data="$2"
	local category="$3"

	# Initialize stats if not done
	if [[ -z "${DATASHEET_STATS_TOTAL:-}" ]]; then
		init_datasheet_stats
	fi

	info "  Downloading datasheets..."

	# Get all symbols
	local symbols
	symbols=$(list_symbols "$symbols_data")

	if [[ -z "$symbols" ]]; then
		return
	fi

	# Create output directory
	local base_dir="${DATASHEET_DIR:-./datasheets}"
	local output_dir="$base_dir/$category"
	mkdir -p "$output_dir"

	local count=0
	while IFS= read -r symbol; do
		if [[ -z "$symbol" ]]; then
			continue
		fi

		download_symbol_datasheet "$file" "$symbols_data" "$symbol" "$output_dir"
		((count++)) || true
	done <<<"$symbols"

	info "  Processed $count datasheet(s) for $category"
}

# Download datasheet for a single symbol
download_symbol_datasheet() {
	local file="$1"
	local symbols_data="$2"
	local symbol="$3"
	local output_dir="$4"

	((DATASHEET_STATS_TOTAL++)) || true

	# Get datasheet URL
	local datasheet
	datasheet=$(get_property "$symbols_data" "$symbol" "Datasheet")

	if [[ -z "$datasheet" ]]; then
		warn "    [$symbol] No datasheet URL"
		((DATASHEET_STATS_MISSING++)) || true
		return 1
	fi

	# Skip non-HTTP URLs
	if [[ ! "$datasheet" =~ ^https?:// ]]; then
		info "    [$symbol] Skipping non-HTTP URL: $datasheet"
		((DATASHEET_STATS_SKIPPED++)) || true
		return 0
	fi

	# Determine output filename
	local ext
	ext=$(get_file_extension_from_url "$datasheet")
	if [[ -z "$ext" ]]; then
		ext="pdf" # Default to PDF
	fi
	local output_file="$output_dir/${symbol}.${ext}"

	# Check if already downloaded
	if [[ -f "$output_file" ]]; then
		info "    [$symbol] Already exists, skipping"
		((DATASHEET_STATS_SKIPPED++)) || true
		return 0
	fi

	# Download with retry
	start_spinner "    [$symbol] Downloading from $datasheet"
	if download_file "$datasheet" "$output_file" 3; then
		stop_spinner
		success "    [$symbol] Downloaded successfully"
		((DATASHEET_STATS_SUCCESS++)) || true
		return 0
	else
		stop_spinner
		error "    [$symbol] Download failed: $datasheet"
		((DATASHEET_STATS_FAILED++)) || true
		return 1
	fi
}

# Get file extension from URL
get_file_extension_from_url() {
	local url="$1"

	# Remove query string and fragment
	local path="${url%%\?*}"
	path="${path%%\#*}"

	# Extract extension
	if [[ "$path" =~ \.([a-zA-Z0-9]+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
	else
		echo ""
	fi
}

# Print datasheet download summary
print_datasheet_summary() {
	local total=${DATASHEET_STATS_TOTAL:-0}
	local success=${DATASHEET_STATS_SUCCESS:-0}
	local failed=${DATASHEET_STATS_FAILED:-0}
	local missing=${DATASHEET_STATS_MISSING:-0}
	local skipped=${DATASHEET_STATS_SKIPPED:-0}

	if [[ $total -eq 0 ]]; then
		return
	fi

	echo ""
	echo "=========================================="
	echo "Datasheet Download Summary"
	echo "=========================================="
	echo "Total symbols: $total"
	echo "  ${COLOR_GREEN}✓${COLOR_RESET} Downloaded: $success"
	echo "  ${COLOR_RED}✗${COLOR_RESET} Failed: $failed"
	echo "  ${COLOR_YELLOW}•${COLOR_RESET} Missing URL: $missing"
	echo "  ${COLOR_BLUE}-${COLOR_RESET} Skipped: $skipped"
	echo "=========================================="
}
