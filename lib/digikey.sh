#!/usr/bin/env bash

# digikey.sh - DigiKey API integration module for kicad-shutil
# Search and retrieve DigiKey part numbers and URLs using official API
#
# API Documentation: https://developer.digikey.com/
# Required: DigiKey API credentials (Client ID and Client Secret)
#
# Configuration:
#   - Environment variables: DIGIKEY_CLIENT_ID, DIGIKEY_CLIENT_SECRET
#   - Config file: ~/.kicad-shutil/config

# DigiKey API endpoints
DIGIKEY_API_BASE="https://api.digikey.com"
DIGIKEY_TOKEN_URL="https://api.digikey.com/v1/oauth2/token"
DIGIKEY_SEARCH_URL="https://api.digikey.com/products/v4/search/keyword"

# API token cache
DIGIKEY_ACCESS_TOKEN=""
DIGIKEY_TOKEN_EXPIRY=0

# Process DigiKey information for all symbols in a file
# Usage: process_digikey <file> <symbols_data>
process_digikey() {
  local file="$1"
  local symbols_data="$2"
  local filename=$(basename "$file")

  info "  Processing DigiKey information..."

  # Get all symbols
  local symbols=$(list_symbols "$symbols_data")

  if [[ -z "$symbols" ]]; then
    return
  fi

  local count=0
  local updated=0
  local skipped=0

  while IFS= read -r symbol; do
    if [[ -z "$symbol" ]]; then
      continue
    fi

    ((count++)) || true

    # Check if DigiKey info already exists
    local existing_dk=$(get_property "$symbols_data" "$symbol" "DigiKey")
    local existing_url=$(get_property "$symbols_data" "$symbol" "DigiKey URL")

    if [[ -n "$existing_dk" ]] && [[ -n "$existing_url" ]]; then
      info "    [$symbol] DigiKey info already exists, skipping"
      ((skipped++)) || true
      continue
    fi

    # Get part name from Value property
    local part_name=$(get_property "$symbols_data" "$symbol" "Value")
    if [[ -z "$part_name" ]]; then
      warn "    [$symbol] No Value property, skipping"
      ((skipped++)) || true
      continue
    fi

    # Search DigiKey
    start_spinner "    [$symbol] Searching DigiKey for: $part_name"

    local candidates=$(search_digikey_part "$part_name")

    stop_spinner

    if [[ -z "$candidates" ]]; then
      warn "    [$symbol] No DigiKey results found"
      ((skipped++)) || true
      continue
    fi

    # Parse candidates
    local candidate_count=$(echo "$candidates" | wc -l)

    if [[ $candidate_count -eq 1 ]]; then
      # Single match - auto-select
      local dk_part=$(echo "$candidates" | cut -d'|' -f1)
      local dk_url=$(echo "$candidates" | cut -d'|' -f2)
      local dk_desc=$(echo "$candidates" | cut -d'|' -f3)
      local dk_detailed_desc=$(echo "$candidates" | cut -d'|' -f4)
      local dk_price=$(echo "$candidates" | cut -d'|' -f5)
      local dk_moq=$(echo "$candidates" | cut -d'|' -f6)

      info "    [$symbol] Found: $dk_part (\$$dk_price/ea, MOQ: $dk_moq)"

      # Add properties
      if add_digikey_properties "$file" "$symbol" "$dk_part" "$dk_url" "$dk_desc" "$dk_detailed_desc" "$dk_price" "$dk_moq"; then
        success "    [$symbol] DigiKey info added with pricing"
        ((updated++)) || true
      fi
    else
      # Multiple matches - interactive selection
      if [[ "${OPT_AUTO_SKIP:-false}" == "true" ]]; then
        warn "    [$symbol] Multiple matches, skipping (auto-skip mode)"
        ((skipped++)) || true
        continue
      fi

      # Present options to user
      select_digikey_candidate "$file" "$symbol" "$candidates"
      local result=$?

      if [[ $result -eq 0 ]]; then
        ((updated++)) || true
      else
        ((skipped++)) || true
      fi
    fi

  done <<<"$symbols"

  echo ""
  info "  DigiKey processing complete: $count symbols, $updated updated, $skipped skipped"
}

# Load DigiKey API credentials
# Priority: 1. Environment variables, 2. Config file
load_digikey_credentials() {
  # Check environment variables first
  if [[ -n "${DIGIKEY_CLIENT_ID:-}" ]] && [[ -n "${DIGIKEY_CLIENT_SECRET:-}" ]]; then
    return 0
  fi

  # Try config file
  local config_file="$HOME/.kicad-shutil/config"
  if [[ -f "$config_file" ]]; then
    # Source config file
    source "$config_file"

    if [[ -n "${DIGIKEY_CLIENT_ID:-}" ]] && [[ -n "${DIGIKEY_CLIENT_SECRET:-}" ]]; then
      return 0
    fi
  fi

  # Credentials not found
  error "DigiKey API credentials not found"
  error "Please set DIGIKEY_CLIENT_ID and DIGIKEY_CLIENT_SECRET environment variables"
  error "Or create config file: $config_file"
  error ""
  error "Get API credentials at: https://developer.digikey.com/"
  return 1
}

# Get DigiKey API access token (OAuth 2.0 Client Credentials)
get_digikey_token() {
  # Check if we have a valid cached token
  local current_time=$(date +%s)
  if [[ -n "$DIGIKEY_ACCESS_TOKEN" ]] && [[ $current_time -lt $DIGIKEY_TOKEN_EXPIRY ]]; then
    echo "$DIGIKEY_ACCESS_TOKEN"
    return 0
  fi

  # Load credentials
  if ! load_digikey_credentials; then
    return 1
  fi

  # Request new token
  start_spinner "Obtaining DigiKey API token"
  local response=$(curl -sS -X POST "$DIGIKEY_TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${DIGIKEY_CLIENT_ID}" \
    -d "client_secret=${DIGIKEY_CLIENT_SECRET}" \
    -d "grant_type=client_credentials" \
    2>&1)
  stop_spinner

  if [[ $? -ne 0 ]]; then
    error "Failed to obtain DigiKey API token"
    return 1
  fi

  # Parse token and expiry from JSON response (using awk instead of jq)
  local token=$(echo "$response" | awk -F'"' '/"access_token"/ { for(i=1; i<=NF; i++) if($i=="access_token") { print $(i+2); exit } }')
  local expires_in=$(echo "$response" | awk -F'[,:}]' '/"expires_in"/ { for(i=1; i<=NF; i++) if($i ~ /expires_in/) { gsub(/[^0-9]/, "", $(i+1)); print $(i+1); exit } }')
  
  # Set default if parsing fails
  expires_in=${expires_in:-3600}

  if [[ -z "$token" ]]; then
    error "Failed to parse DigiKey API token"
    echo "Response: $response" >&2
    return 1
  fi

  # Cache token
  DIGIKEY_ACCESS_TOKEN="$token"
  DIGIKEY_TOKEN_EXPIRY=$((current_time + expires_in - 60)) # Subtract 60s for safety

  echo "$token"
  return 0
}

# Search DigiKey for a part using API
# Returns: part_number|url|description (one per line)
search_digikey_part() {
  local part="$1"

  # Get API token
  local token=$(get_digikey_token)
  if [[ -z "$token" ]]; then
    return 1
  fi

  # Check cache first
  local cache_key="digikey_api_search_$part"
  local cache_file="$CACHE_DIR/$(echo -n "$cache_key" | md5sum | cut -d' ' -f1).cache"

  if is_cache_valid "$cache_file" 3600; then
    cat "$cache_file"
    return 0
  fi

  # Prepare API request (JSON constructed with bash instead of jq)
  local request_body=$(cat <<EOF
{
  "Keywords": "$part",
  "RecordCount": 10,
  "RecordStartPosition": 0,
  "Filters": {},
  "Sort": {
    "SortOption": "None",
    "Direction": "Ascending"
  },
  "RequestedQuantity": 1
}
EOF
)

  # Make API request
  start_spinner "Querying DigiKey API"
  local response=$(curl -sS -X POST "$DIGIKEY_SEARCH_URL" \
    -H "Authorization: Bearer $token" \
    -H "X-DIGIKEY-Client-Id: ${DIGIKEY_CLIENT_ID}" \
    -H "Content-Type: application/json" \
    -H "X-DIGIKEY-Locale-Site: US" \
    -H "X-DIGIKEY-Locale-Language: en" \
    -H "X-DIGIKEY-Locale-Currency: USD" \
    -d "$request_body" \
    2>&1)
  stop_spinner

  if [[ $? -ne 0 ]]; then
    warn "DigiKey API request failed"
    return 1
  fi

  # Parse response
  parse_digikey_api_response "$response" >"$cache_file"
  cat "$cache_file"
}

# Parse DigiKey API JSON response
# Output: dkpn|url|description|detailed_desc|price|moq|package (one per line for each variation)
parse_digikey_api_response() {
  local json="$1"

  # Simple JSON parser using awk (no jq dependency)
  # Extracts DigiKey API response fields
  
  echo "$json" | awk '
    BEGIN {
      RS = ""
      FS = ""
    }
    {
      # Extract all products from the JSON
      products_count = 0
      
      # Split by ProductVariations to process each variation
      num_variations = split($0, variations, /"ProductVariations"/)
      
      for (v = 2; v <= num_variations; v++) {
        variation = variations[v]
        
        # Find the product-level info before this variation
        # Go back to find ProductUrl, ProductDescription, DetailedDescription
        for (p = v-1; p >= 1; p--) {
          prev = variations[p]
          
          # Extract ProductUrl
          if (match(prev, /"ProductUrl"[[:space:]]*:[[:space:]]*"([^"]*)"/, arr)) {
            product_url = arr[1]
          }
          
          # Extract ProductDescription
          if (match(prev, /"ProductDescription"[[:space:]]*:[[:space:]]*"([^"]*)"/, arr)) {
            product_desc = arr[1]
          }
          
          # Extract DetailedDescription
          if (match(prev, /"DetailedDescription"[[:space:]]*:[[:space:]]*"([^"]*)"/, arr)) {
            detailed_desc = arr[1]
          }
          
          if (product_url != "") break
        }
        
        # Extract variation-level fields
        if (match(variation, /"DigiKeyProductNumber"[[:space:]]*:[[:space:]]*"([^"]*)"/, arr)) {
          dkpn = arr[1]
        }
        
        if (match(variation, /"UnitPrice"[[:space:]]*:[[:space:]]*([0-9.]+)/, arr)) {
          price = arr[1]
        }
        
        if (match(variation, /"MinimumOrderQuantity"[[:space:]]*:[[:space:]]*([0-9]+)/, arr)) {
          moq = arr[1]
        } else {
          moq = "1"
        }
        
        # Extract package type if present
        pkg = "Unknown"
        if (match(variation, /"PackageType"[[:space:]]*:[[:space:]]*\{[^}]*"Name"[[:space:]]*:[[:space:]]*"([^"]*)"/, arr)) {
          pkg = arr[1]
        }
        
        # Output if we have required fields
        if (dkpn != "" && price != "") {
          if (product_url == "") product_url = ""
          if (product_desc == "") product_desc = ""
          if (detailed_desc == "") detailed_desc = ""
          
          print dkpn "|" product_url "|" product_desc "|" detailed_desc "|" price "|" moq "|" pkg
          
          # Reset for next variation
          dkpn = ""
          price = ""
          moq = ""
          pkg = ""
        }
        
        # Reset product-level fields for next product
        product_url = ""
        product_desc = ""
        detailed_desc = ""
      }
    }
  '
}

# Interactive selection of DigiKey candidate
select_digikey_candidate() {
  local file="$1"
  local symbol="$2"
  local candidates="$3"

  # Convert to array with descriptions, price, MOQ, and package
  local candidate_array=()
  while IFS='|' read -r part_num url description detailed_desc price moq package; do
    # Format: "PART-NUM - Description ($Price/ea, MOQ: X, Package)"
    candidate_array+=("$part_num - $description (\$$price/ea, MOQ: $moq, $package)")
  done <<<"$candidates"

  # Present options
  echo ""
  local selection=$(select_from_list "Select DigiKey part for [$symbol]:" "${candidate_array[@]}")
  local result=$?

  if [[ $result -eq 0 ]] && [[ -n "$selection" ]]; then
    # Extract just the part number (before " - ")
    local part_num="${selection%% - *}"

    # Find the corresponding line
    local selected_line=$(echo "$candidates" | grep "^${part_num}|")
    local selected_url=$(echo "$selected_line" | cut -d'|' -f2)
    local selected_desc=$(echo "$selected_line" | cut -d'|' -f3)
    local selected_detailed_desc=$(echo "$selected_line" | cut -d'|' -f4)
    local selected_price=$(echo "$selected_line" | cut -d'|' -f5)
    local selected_moq=$(echo "$selected_line" | cut -d'|' -f6)

    if add_digikey_properties "$file" "$symbol" "$part_num" "$selected_url" "$selected_desc" "$selected_detailed_desc" "$selected_price" "$selected_moq"; then
      success "    [$symbol] DigiKey info added: $part_num (\$$selected_price/ea)"
      return 0
    fi
  fi

  return 1
}

# Add DigiKey properties to a symbol
add_digikey_properties() {
  local file="$1"
  local symbol="$2"
  local dk_part="$3"
  local dk_url="$4"
  local dk_desc="${5:-}"
  local dk_detailed_desc="${6:-}"
  local dk_price="${7:-}"
  local dk_moq="${8:-}"

  # Parse file to check for existing ki_keywords and ki_description
  local symbols_data=$(parse_file "$file")
  local existing_keywords=$(get_property "$symbols_data" "$symbol" "ki_keywords")
  local existing_description=$(get_property "$symbols_data" "$symbol" "ki_description")

  # Build properties array
  local -a properties=("DigiKey" "$dk_part" "DigiKey URL" "$dk_url")

  # Add price and MOQ if provided
  if [[ -n "$dk_price" ]] && [[ -n "$dk_moq" ]]; then
    properties+=("Unit Price" "\$$dk_price" "MOQ" "$dk_moq")
  fi

  # Handle ki_keywords (from DigiKey Description)
  if [[ -n "$dk_desc" ]]; then
    if [[ -n "$existing_keywords" ]]; then
      # Ask user for confirmation to overwrite
      echo "" >&2
      info "    [$symbol] Existing ki_keywords: $existing_keywords"
      info "    [$symbol] New ki_keywords (from DigiKey): $dk_desc"
      read -p "    Overwrite ki_keywords? (y/N): " confirm </dev/tty
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        properties+=("ki_keywords" "$dk_desc")
      else
        info "    [$symbol] Keeping existing ki_keywords"
      fi
    else
      properties+=("ki_keywords" "$dk_desc")
    fi
  fi

  # Handle ki_description (from DigiKey Detailed Description)
  if [[ -n "$dk_detailed_desc" ]]; then
    if [[ -n "$existing_description" ]]; then
      # Ask user for confirmation to overwrite
      echo "" >&2
      info "    [$symbol] Existing ki_description: $existing_description"
      info "    [$symbol] New ki_description (from DigiKey): $dk_detailed_desc"
      read -p "    Overwrite ki_description? (y/N): " confirm </dev/tty
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        properties+=("ki_description" "$dk_detailed_desc")
      else
        info "    [$symbol] Keeping existing ki_description"
      fi
    else
      properties+=("ki_description" "$dk_detailed_desc")
    fi
  fi

  # Add properties in batch
  if add_properties_batch "$file" "$symbol" "${properties[@]}"; then
    return 0
  fi

  error "    [$symbol] Failed to add DigiKey properties"
  return 1
}

# Delete DigiKey information from all symbols in a file
# Usage: delete_digikey_info <file> <symbols_data>
delete_digikey_info() {
  local file="$1"
  local symbols_data="$2"
  local filename=$(basename "$file")

  info "  Deleting DigiKey information..."

  # Get all symbols
  local symbols=$(list_symbols "$symbols_data")

  if [[ -z "$symbols" ]]; then
    return
  fi

  local count=0
  local deleted=0

  # DigiKey-related properties to remove
  local digikey_props=(
    "DigiKey"
    "DigiKey URL"
    "DigiKey Price"
    "DigiKey MOQ"
  )

  while IFS= read -r symbol; do
    if [[ -z "$symbol" ]]; then
      continue
    fi

    ((count++)) || true

    # Check if symbol has any DigiKey properties
    local has_digikey=false
    for prop in "${digikey_props[@]}"; do
      local value=$(get_property "$symbols_data" "$symbol" "$prop")
      if [[ -n "$value" ]]; then
        has_digikey=true
        break
      fi
    done

    if ! $has_digikey; then
      continue
    fi

    # Delete each DigiKey property
    local props_deleted=0
    for prop in "${digikey_props[@]}"; do
      if delete_property "$file" "$symbol" "$prop" 2>/dev/null; then
        ((props_deleted++)) || true
      fi
    done

    if [[ $props_deleted -gt 0 ]]; then
      success "    [$symbol] Deleted $props_deleted DigiKey property(ies)"
      ((deleted++)) || true
    fi
  done <<< "$symbols"

  if [[ $deleted -gt 0 ]]; then
    success "  Deleted DigiKey info from $deleted symbol(s)"
  else
    info "  No DigiKey information found"
  fi
}
