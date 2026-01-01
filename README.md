# kicad-shutil

**KiCad Project Helper Utilities** - Shell scripts for managing KiCad projects and libraries

## ✨ Features

### Project Verification

- ✅ **Comprehensive Project Checks** - Verify entire KiCad projects
  - Validates all library tables (symbols and footprints)
  - Checks all symbols for missing footprints and datasheets
  - Verifies all footprints have 3D models
  - Resolves environment variables (KIPRJMOD, etc.)

### Symbol Library Management

- ✅ **DigiKey Integration** - Automatically fetch part numbers, URLs, and metadata
  - Stores DigiKey Description in `ki_keywords` property
  - Stores DigiKey Detailed Description in `ki_description` property
  - Interactive confirmation when overwriting existing metadata
- ✅ **Datasheet Download** - Bulk download datasheets for all symbols
- ✅ **Metadata Validation** - Verify footprints and datasheet links
- 🔒 **Safe Operations** - Automatic backups before modifications

## Quick Start

```bash
# Clone into your KiCad project directory
cd /path/to/your/kicad-project
git clone --recursive https://github.com/qq3g7bad/kicad-shutil.git

# Make executable
chmod +x ./kicad-shutil/kicad-shutil

# Verify your entire KiCad project
./kicad-shutil/kicad-shutil project my_project.kicad_pro
./kicad-shutil/kicad-shutil my_project.kicad_pro  # implicit project command

# With verbose output
./kicad-shutil/kicad-shutil --verbose project my_project.kicad_pro

# Manage symbol libraries
./kicad-shutil/kicad-shutil sym --update-digikey path/to/library.kicad_sym
```

## Prerequisites

- `bash` (4.0+)
- `curl`
- `awk`, `sed`, `grep` (standard Unix tools)

**All prerequisites are pre-installed on:**

- ✅ macOS (built-in)
- ✅ Most Linux distributions (built-in)
- ✅ Windows with Git Bash (included)

## Installation

```bash
# Clone repository into your KiCad project directory
cd /path/to/your/kicad-project
git clone --recursive https://github.com/qq3g7bad/kicad-shutil.git

# Make executable
chmod +x ./kicad-shutil/kicad-shutil

# Verify installation by running tests
cd kicad-shutil
./test/run_tests.sh

# Return to project root and verify your project
cd ..
./kicad-shutil/kicad-shutil project my_project.kicad_pro
```

**Note:** If you forgot `--recursive` during clone, initialize submodules:

```bash
cd kicad-shutil
git submodule update --init --recursive
```

## 📄 DigiKey API Setup

kicad-shutil uses the official DigiKey API for legal and reliable operation.

### Get API Credentials

1. Visit [DigiKey Developer Portal](https://developer.digikey.com/)
2. Create a free account
3. Create a new application
4. Note your **Client ID** and **Client Secret**

### Configure Credentials

**Option 1: Using config file (recommended)**

kicad-shutil automatically sources `~/.kicad-shutil/config` if it exists:

```bash
# Create config directory
mkdir -p ~/.kicad-shutil

# Copy and edit the config template
cp config.example ~/.kicad-shutil/config
nano ~/.kicad-shutil/config
```

**Option 2: Using environment variables**

```bash
export DIGIKEY_CLIENT_ID="your-client-id"
export DIGIKEY_CLIENT_SECRET="your-client-secret"
```

## 🚀 Usage

kicad-shutil provides two main subcommands:

**1. Project Verification**

```bash
kicad-shutil project <file.kicad_pro|directory>
kicad-shutil <file.kicad_pro>              # implicit project command
```

**2. Symbol Library Management**

```bash
kicad-shutil sym [options] <file.kicad_sym>...
```

### Project Verification

Verify an entire KiCad project and all its libraries:

```bash
# Verify project (by file)
./kicad-shutil/kicad-shutil project my_project.kicad_pro
./kicad-shutil/kicad-shutil my_project.kicad_pro  # implicit

# Verify project (by directory - finds .kicad_pro automatically)
./kicad-shutil/kicad-shutil project ./my_project

# With verbose output (shows INFO, OK messages, and summaries)
./kicad-shutil/kicad-shutil --verbose project my_project.kicad_pro
```

**What gets checked:**

- ✅ Project structure and library tables (sym-lib-table, fp-lib-table)
- ✅ All symbol libraries - verifies library files exist
- ✅ All symbols in symbol libraries for missing footprints
- ✅ Footprint file existence for each symbol
- ✅ All footprint libraries - verifies library directories exist
- ✅ All footprints for missing 3D models
- ✅ 3D model file existence for each footprint
- ✅ Environment variable resolution (KIPRJMOD, KICAD7_SYMBOL_DIR, etc.)

**Output Format:**

By default, only errors and warnings are shown :

```
[ERROR] sym-lib CustomLib FILE_NOT_FOUND
[WARN] sym-lib MyLib U1 MISSING_FOOTPRINT_FIELD
[ERROR] fp-lib Footprints R_0603 3D_MODEL_FILE_NOT_FOUND
```

With `--verbose`, you get detailed output including paths:

```
[ERROR] sym-lib CustomLib FILE_NOT_FOUND /path/to/CustomLib.kicad_sym
[WARN] sym-lib MyLib U1 MISSING_FOOTPRINT_FIELD
[ERROR] fp-lib Footprints R_0603 3D_MODEL_FILE_NOT_FOUND /path/to/model.step
```

With `--verbose`, you also get INFO, OK, and summary messages:

```
[ENV]:Loaded 5 KiCad environment variables
[ENV]:KICAD7_SYMBOL_DIR=/usr/share/kicad/symbols
[INFO]:Verifying symbol library table:sym-lib-table
[OK]:sym-lib:Power_Management:/usr/share/kicad/symbols/Power_Management.kicad_sym
```

### Symbol Library Management

```bash
# Verify symbol library (default operation)
./kicad-shutil/kicad-shutil sym pmic.kicad_sym
./kicad-shutil/kicad-shutil sym --verify *.kicad_sym

# Add/update DigiKey information (interactive)
./kicad-shutil/kicad-shutil sym --update-digikey pmic.kicad_sym
./kicad-shutil/kicad-shutil sym -u pmic.kicad_sym

# Remove DigiKey metadata from symbols
./kicad-shutil/kicad-shutil sym --delete-digikey pmic.kicad_sym
./kicad-shutil/kicad-shutil sym -d pmic.kicad_sym

# Download all datasheets
./kicad-shutil/kicad-shutil sym --download-datasheets *.kicad_sym
./kicad-shutil/kicad-shutil sym -D *.kicad_sym --to ~/datasheets
```

### Command Reference

**Global Options:**

```bash
kicad-shutil [--verbose] <command> [options]
```

- `--verbose` - Show detailed output (INFO, OK messages, summaries)
- `-h, --help` - Show help message
- `-v, --version` - Show version information

**Project Command:**

```bash
kicad-shutil project [options] <file.kicad_pro|directory>
kicad-shutil <file.kicad_pro>                    # implicit
```

Options:
- `--verbose` - Show detailed verbose output
- `-h, --help` - Show project command help

**Symbol Command:**

```bash
kicad-shutil sym [options] <file.kicad_sym> [<file2.kicad_sym> ...]
```

Options:
- `-v, --verify` - Validate footprints, datasheets (default)
- `-u, --update-digikey` - Add/update DigiKey metadata
- `-d, --delete-digikey` - Remove DigiKey metadata
- `-D, --download-datasheets` - Download all datasheets
- `-t, --to <dir>` - Target directory for downloads
- `-h, --help` - Show help message

| Short | Long | Description |
|-------|------|-------------|
| `-u` | `--update-digikey` | Add/update DigiKey part numbers, URLs, and metadata |
| `-d` | `--delete-digikey` | Remove all DigiKey metadata from symbols |
| `-v` | `--verify` | Validate footprints and datasheets, show detailed report |
| `-D` | `--download-datasheets` | Download all datasheets (use `--to <dir>` to specify directory, default: `./datasheets`) |
| `-h` | `--help` | Show help message |

### Examples

#### Verify Entire Project

```bash
# Default (silent on success, errors to stderr)
$ ./kicad-shutil project my_project.kicad_pro
[ERROR] sym-lib CustomLib FILE_NOT_FOUND
[WARN] sym-lib MyLib U1 MISSING_FOOTPRINT_FIELD
$ echo $?
1

# With verbose output
$ ./kicad-shutil --verbose project my_project.kicad_pro
[INFO] Parsing project file: my_project.kicad_pro
[INFO] Verifying symbol library table: sym-lib-table
[OK] sym-lib Power_Management: /usr/share/kicad/symbols/Power_Management.kicad_sym
[INFO] Verifying footprint library table: fp-lib-table
[OK] fp-lib Resistor_SMD: /usr/share/kicad/footprints/Resistor_SMD.pretty
$ echo $?
0
```

#### Update DigiKey Information

```bash
$ ./kicad-shutil sym -u pmic.kicad_sym

[INFO] Processing: pmic.kicad_sym
[INFO]   Processing DigiKey information...
[INFO]     [TPS63031DSKT] Searching DigiKey for: TPS63031DSKT
[INFO]     [TPS63031DSKT] Found: TPS63031DSKT-ND

Multiple candidates found for: [LM27762DSST]
========================================
 1) LM27762DSST-ND - IC REG BUCK BST ADJ 2.5A
 2) LM27762DSSTRCT-ND - IC REG BUCK BST ADJ 2.5A (Tape & Reel)
========================================
 s) Skip this item
 q) Quit

Select (1-2, s, q): 1

[INFO]     [LM27762DSST] Existing ki_keywords: power regulator
[INFO]     [LM27762DSST] New ki_keywords (from DigiKey): IC REG BUCK BST ADJ 2.5A
    Overwrite ki_keywords? (y/N): y

[INFO]     [LM27762DSST] Existing ki_description: Buck-boost regulator
[INFO]     [LM27762DSST] New ki_description (from DigiKey): The LM27762 is a dual-output...
    Overwrite ki_description? (y/N): n
[INFO]     [LM27762DSST] Keeping existing ki_description
[OK]      [LM27762DSST] DigiKey info added: LM27762DSST-ND ($2.50/ea)
```

#### Download Datasheets

```bash
# Download datasheets to default directory (./datasheets)
./kicad-shutil sym --download-datasheets pmic.kicad_sym

# Download to specific directory
./kicad-shutil sym -D *.kicad_sym --to ~/my_datasheets
```

## Project Structure

```
kicad-shutil/
├── kicad-shutil                # Main executable
├── config.example              # Configuration template
├── lib/                        # Library modules
│   ├── parser.sh               # S-expression parser for symbols
│   ├── parser_project.sh       # JSON parser for projects
│   ├── parser_footprint.sh     # S-expression parser for footprints
│   ├── writer.sh               # Property writer
│   ├── utils.sh                # Utilities
│   ├── verify.sh               # Verification dispatcher
│   ├── verify_table.sh         # Library table verification
│   ├── verify_project.sh       # Project verification
│   ├── datasheet.sh            # Datasheet download
│   └── digikey.sh              # DigiKey API integration
├── cache/                      # API response cache
├── docs/                       # Documentation
│   ├── requirements.md         # Requirements specification
│   ├── design.md               # Architecture and design
│   ├── shtracer/               # Traceability tool (submodule)
│   └── traceability/           # Traceability reports
│       ├── config.md           # Traceability configuration
│       ├── run_shtracer.sh     # Report generator
│       └── traceability.html   # Generated report
└── test/                       # Test suite
    ├── run_tests.sh            # Test runner
    ├── test_*.sh               # Unit tests
    ├── fixtures/               # Test data
    └── shunit2/                # Test framework (submodule)
```

## Development

### Running Tests

```bash
# Ensure submodules are initialized
git submodule update --init --recursive

# Run all tests
./test/run_tests.sh
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Run `./test/run_tests.sh`
5. Submit a pull request

See [test/README.md](test/README.md) for detailed testing information.

## How It Works

### S-Expression Parsing

Uses AWK-based state machine to parse KiCad symbol files:

- Identifies symbol boundaries by tracking brace depth
- Extracts properties while preserving formatting
- Inserts new properties at correct locations

### Safety Features

- **Automatic backups** - Creates `.bak` files before modifications
- **Atomic writes** - Uses temporary files to prevent corruption
- **Validation** - Verifies file integrity after changes

### Caching

- API responses cached for 1 hour
- Web requests cached for 15 minutes
- Cache location: `cache/` directory

## Troubleshooting

### DigiKey API Issues

**Error: "DigiKey API credentials not found"**

Solution: Set environment variables or create config file (see [DigiKey API Setup](#digikey-api-setup))

**Error: "Failed to obtain DigiKey API token"**

Possible causes:

- Invalid credentials
- Network connectivity issues
- DigiKey API service downtime

### Missing Dependencies

**Error: "curl: command not found"**

Install missing tools:

- macOS: `brew install curl`
- Linux: `sudo apt install curl`
- Windows: Use Git Bash (includes curl)

## License

MIT License - See LICENSE file for details

## Acknowledgments

- [KiCad](https://www.kicad.org/) - Excellent EDA tool
- [DigiKey](https://www.digikey.com/) - Official API access
- [shunit2](https://github.com/kward/shunit2) - Shell unit testing framework

## 🔗 Requirements Traceability

This project uses [shtracer](https://github.com/qq3g7bad/shtracer) for requirements traceability management.

### Viewing Traceability

```bash
# Generate HTML report
cd docs/traceability
./run_shtracer.sh

# View report
open traceability.html  # macOS
xdg-open traceability.html  # Linux
```

### Current Status

The traceability matrix has been fully implemented:

- ✅ **Requirements**: 20 requirement tags defined
- ✅ **Architecture**: 23 architecture tags defined
- ✅ **Implementation**: All major public functions tagged with @IMPL-* tags
- ✅ **Tests**: Sample test tags added to test_parser.sh

**Coverage:**
- All requirements have corresponding architecture tags
- All critical functions have implementation tags
- Test coverage includes unit tests for parsers, verifiers, and utilities

See [docs/requirements.md](docs/requirements.md) and [docs/design.md](docs/design.md) for detailed traceability documentation.
