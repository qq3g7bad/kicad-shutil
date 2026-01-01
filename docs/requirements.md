# Requirements Specification

## Table of Contents
- [1. Project Verification](#1-project-verification)
- [2. Symbol Library Management](#2-symbol-library-management)
- [3. File Operations](#3-file-operations)
- [4. Cross-Platform Compatibility](#4-cross-platform-compatibility)
- [5. Command-Line Interface](#5-command-line-interface)
- [6. Quality Assurance](#6-quality-assurance)
- [7. Future Requirements](#7-future-requirements)

## Requirements Summary

| Category | Count | Status |
|----------|-------|--------|
| Project Verification | 4 | ✅ Implemented |
| Symbol Library Management | 4 | ✅ Implemented |
| File Operations | 4 | ✅ Implemented |
| Cross-Platform Compatibility | 2 | ✅ Implemented |
| Command-Line Interface | 3 | ✅ Implemented |
| Quality Assurance | 2 | ✅ Implemented |
| Future Requirements | 1 | 🔄 Planned |
| **Total** | **20** | **95% Complete** |

## 1. Project Verification

<!-- @REQ-PROJ-001@ -->
### Project File Validation
The system shall validate KiCad project files (`.kicad_pro`) and their associated library tables (`sym-lib-table`, `fp-lib-table`).

**Acceptance Criteria:**
- Parse JSON format of `.kicad_pro` files
- Extract project directory (KIPRJMOD)
- Extract text variables and environment variables
- Locate and verify sym-lib-table and fp-lib-table files
- Skip disabled library entries (lines containing `disabled` option)

<!-- @REQ-PROJ-002@ -->
### Deep Symbol Library Verification
The system shall perform deep verification of all symbol libraries referenced in the project.

**Acceptance Criteria:**
- Resolve environment variables in library paths (KIPRJMOD, KICAD7_SYMBOL_DIR, etc.)
- Parse all `.kicad_sym` files in each library
- Check each symbol for:
  - Missing Footprint field
  - Footprint file existence
  - Missing Datasheet field

<!-- @REQ-PROJ-003@ -->
### Deep Footprint Library Verification
The system shall perform deep verification of all footprint libraries referenced in the project.

**Acceptance Criteria:**
- Resolve environment variables in library paths
- Parse all `.kicad_mod` files in each library
- Check each footprint for:
  - Missing 3D model references
  - 3D model file existence
- Resolve environment variables in model paths (KICAD7_3DMODEL_DIR, etc.)

<!-- @REQ-PROJ-004@ -->
### Verification Reporting
The system shall provide comprehensive verification reports with statistics.

**Acceptance Criteria:**
- Count total libraries, symbols, and footprints
- Report missing footprints, datasheets, and 3D models
- Display errors and warnings with appropriate severity levels
- Support debug mode for detailed output

**Output Format Examples:**

Default mode (errors only):
```
[ERROR] sym-lib CustomLib FILE_NOT_FOUND
[WARN] fp-lib Resistor_SMD R_0603 MISSING_3D_MODEL
```

Verbose mode (with details):
```
[INFO] Verifying symbol library table: sym-lib-table
[OK] sym-lib Power_Management: /usr/share/kicad/symbols/Power_Management.kicad_sym
[ERROR] sym-lib CustomLib FILE_NOT_FOUND /path/to/CustomLib.kicad_sym
```

## 2. Symbol Library Management

<!-- @REQ-SYM-001@ -->
### Symbol Library Verification
The system shall verify individual symbol library files (`.kicad_sym`).

**Acceptance Criteria:**
- Parse S-expression format
- Extract symbol metadata and properties
- Validate footprint and datasheet fields
- Generate verification reports

<!-- @REQ-SYM-002@ -->
### DigiKey Integration
The system shall integrate with DigiKey API to add/update part information.

**Acceptance Criteria:**
- OAuth2 authentication with DigiKey API
- Search for parts by manufacturer and part number
- Interactive selection when multiple matches found
- Add DigiKey part number and URL properties to symbols
- Cache API responses to minimize requests

<!-- @REQ-SYM-003@ -->
### DigiKey Metadata Removal
The system shall remove DigiKey metadata from symbol libraries.

**Acceptance Criteria:**
- Delete DigiKey and "DigiKey URL" properties
- Preserve other symbol properties
- Create automatic backups before modification

<!-- @REQ-SYM-004@ -->
### Datasheet Download
The system shall download datasheets for all symbols in a library.

**Acceptance Criteria:**
- Extract datasheet URLs from symbol properties
- Download PDF files with retry logic
- Organize downloads by category/library name
- Track download progress and statistics
- Handle network errors gracefully

## 3. File Operations

<!-- @REQ-FILE-001@ -->
### S-Expression Parser
The system shall parse KiCad S-expression format files.

**Acceptance Criteria:**
- Parse `.kicad_sym` files (symbol libraries)
- Parse `.kicad_mod` files (footprint definitions)
- Parse library table files (sym-lib-table, fp-lib-table)
- Extract symbols, properties, and metadata
- Support nested graphical symbols

<!-- @REQ-FILE-002@ -->
### JSON Parser
The system shall parse KiCad JSON format files.

**Acceptance Criteria:**
- Parse `.kicad_pro` files (project configuration)
- Extract project directory path
- Extract text variables
- Extract environment variables

<!-- @REQ-FILE-003@ -->
### Atomic File Writes
The system shall modify files atomically with automatic backups.

**Acceptance Criteria:**
- Create `.bak` backup files before modification
- Use temporary files for atomic writes
- Verify file integrity after modification
- Restore from backup on failure
- Clean up backups on success

<!-- @REQ-FILE-004@ -->
### Property Insertion
The system shall insert and modify properties in symbol files.

**Acceptance Criteria:**
- Add new properties to existing symbols
- Update existing property values
- Preserve property formatting and position
- Maintain S-expression structure

## 4. Cross-Platform Compatibility

<!-- @REQ-PLAT-001@ -->
### POSIX Shell Compliance
The system shall use POSIX-compliant shell constructs where possible.

**Acceptance Criteria:**
- Bash 4.0+ compatibility
- Work on Linux, macOS, and Windows (Git Bash)
- Avoid GNU-specific tools where possible
- Use portable AWK, sed, grep patterns

**Platform-Specific Notes:**

| Platform | Shell | AWK | Notes |
|----------|-------|-----|-------|
| Linux | bash 4.0+ | GNU awk | Default, fully tested |
| macOS | bash 3.2+ (4.0+ recommended) | BSD awk | Compatible, CI tested |
| Windows | Git Bash 4.0+ | GNU awk | Via Git for Windows |

**Known Limitations:**
- macOS: Default bash 3.2 lacks associative arrays - install bash 4.0+ via Homebrew
- Windows: Requires Git Bash (included with Git for Windows)

<!-- @REQ-PLAT-002@ -->
### Zero External Dependencies
The system shall have no external dependencies beyond standard Unix tools.

**Acceptance Criteria:**
- Only require: bash, curl, awk, sed, grep
- No Python, Node.js, or other runtime environments
- No external libraries or packages

## 5. Command-Line Interface

<!-- @REQ-CLI-001@ -->
### Subcommand Interface
The system shall provide a subcommand-based CLI interface.

**Acceptance Criteria:**
- `project` subcommand for project verification
- `sym` subcommand for symbol library management
- Default to project verification when file path provided
- Clear help messages for each subcommand

<!-- @REQ-CLI-002@ -->
### UNIX Philosophy Output
The system shall follow UNIX philosophy for output handling.

**Acceptance Criteria:**
- Silent on success (default mode)
- Errors and warnings to stderr
- Info and success messages only in verbose mode
- Support verbose flag (--verbose) for detailed output
- Clean exit codes (0 = success, 1 = failure, 2 = usage error)

<!-- @REQ-CLI-003@ -->
### Batch Processing
The system shall support processing multiple files.

**Acceptance Criteria:**
- Accept multiple file arguments
- Support glob patterns (*.kicad_sym)
- Process files sequentially
- Aggregate statistics across files

## 6. Quality Assurance

<!-- @REQ-QA-001@ -->
### Unit Testing
The system shall have comprehensive unit test coverage.

**Acceptance Criteria:**
- Test framework: shunit2
- Tests for all library modules
- Integration tests for end-to-end workflows
- CI/CD integration via GitHub Actions

<!-- @REQ-QA-002@ -->
### Static Analysis
The system shall pass static analysis checks.

**Acceptance Criteria:**
- ShellCheck compliance
- No critical or high-severity warnings
- Configuration via .shellcheckrc

## 7. Future Requirements

<!-- @REQ-FUTURE-001@ -->
### Schematic Verification (Planned)
The system shall support verification of schematic files (`.kicad_sch`).

**Status:** Not yet implemented

**Acceptance Criteria:**
- Parse S-expression format of schematic files
- Verify component references match symbols in library tables
- Check that all components have valid footprints
- Validate datasheet links at component level
- Cross-reference with DigiKey part numbers for BOM generation
