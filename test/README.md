# kicad-putil Testing Guide

## Quick Start

```bash
# Initialize shunit2 submodule (first time only)
git submodule update --init --recursive

# Run all tests
./test/run_tests.sh
```

## Test Structure

```
test/
├── run_tests.sh                 # Test runner
├── test_utils.sh                # Tests for lib/utils.sh
├── test_parser.sh               # Tests for lib/parser.sh
├── test_writer.sh               # Tests for lib/writer.sh
├── test_verify.sh               # Tests for lib/verify.sh
├── test_datasheet.sh            # Tests for lib/datasheet.sh
├── test_digikey.sh              # Tests for lib/digikey.sh
├── fixtures/                    # Test data files
├── integration/                 # Integration tests
│   └── test_digikey_integration.sh  # DigiKey API tests (requires credentials)
└── shunit2/                     # Testing framework (git submodule)
```

## Running Tests

### All Tests
```bash
# From project root
./test/run_tests.sh
```

### Individual Test Suites
```bash
./test/test_utils.sh
./test/test_parser.sh
./test/test_writer.sh
```

### Integration Tests
```bash
# Requires DIGIKEY_CLIENT_ID and DIGIKEY_CLIENT_SECRET
export DIGIKEY_CLIENT_ID="your-id"
export DIGIKEY_CLIENT_SECRET="your-secret"
./test/integration/test_digikey_integration.sh
```

## Writing Tests

### Test File Template

```bash
#!/usr/bin/env bash

# Unit tests for lib/your_module.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source the module to test
source "$LIB_DIR/your_module.sh"

# Disable color output for consistent results
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_RESET=""

#-----------------------------------
# Test: your_function()
#-----------------------------------
testYourFunction() {
    local result=$(your_function "input")
    assertEquals "Expected output" "$result"
}

#-----------------------------------
# Load and run shunit2
#-----------------------------------
. "$(dirname "$0")/shunit2"
```

### Common Assertions

```bash
assertEquals "message" "expected" "actual"
assertNotEquals "message" "unexpected" "actual"
assertTrue "message" "[ condition ]"
assertFalse "message" "[ condition ]"
assertNull "message" "$value"
assertNotNull "message" "$value"
assertContains "message" "$haystack" "needle"
```

### Setup and Teardown

```bash
# Run once before all tests
oneTimeSetUp() {
    mkdir -p "$FIXTURES_DIR"
}

# Run once after all tests
oneTimeTearDown() {
    rm -rf "$FIXTURES_DIR"
}

# Run before each test
setUp() {
    TEST_FILE="/tmp/test_$$"
}

# Run after each test
tearDown() {
    rm -f "$TEST_FILE"
}
```

### Skipping Tests

```bash
testOptionalFeature() {
    if ! command -v optional_command >/dev/null; then
        startSkipping
        return
    fi
    
    # Test code here
}
```

## Test Coverage

See [TEST_COVERAGE.md](TEST_COVERAGE.md) for detailed coverage information.

### Current Coverage

- ✅ **lib/utils.sh** - Logging, timestamps, caching
- ✅ **lib/parser.sh** - S-expression parsing, property extraction
- ✅ **lib/writer.sh** - File modification, backups, validation
- ⚠️ **lib/digikey.sh** - Integration tests (requires API credentials)
- ⏳ **lib/datasheet.sh** - Not yet tested
- ⏳ **lib/summary.sh** - Not yet tested
- ⏳ **lib/verify.sh** - Not yet tested

## CI Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y curl awk sed grep
      
      - name: Initialize submodules
        run: git submodule update --init --recursive
      
      - name: Run tests
        run: ./run_tests.sh
```

## Troubleshooting

### shunit2 not found
```bash
curl -fsSL https://raw.githubusercontent.com/kward/shunit2/master/shunit2 -o test/shunit2
chmod +x test/shunit2
```

### Test failures
```bash
# Run individual test with verbose output
bash -x ./test/test_utils.sh
```

### Permission denied
```bash
chmod +x ./run_tests.sh
chmod +x ./test/*.sh
```

## Best Practices

1. **One test per function** - Keep tests focused and isolated
2. **Descriptive names** - Use clear test function names like `testGetTimestampReturnsNumber`
3. **Clean up** - Always clean up temporary files in `tearDown()`
4. **Mock external dependencies** - Use fixtures instead of real API calls when possible
5. **Test edge cases** - Empty inputs, invalid data, missing files, etc.
6. **Fast tests** - Unit tests should run in milliseconds, not seconds

## Contributing

When adding new features to kicad-putil:

1. Write tests first (TDD)
2. Ensure all tests pass: `./run_tests.sh`
3. Update `TEST_COVERAGE.md` if needed
4. Include test examples in your PR description
