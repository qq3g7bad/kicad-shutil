#!/usr/bin/env bash
# lib/pcb_export.sh - PCB manufacturing output generation module
#
# Wraps kicad-cli commands for generating manufacturing output files:
# - Gerber files (all layers)
# - Drill files (Excellon format)
# - Position files (Pick & Place, CSV format)
# - Netlist (KiCad XML format)

# Prevent multiple sourcing
if [[ -n "${_KICAD_SHUTIL_PCB_EXPORT_SH_:-}" ]]; then
	return 0
fi
readonly _KICAD_SHUTIL_PCB_EXPORT_SH_=1

# Statistics tracking (individual variables for Bash 3.x / macOS compatibility)
PCB_EXPORT_STATS_gerbers=0
PCB_EXPORT_STATS_drill=0
PCB_EXPORT_STATS_position=0
PCB_EXPORT_STATS_netlist=0
PCB_EXPORT_STATS_total=0
PCB_EXPORT_STATS_failed=0

# Initialize statistics
init_pcb_export_stats() {
	PCB_EXPORT_STATS_gerbers=0
	PCB_EXPORT_STATS_drill=0
	PCB_EXPORT_STATS_position=0
	PCB_EXPORT_STATS_netlist=0
	PCB_EXPORT_STATS_total=0
	PCB_EXPORT_STATS_failed=0
}

# @IMPL-PCB-EXPORT-001@ (FROM: @ARCH-PCB-001@)
# Check if kicad-cli is available and meets version requirements
# Returns: 0 if available, 1 otherwise
check_kicad_cli() {
	local version_output version_major

	if ! command -v kicad-cli &>/dev/null; then
		error "kicad-cli not found in PATH"
		error "Please install KiCad 7.0 or later"
		error "Installation: https://www.kicad.org/download/"
		return 1
	fi

	# Get version
	version_output=$(kicad-cli version 2>&1 || echo "unknown")

	# Try to extract major version number
	if [[ "$version_output" =~ ([0-9]+)\. ]]; then
		version_major="${BASH_REMATCH[1]}"

		if [[ "$version_major" -lt 7 ]]; then
			warn "KiCad version $version_major detected (older than 7.0)"
			warn "Some features may not work correctly"
			warn "Please upgrade to KiCad 7.0 or later"
		else
			info "Found kicad-cli version $version_major"
		fi
	else
		warn "Could not determine kicad-cli version"
		info "kicad-cli found at: $(command -v kicad-cli)"
	fi

	return 0
}

# @IMPL-PCB-EXPORT-002@ (FROM: @ARCH-PCB-001@)
# Resolve input files from various formats
# Args: input_file
# Sets global variables: PCB_FILE, SCH_FILE
# Returns: 0 on success, 1 on failure
resolve_input_files() {
	local input_file="$1"
	local base_name

	# Verify input file exists
	if [[ ! -f "$input_file" ]]; then
		error "Input file not found: $input_file"
		return 1
	fi

	base_name=$(basename "$input_file")

	# Determine file type and resolve PCB/SCH files
	case "$base_name" in
		*.kicad_pcb)
			PCB_FILE="$input_file"
			# Look for matching schematic
			local sch_candidate="${input_file%.kicad_pcb}.kicad_sch"
			if [[ -f "$sch_candidate" ]]; then
				SCH_FILE="$sch_candidate"
				info "Found schematic: $(basename "$SCH_FILE")"
			else
				warn "Schematic file not found: $(basename "$sch_candidate")"
				warn "Netlist generation will be skipped"
				SCH_FILE=""
			fi
			;;

		*.kicad_pro)
			# Find matching PCB and SCH files
			local project_base="${input_file%.kicad_pro}"
			PCB_FILE="${project_base}.kicad_pcb"
			SCH_FILE="${project_base}.kicad_sch"

			if [[ ! -f "$PCB_FILE" ]]; then
				error "PCB file not found: $(basename "$PCB_FILE")"
				return 1
			fi

			if [[ ! -f "$SCH_FILE" ]]; then
				warn "Schematic file not found: $(basename "$SCH_FILE")"
				warn "Netlist generation will be skipped"
				SCH_FILE=""
			else
				info "Found schematic: $(basename "$SCH_FILE")"
			fi

			info "Found PCB: $(basename "$PCB_FILE")"
			;;

		*.kicad_sch)
			SCH_FILE="$input_file"
			# Look for matching PCB
			local pcb_candidate="${input_file%.kicad_sch}.kicad_pcb"
			if [[ -f "$pcb_candidate" ]]; then
				PCB_FILE="$pcb_candidate"
				info "Found PCB: $(basename "$PCB_FILE")"
			else
				error "PCB file not found: $(basename "$pcb_candidate")"
				error "PCB file is required for manufacturing output"
				return 1
			fi
			;;

		*)
			error "Unsupported file type: $base_name"
			error "Supported types: .kicad_pcb, .kicad_pro, .kicad_sch"
			return 1
			;;
	esac

	return 0
}

# @IMPL-PCB-EXPORT-003@ (FROM: @ARCH-PCB-001@)
# Export Gerber files
# Args: pcb_file output_dir
# Returns: 0 on success, 1 on failure
export_gerbers() {
	local pcb_file="$1"
	local output_dir="$2"
	local gerber_dir="${output_dir}/gerbers"
	local log_file="${output_dir}/gerbers.log"

	info "Generating Gerber files..."

	# Create output directory
	mkdir -p "$gerber_dir" || {
		error "Failed to create directory: $gerber_dir"
		return 1
	}

	# Run kicad-cli
	if kicad-cli pcb export gerbers --output "$gerber_dir" "$pcb_file" >"$log_file" 2>&1; then
		PCB_EXPORT_STATS_gerbers=1
		PCB_EXPORT_STATS_total=$((PCB_EXPORT_STATS_total + 1))
		success "Gerbers exported to: gerbers/"
		return 0
	else
		PCB_EXPORT_STATS_failed=$((PCB_EXPORT_STATS_failed + 1))
		error "Failed to export Gerbers (see $log_file)"
		return 1
	fi
}

# @IMPL-PCB-EXPORT-004@ (FROM: @ARCH-PCB-001@)
# Export drill files
# Args: pcb_file output_dir
# Returns: 0 on success, 1 on failure
export_drill() {
	local pcb_file="$1"
	local output_dir="$2"
	local drill_dir="${output_dir}/drill"
	local log_file="${output_dir}/drill.log"

	info "Generating drill files..."

	# Create output directory
	mkdir -p "$drill_dir" || {
		error "Failed to create directory: $drill_dir"
		return 1
	}

	# Run kicad-cli
	if kicad-cli pcb export drill --format excellon --output "$drill_dir" "$pcb_file" >"$log_file" 2>&1; then
		PCB_EXPORT_STATS_drill=1
		PCB_EXPORT_STATS_total=$((PCB_EXPORT_STATS_total + 1))
		success "Drill files exported to: drill/"
		return 0
	else
		PCB_EXPORT_STATS_failed=$((PCB_EXPORT_STATS_failed + 1))
		error "Failed to export drill files (see $log_file)"
		return 1
	fi
}

# @IMPL-PCB-EXPORT-005@ (FROM: @ARCH-PCB-001@)
# Export position files (Pick & Place)
# Args: pcb_file output_dir
# Returns: 0 on success, 1 on failure
export_position() {
	local pcb_file="$1"
	local output_dir="$2"
	local position_dir="${output_dir}/position"
	local log_file="${output_dir}/position.log"
	local failed=0

	info "Generating position files..."

	# Create output directory
	mkdir -p "$position_dir" || {
		error "Failed to create directory: $position_dir"
		return 1
	}

	# Export front side
	if ! kicad-cli pcb export pos --format csv --units mm --side front \
		--output "${position_dir}/front.pos" "$pcb_file" >>"$log_file" 2>&1; then
		error "Failed to export front position file (see $log_file)"
		failed=1
	fi

	# Export back side
	if ! kicad-cli pcb export pos --format csv --units mm --side back \
		--output "${position_dir}/back.pos" "$pcb_file" >>"$log_file" 2>&1; then
		error "Failed to export back position file (see $log_file)"
		failed=1
	fi

	if [[ $failed -eq 0 ]]; then
		PCB_EXPORT_STATS_position=1
		PCB_EXPORT_STATS_total=$((PCB_EXPORT_STATS_total + 1))
		success "Position files exported to: position/"
		return 0
	else
		PCB_EXPORT_STATS_failed=$((PCB_EXPORT_STATS_failed + 1))
		return 1
	fi
}

# @IMPL-PCB-EXPORT-006@ (FROM: @ARCH-PCB-001@)
# Export netlist
# Args: sch_file output_dir
# Returns: 0 on success, 1 on failure
export_netlist() {
	local sch_file="$1"
	local output_dir="$2"
	local netlist_dir="${output_dir}/netlist"
	local log_file="${output_dir}/netlist.log"

	# Skip if no schematic file
	if [[ -z "$sch_file" ]]; then
		warn "Skipping netlist generation (no schematic file)"
		return 0
	fi

	info "Generating netlist..."

	# Create output directory
	mkdir -p "$netlist_dir" || {
		error "Failed to create directory: $netlist_dir"
		return 1
	}

	# Run kicad-cli
	if kicad-cli sch export netlist --format kicadxml \
		--output "${netlist_dir}/netlist.xml" "$sch_file" >"$log_file" 2>&1; then
		PCB_EXPORT_STATS_netlist=1
		PCB_EXPORT_STATS_total=$((PCB_EXPORT_STATS_total + 1))
		success "Netlist exported to: netlist/"
		return 0
	else
		PCB_EXPORT_STATS_failed=$((PCB_EXPORT_STATS_failed + 1))
		error "Failed to export netlist (see $log_file)"
		return 1
	fi
}

# Print export summary
print_pcb_export_summary() {
	local output_dir="$1"

	echo
	info "Manufacturing Output Summary:"
	echo "  Output directory: $output_dir"
	echo

	# Show results for each export type
	if [[ $PCB_EXPORT_STATS_gerbers -eq 1 ]]; then
		echo "  ✓ Gerbers:  gerbers/"
	else
		echo "  ✗ Gerbers:  FAILED"
	fi

	if [[ $PCB_EXPORT_STATS_drill -eq 1 ]]; then
		echo "  ✓ Drill:    drill/"
	else
		echo "  ✗ Drill:    FAILED"
	fi

	if [[ $PCB_EXPORT_STATS_position -eq 1 ]]; then
		echo "  ✓ Position: position/"
	else
		echo "  ✗ Position: FAILED"
	fi

	if [[ $PCB_EXPORT_STATS_netlist -eq 1 ]]; then
		echo "  ✓ Netlist:  netlist/"
	elif [[ -z "${SCH_FILE:-}" ]]; then
		echo "  - Netlist:  SKIPPED (no schematic)"
	else
		echo "  ✗ Netlist:  FAILED"
	fi

	echo
	echo "  Total: $PCB_EXPORT_STATS_total successful, $PCB_EXPORT_STATS_failed failed"
	echo
}

# @IMPL-PCB-EXPORT-007@ (FROM: @ARCH-PCB-001@)
# Main entry point for gerber-output command
# Args: input_file output_dir
# Returns: 0 if all succeeded, 1 if any failed
export_gerber_output() {
	local input_file="$1"
	local output_dir="$2"
	local pcb_dir

	# Initialize statistics
	init_pcb_export_stats

	# Check for kicad-cli
	check_kicad_cli || return 1

	# Resolve input files (sets PCB_FILE and SCH_FILE globals)
	resolve_input_files "$input_file" || return 1

	# Determine output directory
	if [[ -z "$output_dir" ]]; then
		pcb_dir=$(dirname "$PCB_FILE")
		output_dir="${pcb_dir}/manufacturing"
	fi

	# Create output directory
	mkdir -p "$output_dir" || {
		error "Failed to create output directory: $output_dir"
		return 1
	}

	# Convert to absolute path for display
	output_dir=$(cd "$output_dir" && pwd)

	info "Generating manufacturing output for: $(basename "$PCB_FILE")"
	info "Output directory: $output_dir"
	echo

	# Run exports (continue on failures for best-effort approach)
	export_gerbers "$PCB_FILE" "$output_dir"
	export_drill "$PCB_FILE" "$output_dir"
	export_position "$PCB_FILE" "$output_dir"
	export_netlist "$SCH_FILE" "$output_dir"

	# Print summary
	print_pcb_export_summary "$output_dir"

	# Return error if any export failed
	if [[ $PCB_EXPORT_STATS_failed -gt 0 ]]; then
		return 1
	fi

	return 0
}
