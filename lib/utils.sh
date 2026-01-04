#!/usr/bin/env bash

# @IMPL-UTILS-001@ (FROM: @ARCH-UTILS-001@)
# utils.sh - Utility functions for kicad-shutil
# Cross-platform (Linux, macOS, Windows Git Bash)

# Color output (if terminal supports it)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
	COLOR_RED=$(tput setaf 1 2>/dev/null || echo "")
	COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo "")
	COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo "")
	COLOR_BLUE=$(tput setaf 4 2>/dev/null || echo "")
	COLOR_MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
	COLOR_CYAN=$(tput setaf 6 2>/dev/null || echo "")
	COLOR_GRAY=$(tput setaf 8 2>/dev/null || echo "")
	COLOR_BOLD=$(tput bold 2>/dev/null || echo "")
	COLOR_RESET=$(tput sgr0 2>/dev/null || echo "")
else
	COLOR_RED=""
	COLOR_GREEN=""
	COLOR_YELLOW=""
	COLOR_BLUE=""
	COLOR_MAGENTA=""
	COLOR_CYAN=""
	COLOR_GRAY=""
	COLOR_BOLD=""
	COLOR_RESET=""
fi

# Export colors for use in other scripts
export COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_MAGENTA COLOR_CYAN COLOR_GRAY COLOR_BOLD COLOR_RESET

# Logging functions
info() {
	[[ "${VERBOSE:-false}" == "true" ]] && echo "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" >&2
}

warn() {
	echo "${COLOR_YELLOW}[WARN]:${COLOR_RESET} $*" >&2
}

error() {
	echo "${COLOR_RED}[ERROR]:${COLOR_RESET} $*" >&2
}

success() {
	[[ "${VERBOSE:-false}" == "true" ]] && echo "${COLOR_GREEN}[OK]:${COLOR_RESET} $*" >&2
}

env_info() {
	[[ "${VERBOSE:-false}" == "true" ]] && echo "${COLOR_BLUE}[INFO]${COLOR_RESET}	${COLOR_GREEN}env${COLOR_RESET}	$*" >&2
}

gray_text() {
	echo "${COLOR_GRAY}$*${COLOR_RESET}"
}

# Spinner animation for long-running operations
# Usage: start_spinner "message"
#        ... do work ...
#        stop_spinner
SPINNER_PID=""

# Cleanup function to stop spinner and restore terminal
cleanup_spinner() {
	if [[ -n "$SPINNER_PID" ]]; then
		kill "$SPINNER_PID" 2>/dev/null || true
		wait "$SPINNER_PID" 2>/dev/null || true
		SPINNER_PID=""
		# Clear spinner character and newline
		printf "\b \b\n" >&2
	fi
}

start_spinner() {
	local message="${1:-Working...}"
	local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

	# Don't show spinner if not a terminal
	if [[ ! -t 2 ]]; then
		echo "$message" >&2
		return
	fi

	# Print initial message
	printf "${COLOR_BLUE}%s${COLOR_RESET} " "$message" >&2

	# Start spinner in background
	{
		local i=0
		while true; do
			local char="${spinner_chars:$i:1}"
			printf "\b%s" "$char" >&2
			i=$(((i + 1) % ${#spinner_chars}))
			sleep 0.1
		done
	} &

	SPINNER_PID=$!
	# Disable job control messages
	disown $SPINNER_PID 2>/dev/null || true
}

stop_spinner() {
	if [[ -n "$SPINNER_PID" ]]; then
		kill "$SPINNER_PID" 2>/dev/null || true
		wait "$SPINNER_PID" 2>/dev/null || true
		SPINNER_PID=""
		printf "\b \b" >&2 # Clear spinner character
		echo "" >&2
	fi
}

# @IMPL-UTILS-002@ (FROM: @ARCH-UTILS-001@)
# Check if required commands are available
check_dependencies() {
	local missing=()

	for cmd in curl awk sed grep; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		error "Missing required commands: ${missing[*]}"
		error "Please install: ${missing[*]}"
		return 1
	fi
	return 0
}

# Get file modification time (cross-platform)
# Returns Unix timestamp
get_file_mtime() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		echo "0"
		return
	fi

	# Try different stat formats for cross-platform compatibility
	if stat -c %Y "$file" 2>/dev/null; then
		# GNU stat (Linux, Git Bash)
		return
	elif stat -f %m "$file" 2>/dev/null; then
		# BSD stat (macOS)
		return
	else
		# Fallback: use current time (disables caching effectively)
		date +%s
	fi
}

# Get current Unix timestamp
get_timestamp() {
	date +%s
}

# Check if cache is still valid (15 minute TTL)
is_cache_valid() {
	local cache_file="$1"
	local ttl="${2:-900}" # Default 15 minutes

	if [[ ! -f "$cache_file" ]]; then
		return 1 # Cache doesn't exist
	fi

	local cache_time
	cache_time=$(get_file_mtime "$cache_file")
	local current_time
	current_time=$(get_timestamp)
	local age=$((current_time - cache_time))

	if [[ $age -lt $ttl ]]; then
		return 0 # Cache is valid
	else
		return 1 # Cache is expired
	fi
}

# URL encode a string (for search queries)
url_encode() {
	local string="$1"
	# Use awk for URL encoding (compatible with Git Bash on Windows)
	echo -n "$string" | awk '
        BEGIN {
            for (i = 0; i < 256; i++) {
                ord[sprintf("%c", i)] = i
            }
        }
        {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c ~ /[A-Za-z0-9._~-]/) {
                    printf "%s", c
                } else {
                    printf "%%%02X", ord[c]
                }
            }
        }
    '
}

# HTTP GET request with caching
# Usage: http_get <url> [cache_key] [ttl_seconds]
http_get() {
	local url="$1"
	local cache_key="${2:-}"
	local ttl="${3:-900}"

	local cache_file=""
	if [[ -n "$cache_key" ]]; then
		local hash
		hash=$(echo -n "$cache_key" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$cache_key")
		cache_file="$CACHE_DIR/${hash}.cache"

		# Check cache
		if is_cache_valid "$cache_file" "$ttl"; then
			cat "$cache_file"
			return 0
		fi
	fi

	# Make HTTP request
	local response
	if response=$(curl -sS -L --http1.1 --connect-timeout 10 --max-time 30 \
		-A "Mozilla/5.0 (compatible; kicad-shutil/1.0)" \
		"$url" 2>&1); then

		# Save to cache if cache_key provided
		if [[ -n "$cache_file" ]]; then
			echo "$response" >"$cache_file"
		fi

		echo "$response"
		return 0
	else
		error "HTTP request failed: $url"
		return 1
	fi
}

# HTTP request to check if URL is valid
# Returns HTTP status code
http_check_url() {
	local url="$1"

	local http_code
	# Use GET request with browser-like headers
	# Download only first 1KB to minimize bandwidth
	# Some servers (like Analog Devices) require realistic browser headers
	http_code=$(curl -s -L \
		--connect-timeout 20 --max-time 60 \
		-A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
		-H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
		-H "Accept-Language: en-US,en;q=0.5" \
		-H "Accept-Encoding: gzip, deflate, br" \
		-H "DNT: 1" \
		-H "Connection: keep-alive" \
		-H "Upgrade-Insecure-Requests: 1" \
		-H "Sec-Fetch-Dest: document" \
		-H "Sec-Fetch-Mode: navigate" \
		-H "Sec-Fetch-Site: none" \
		-r 0-1023 \
		-o /dev/null -w "%{http_code}" \
		"$url" 2>/dev/null)

	# If curl failed or no status code found, return 000
	if [[ -z "$http_code" ]]; then
		http_code="000"
	fi

	# 206 (Partial Content) and 416 (Range Not Satisfiable) are also successes
	# Some servers return 416 for small files, which means the file exists
	if [[ "$http_code" == "206" ]] || [[ "$http_code" == "416" ]]; then
		http_code="200"
	fi

	echo "$http_code"
}

# Download file with retry logic
# Usage: download_file <url> <output_path> [max_attempts]
download_file() {
	local url="$1"
	local output="$2"
	local max_attempts="${3:-3}"

	# Create output directory
	local output_dir
	output_dir=$(dirname "$output")
	mkdir -p "$output_dir"

	for attempt in $(seq 1 "$max_attempts"); do
		# Use --http1.1 to avoid HTTP/2 issues with some servers (e.g., TDK)
		# Send browser-like headers to avoid bot detection (e.g., Analog Devices)
		# --connect-timeout: max time to establish connection
		# --max-time: max time for entire operation
		# -s: silent mode (no progress bar)
		# -S: show errors even in silent mode
		# -L: follow redirects
		# Note: Removed -f to allow downloads even with HTTP errors (some servers redirect with 3xx)
		if curl -sSL \
			--http1.1 \
			--connect-timeout 10 \
			--max-time 60 \
			-H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
			-H "Accept-Language: en-US,en;q=0.5" \
			-H "Accept-Encoding: gzip, deflate" \
			-H "DNT: 1" \
			-H "Connection: keep-alive" \
			-H "Upgrade-Insecure-Requests: 1" \
			-A "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0" \
			-o "$output" "$url" 2>/dev/null; then
			# Verify file was actually downloaded and is not empty
			if [[ -f "$output" ]] && [[ -s "$output" ]]; then
				return 0
			fi
		fi

		# Clean up partial or failed download
		rm -f "$output"

		if [[ $attempt -lt $max_attempts ]]; then
			sleep $((attempt * 2)) # Exponential backoff
		fi
	done

	return 1
}

# Interactive user selection from a list
# @IMPL-UTILS-003@ (FROM: @ARCH-UTILS-001@)
# Usage: select_from_list <prompt> <item1> <item2> ...
# Returns: selected item or empty string if skipped
select_from_list() {
	local prompt="$1"
	shift
	local items=("$@")

	if [[ ${#items[@]} -eq 0 ]]; then
		return 1
	fi

	if [[ ${#items[@]} -eq 1 ]]; then
		# Auto-select if only one option
		echo "${items[0]}"
		return 0
	fi

	echo "" >&2
	echo "$prompt" >&2
	echo "========================================" >&2

	local i=1
	for item in "${items[@]}"; do
		printf "%2d) %s\n" "$i" "$item" >&2
		((i += 1))
	done

	echo "========================================" >&2
	echo " s) Skip this item" >&2
	echo " q) Quit" >&2
	echo "" >&2

	while true; do
		read -r -p "Select (1-${#items[@]}, s, q): " choice </dev/tty

		case "$choice" in
			q | Q)
				error "User quit"
				return 1
				;;
			s | S)
				return 2 # Skip signal
				;;
			[0-9]*)
				if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#items[@]} ]]; then
					echo "${items[$((choice - 1))]}"
					return 0
				else
					warn "Invalid selection. Try again." >&2
				fi
				;;
			*)
				warn "Invalid input. Try again." >&2
				;;
		esac
	done
}

# Create backup of file
backup_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		error "Cannot backup non-existent file: $file"
		return 1
	fi

	cp "$file" "$file.bak"
	return 0
}

# Restore file from backup
restore_from_backup() {
	local file="$1"

	if [[ -f "$file.bak" ]]; then
		mv "$file.bak" "$file"
		return 0
	else
		warn "No backup found for: $file"
		return 1
	fi
}

# Remove backup file
remove_backup() {
	local file="$1"

	if [[ -f "$file.bak" ]]; then
		rm "$file.bak"
	fi
}

# Atomic file write: write to temp file, then move
# Usage: atomic_write <file> <content>
atomic_write() {
	local file="$1"
	local content="$2"

	local temp_file="${file}.tmp.$$"

	if echo "$content" >"$temp_file"; then
		mv "$temp_file" "$file"
		return 0
	else
		rm -f "$temp_file"
		return 1
	fi
}

# Extract filename without extension
get_basename_no_ext() {
	local file="$1"
	local basename
	basename=$(basename "$file")
	echo "${basename%.*}"
}

# Validate a datasheet URL
# Returns: OK, BROKEN, REDIRECT, TIMEOUT, HTTP_XXX
validate_datasheet_url() {
	local url="$1"

	# Skip non-HTTP URLs (local files, etc.)
	if [[ ! "$url" =~ ^https?:// ]]; then
		echo "OK"
		return 0
	fi

	# Check HTTP status
	local http_code
	http_code=$(http_check_url "$url")

	case "$http_code" in
		200)
			echo "OK"
			;;
		404 | 410)
			echo "BROKEN"
			;;
		301 | 302 | 303 | 307 | 308)
			echo "REDIRECT"
			;;
		000)
			echo "TIMEOUT"
			;;
		*)
			echo "HTTP_$http_code"
			;;
	esac
}

# @IMPL-UTILS-004@ (FROM: @ARCH-UTILS-001@)
# Initialize utilities (called from main script)
init_utils() {
	if ! check_dependencies; then
		return 1
	fi

	# Setup signal handlers to cleanup spinner on interrupt
	# Note: EXIT trap removed to avoid issues with subshells in command substitutions
	trap cleanup_spinner INT TERM
	return 0
}
