# Traceability Configuration for kicad-shutil

## Requirements

* **PATH**: "../requirements.md"
  * **BRIEF**: "Functional and non-functional requirements"
  * **TAG FORMAT**: `@REQ-[A-Z0-9-]+@`
  * **TAG LINE FORMAT**: `<!--.*-->`
  * **TAG-TITLE OFFSET**: 0

## Architecture

* **PATH**: "../design.md"
  * **BRIEF**: "System architecture and design patterns"
  * **TAG FORMAT**: `@ARCH-[A-Z0-9-]+@`
  * **TAG LINE FORMAT**: `<!--.*-->`
  * **TAG-TITLE OFFSET**: 0

## Implementation

* **PATH**: "../../kicad-shutil"
  * **TAG FORMAT**: `@IMPL-[A-Z0-9-]+@`
  * **TAG LINE FORMAT**: `#.*`
  * **BRIEF**: "Main executable script"

* **PATH**: "../../lib/"
  * **EXTENSION FILTER**: "*.sh"
  * **TAG FORMAT**: `@IMPL-[A-Z0-9-]+@`
  * **TAG LINE FORMAT**: `#.*`
  * **BRIEF**: "Library modules (parser, verify, digikey, etc.)"

## Unit Tests

* **PATH**: "../../test/"
  * **EXTENSION FILTER**: "*.sh"
  * **IGNORE FILTER**: "shunit2|run_tests"
  * **TAG FORMAT**: `@TEST-[A-Z0-9-]+@`
  * **TAG LINE FORMAT**: `#.*`
  * **BRIEF**: "Unit test files using shunit2 framework"

## CI Tests

* **PATH**: "../../.github/workflows/"
  * **EXTENSION FILTER**: "*.yml"
  * **TAG FORMAT**: `@CI-[A-Z0-9-]+@`
  * **TAG LINE FORMAT**: `#.*`
  * **BRIEF**: "GitHub Actions CI/CD workflows for cross-platform testing and quality checks"
