# kicad-shutil

**KiCad Symbol Helper Utilities** - Shell scripts for managing KiCad symbol library metadata

## ✨ Features

- ✅ **DigiKey Integration** - Automatically fetch part numbers, URLs, and metadata
  - Stores DigiKey Description in `ki_keywords` property
  - Stores DigiKey Detailed Description in `ki_description` property
  - Interactive confirmation when overwriting existing metadata
- ✅ **Datasheet Download** - Bulk download datasheets for all symbols
- ✅ **Metadata Validation** - Verify footprints and datasheet links
- ✅ **Summary Reports** - Generate TSV reports of symbol libraries
- 🔒 **Safe Operations** - Automatic backups before modifications

## Quick Start

```bash
# Clone with submodules
git clone --recursive <repository-url> kicad-shutil
cd kicad-shutil

# If you forgot --recursive, initialize submodules
git submodule update --init --recursive

# Add DigiKey information to your symbols
./kicad-shutil --digikey path/to/your/library.kicad_sym
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
# Clone repository with test framework submodule
cd /path/to/your/kicad/library
git clone --recursive https://github.com/your-username/kicad-shutil.git
cd kicad-shutil

# If you forgot --recursive during clone
git submodule update --init --recursive

# Verify installation by running tests
./test/run_tests.sh
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

If no operation is specified, `--verify` is used by default.

### Basic Commands

```bash
# Verify symbols (default operation)
./kicad-shutil pmic.kicad_sym
./kicad-shutil *.kicad_sym

# Add/update DigiKey information (interactive)
./kicad-shutil --update-digikey-info pmic.kicad_sym
./kicad-shutil -u pmic.kicad_sym

# Remove DigiKey metadata from symbols
./kicad-shutil --delete-digikey-info pmic.kicad_sym
./kicad-shutil -d pmic.kicad_sym

# Verify library integrity
./kicad-shutil --verify *.kicad_sym
./kicad-shutil -v *.kicad_sym

# Download all datasheets
./kicad-shutil --download-datasheets *.kicad_sym
./kicad-shutil -D *.kicad_sym --to ~/datasheets
```

### Options

| Short | Long | Description |
|-------|------|-------------|
| `-u` | `--update-digikey-info` | Add/update DigiKey part numbers, URLs, and metadata |
| `-d` | `--delete-digikey-info` | Remove all DigiKey metadata from symbols |
| `-v` | `--verify` | Validate footprints and datasheets, show detailed report |
| `-D` | `--download-datasheets` | Download all datasheets (use `--to <dir>` to specify directory, default: `./datasheets`) |
| `-h` | `--help` | Show help message |

### Examples

#### Update DigiKey Information

```bash
$ ./kicad-shutil -u pmic.kicad_sym

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

#### Auto-Skip Mode

```bash
# Skip symbols with multiple candidates
./kicad-shutil --digikey --auto-skip pmic.kicad_sym
```

#### Combined Operations

```bash
# Verify, add DigiKey info, and download datasheets
./kicad-shutil --verify --digikey --datasheet pmic.kicad_sym
```

## Project Structure

```
kicad-shutil/
├── kicad-shutil         # Main executable
├── config.example       # Configuration template
├── lib/                 # Library modules
│   ├── parser.sh        # S-expression parser
│   ├── writer.sh        # Property writer
│   ├── utils.sh         # Utilities
│   ├── verify.sh        # Verification
│   ├── summary.sh       # Reporting
│   ├── datasheet.sh     # Datasheet download
│   └── digikey.sh       # DigiKey API integration
├── cache/               # API response cache
└── test/                # Test suite
    ├── run_tests.sh     # Test runner
    ├── test_*.sh        # Unit tests
    └── shunit2/         # Test framework (submodule)
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
