#!/usr/bin/env bash

# Test runner - Executes all unit tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR"

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    BLUE=''
    NC=''
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  kicad-shutil Test Suite${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if shunit2 is available
if [[ ! -f "$TEST_DIR/shunit2/shunit2" ]]; then
    echo -e "${RED}✗ Error: shunit2 not found${NC}"
    echo "This project uses git submodules for shunit2."
    echo "Please run:"
    echo "  git submodule update --init --recursive"
    exit 1
fi

# Find all test files
test_files=()
while IFS= read -r -d '' file; do
    test_files+=("$file")
done < <(find "$TEST_DIR" -name "test_*.sh" -type f -print0 | sort -z)

if [[ ${#test_files[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠ No test files found${NC}"
    exit 0
fi

echo -e "${BLUE}Found ${#test_files[@]} test file(s):${NC}"
for file in "${test_files[@]}"; do
    echo "  • $(basename "$file")"
done
echo ""

# Run tests
total_passed=0
total_failed=0
failed_tests=()

for test_file in "${test_files[@]}"; do
    test_name=$(basename "$test_file" .sh)
    echo -e "${BLUE}Running ${test_name}...${NC}"
    
    # Make test file executable
    chmod +x "$test_file"
    
    # Run test and capture output
    if output=$("$test_file" 2>&1); then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        ((total_passed++))
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        echo "$output" | sed 's/^/  /'
        ((total_failed++))
        failed_tests+=("$test_name")
    fi
    echo ""
done

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total: $((total_passed + total_failed))"
echo -e "${GREEN}Passed: $total_passed${NC}"

if [[ $total_failed -gt 0 ]]; then
    echo -e "${RED}Failed: $total_failed${NC}"
    echo ""
    echo -e "${RED}Failed tests:${NC}"
    for test in "${failed_tests[@]}"; do
        echo -e "  ${RED}✗${NC} $test"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}All tests passed! 🎉${NC}"
    echo ""
    exit 0
fi
