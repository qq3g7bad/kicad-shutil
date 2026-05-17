# kicad-shutil

A single shell script that audits a KiCad **project** against the rules *your
team* sets for it, enriches its symbol libraries from the **official DigiKey
API**, and — once the project passes — drives `kicad-cli` to emit a
manufacturing package. No Python, no Docker, nothing to install.

## Why this exists

Two problems, one small tool.

### 1. "Conforms to KLC" is not the question most teams are asking

KiCad's official library checks (the KiCad Library Convention) answer one
question very well: *does this part conform to the global convention?* That is
exactly the right question when you contribute to the upstream KiCad libraries.

It is usually **not** the question a team asks about its own boards. There the
question is *does this project follow **our** rules* — every symbol resolves to
a footprint, every footprint to a 3D model that actually exists on disk, every
part to a datasheet, every library path to something this environment can
resolve. Those answers depend on *your* libraries, *your* environment
variables, *your* directory layout — not on any convention, so no globally
fixed checker can give them. That gap widens as work moves toward enterprise
scale.

kicad-shutil checks that project-scoped question, and ties one consequence to
it: a fabrication package should never be generated from a project that has not
passed. The same run that verifies the project drives `kicad-cli` to produce
the Gerbers, drill, position, netlist and previews — verification and output in
one ordered pass, or not at all.

### 2. A hardware engineer should not have to fight Python packaging

Most KiCad automation (KiBot, KiCost, kicad-library-utils) is Python. That is
fine for software engineers. It is increasingly hostile to everyone else:
current distributions and Homebrew mark the system Python as *externally
managed* ([PEP 668](https://peps.python.org/pep-0668/)), so `pip install` fails
— or, worse, a non-expert reaches for `sudo pip` and quietly breaks the system
interpreter. A hardware engineer who just wants to check a board before sending
it to fab should not have to learn `venv`, `pipx`, or Docker first.

So kicad-shutil has **no Python and no install step**. It is one Bash script
plus standard Unix tools, and it runs with the bash Apple still ships on macOS
(3.2). Clone it, run it. That constraint is the point, not an accident — it is
what keeps the tool usable on locked-down build servers and by people who do
not want a toolchain.

## Scope & non-goals

Deliberately small, and honest about its edges:

- **`pcb gerber-output` is a thin convenience, not a product.** It runs
  `kicad-cli`; it reimplements nothing. KiCad 8+ *jobsets* and
  [KiBot](https://github.com/INTI-CMNB/KiBot) already do configurable
  fabrication output well. Use this when you want zero-config output tied to
  verification in a single command; reach for jobsets or KiBot when you outgrow
  that. This part is intentionally frozen.
- **This is not a KLC checker.** For upstream-library conformance use the
  official [kicad-library-utils](https://gitlab.com/kicad/libraries/kicad-library-utils).
  It and this tool answer different questions.
- **This is not a KiBot replacement.** No panelization, no documentation
  generation, no configuration language.

What it does that those do not: project-instance verification with on-disk and
environment resolution, and writing DigiKey metadata back into the symbol
library file itself.

## Features

### Project verification — the core

Resolve the project the way KiCad would, then assert *your* rules hold:

- ✅ Project structure and library tables (`sym-lib-table`, `fp-lib-table`)
- ✅ Every symbol resolves to a footprint, and that footprint file exists
- ✅ Every symbol has a datasheet (optionally validates the URL with `--deep`)
- ✅ Every footprint has a 3D model, and that model file exists on disk
- ✅ Schematic footprint instances resolve against the library tables
- ✅ Environment-variable resolution (`KIPRJMOD`, `KICAD7_SYMBOL_DIR`, …)
- ✅ Silent on success, errors to stderr, clean exit codes — drops into CI

### Symbol library enrichment from DigiKey

The part with no direct equivalent we know of. It pulls part numbers,
descriptions and datasheet links from the **official DigiKey API** (OAuth2) and
writes them back **into the `.kicad_sym` library file itself**, in place, with
automatic backups — not into a BOM at export time, but into the library, so
every project that uses it inherits the metadata.

- ✅ Stores DigiKey description in `ki_keywords`, detailed description in `ki_description`
- ✅ Interactive confirmation before overwriting existing fields
- ✅ Bulk datasheet download
- 🔒 In-place writes are backed up (`.bak`), written atomically, integrity-checked

### Manufacturing output (convenience wrapper)

Generated only from a verified project. Wraps `kicad-cli` for Gerbers, drill,
position, netlist, and board previews (3D PNG + 2D SVG). See *Scope &
non-goals* for when to use jobsets or KiBot instead.

## Prerequisites

- `bash` — no version newer than the macOS system bash (3.2) is required
- `kicad-cli` — for the `pcb` command (KiCad 7+; 8+ for the 3D preview render)
- `curl` — for the DigiKey API and datasheet download
- `awk`, `sed`, `grep` — standard Unix tools

Pre-installed on macOS (built-in), most Linux distributions (built-in), and
Windows with Git Bash. `kicad-cli` ships with KiCad itself.

## Installation

No build, no packages. Clone and run.

```bash
# Clone into your KiCad project directory
cd /path/to/your/kicad-project
git clone --recursive https://github.com/qq3g7bad/kicad-shutil.git
chmod +x ./kicad-shutil/kicad-shutil

# Verify your project
./kicad-shutil/kicad-shutil project my_project.kicad_pro
```

If you forgot `--recursive`, initialize the test submodule:

```bash
cd kicad-shutil && git submodule update --init --recursive
```

## Quick Start

```bash
# Verify an entire project (silent on success; non-zero exit on failure)
./kicad-shutil/kicad-shutil project my_project.kicad_pro
./kicad-shutil/kicad-shutil my_project.kicad_pro          # implicit project

# Show what passed, not just what failed
./kicad-shutil/kicad-shutil --verbose project my_project.kicad_pro

# Enrich a symbol library from DigiKey (interactive)
./kicad-shutil/kicad-shutil sym --update-digikey path/to/library.kicad_sym

# Manufacturing output from a verified project
./kicad-shutil/kicad-shutil pcb gerber-output my_project.kicad_pro
```

## 📄 DigiKey API Setup

kicad-shutil uses the official DigiKey API for legal and reliable operation.

### Get API Credentials

1. Visit [DigiKey Developer Portal](https://developer.digikey.com/)
2. Create a free account
3. Create a new application
4. Note your **Client ID** and **Client Secret**

### Configure Credentials

**Option 1: Config file (recommended)** — sourced from `~/.kicad-shutil/config` if present:

```bash
mkdir -p ~/.kicad-shutil
cp config.example ~/.kicad-shutil/config
$EDITOR ~/.kicad-shutil/config
```

**Option 2: Environment variables**

```bash
export DIGIKEY_CLIENT_ID="your-client-id"
export DIGIKEY_CLIENT_SECRET="your-client-secret"
```

## 🚀 Usage

kicad-shutil provides three subcommands:

```bash
kicad-shutil project <file.kicad_pro|directory>      # verify a project
kicad-shutil <file.kicad_pro>                        # implicit project
kicad-shutil sym [options] <file.kicad_sym>...       # symbol libraries
kicad-shutil pcb gerber-output <pcb|pro|sch>         # manufacturing output
```

### Project Verification

```bash
# By file, by directory (finds the .kicad_pro), or implicitly
./kicad-shutil/kicad-shutil project my_project.kicad_pro
./kicad-shutil/kicad-shutil project ./my_project
./kicad-shutil/kicad-shutil my_project.kicad_pro

# Verbose: also show INFO/OK and the summary
./kicad-shutil/kicad-shutil --verbose project my_project.kicad_pro

# Deep: also validate datasheet URLs over the network
./kicad-shutil/kicad-shutil --deep project my_project.kicad_pro
```

**Output.** By default only errors and warnings reach stderr:

```
[ERROR] sym-lib CustomLib FILE_NOT_FOUND
[WARN] sym-lib MyLib U1 MISSING_FOOTPRINT_FIELD
[ERROR] fp-lib Footprints R_0603 3D_MODEL_FILE_NOT_FOUND
```

`--verbose` adds resolved paths plus INFO/OK/summary lines:

```
[ENV] Loaded 5 KiCad environment variables
[INFO] Verifying symbol library table: sym-lib-table
[OK] sym-lib Power_Management: /usr/share/kicad/symbols/Power_Management.kicad_sym
```

### Symbol Library Management

```bash
# Verify (default operation)
./kicad-shutil/kicad-shutil sym pmic.kicad_sym
./kicad-shutil/kicad-shutil sym --verify *.kicad_sym

# Add/update DigiKey metadata (interactive), or remove it
./kicad-shutil/kicad-shutil sym --update-digikey pmic.kicad_sym   # -u
./kicad-shutil/kicad-shutil sym --delete-digikey pmic.kicad_sym   # -d

# Download datasheets
./kicad-shutil/kicad-shutil sym -D *.kicad_sym --to ~/datasheets
```

### Manufacturing Output

```bash
# From a PCB, or a project (auto-detects PCB + schematic)
./kicad-shutil/kicad-shutil pcb gerber-output my_board.kicad_pcb
./kicad-shutil/kicad-shutil pcb gerber-output my_project.kicad_pro

# Custom output directory (default: ./manufacturing/)
./kicad-shutil/kicad-shutil pcb gerber-output my_board.kicad_pcb --output /tmp/fab
```

Output is organized into `gerbers/`, `drill/`, `position/`, `netlist/`, and
`preview/` (3D render PNG + 2D layer-composite SVG, front and back).

### Command Reference

**Global:** `kicad-shutil [--verbose] <command> [options]`

| Option | Description |
|--------|-------------|
| `--verbose` | Show INFO/OK messages and summaries |
| `-h, --help` | Show help (per command too) |
| `-v, --version` | Show version |

**`project [--verbose] [--deep] <file.kicad_pro\|directory>`**

| Option | Description |
|--------|-------------|
| `--deep` | Also validate datasheet URLs over the network |

**`sym [options] <file.kicad_sym>...`**

| Short | Long | Description |
|-------|------|-------------|
| `-v` | `--verify` | Validate footprints and datasheets (default) |
| `-u` | `--update-digikey` | Add/update DigiKey part numbers, URLs, metadata |
| `-d` | `--delete-digikey` | Remove all DigiKey metadata |
| `-D` | `--download-datasheets` | Download all datasheets |
| `-t` | `--to <dir>` | Target directory for downloads (default: `./datasheets`) |

**`pcb gerber-output [--output <dir>] <file.kicad_pcb\|.kicad_pro\|.kicad_sch>`**

### Examples

#### Verify a project (CI-style)

```bash
$ ./kicad-shutil project my_project.kicad_pro
[ERROR] sym-lib CustomLib FILE_NOT_FOUND
[WARN] sym-lib MyLib U1 MISSING_FOOTPRINT_FIELD
$ echo $?
1
```

#### Update DigiKey information

```bash
$ ./kicad-shutil sym -u pmic.kicad_sym

[INFO] Processing: pmic.kicad_sym
[INFO]   Processing DigiKey information...
[INFO]     [TPS63031DSKT] Found: TPS63031DSKT-ND

Multiple candidates found for: [LM27762DSST]
========================================
 1) LM27762DSST-ND - IC REG BUCK BST ADJ 2.5A
 2) LM27762DSSTRCT-ND - IC REG BUCK BST ADJ 2.5A (Tape & Reel)
========================================
 s) Skip this item    q) Quit

Select (1-2, s, q): 1

[INFO]     [LM27762DSST] Existing ki_keywords: power regulator
[INFO]     [LM27762DSST] New ki_keywords (from DigiKey): IC REG BUCK BST ADJ 2.5A
    Overwrite ki_keywords? (y/N): y
[OK]      [LM27762DSST] DigiKey info added: LM27762DSST-ND ($2.50/ea)
```

## Project Structure

```
kicad-shutil/
├── kicad-shutil                # Main executable (subcommand routing)
├── config.example              # Configuration template
├── lib/
│   ├── parser*.sh              # S-expr/JSON parsers (symbol, project,
│   │                           #   footprint, schematic)
│   ├── writer.sh               # Atomic property writer with backups
│   ├── utils.sh                # Logging, caching, config loading
│   ├── verify*.sh              # Dispatcher + table/project verifiers
│   ├── pcb_export.sh           # kicad-cli wrappers for manufacturing output
│   ├── datasheet.sh            # Datasheet download
│   └── digikey.sh              # DigiKey API integration (OAuth2)
├── docs/                       # requirements.md, design.md, traceability/
└── test/                       # run_tests.sh, test_*.sh, shunit2 (submodule)
```

## Development

```bash
git submodule update --init --recursive   # first time only
./test/run_tests.sh                        # run all tests
shellcheck kicad-shutil lib/*.sh           # lint
```

Contributions: fork, branch, add tests for new behavior, run
`./test/run_tests.sh`, open a PR. See [test/README.md](test/README.md).

## How It Works

- **Parsing.** AWK state machines track S-expression depth (ignoring parens
  inside quoted strings) to extract symbols/footprints; project files are
  parsed as JSON. Output is a pipe-delimited intermediate format.
- **Safety.** File writes create a `.bak`, write via a temp file, verify
  integrity, and roll back on failure.
- **Caching.** DigiKey OAuth tokens are cached in memory; API responses are
  cached on disk under `cache/` to avoid repeat calls.

## Troubleshooting

**"DigiKey API credentials not found"** — set the environment variables or
create the config file (see [DigiKey API Setup](#-digikey-api-setup)).

**"Failed to obtain DigiKey API token"** — invalid credentials, no network, or
DigiKey API downtime.

**"kicad-cli not found"** — install KiCad (7+; 8+ for the 3D preview render);
`kicad-cli` ships with it.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- [KiCad](https://www.kicad.org/) — the EDA tool and `kicad-cli`, which does
  all the actual manufacturing-output work
- [DigiKey](https://www.digikey.com/) — official API access
- [shunit2](https://github.com/kward/shunit2) — shell unit-testing framework
- [Greg Davill](https://github.com/gregdavill) — whose
  [kicadScripts](https://github.com/gregdavill/kicadScripts)
  (`plot_gerbers.py`, `plot_board.py`) inspired the `pcb` output and
  board-preview features, here re-expressed as thin `kicad-cli` wrappers

## 🔗 Requirements Traceability

This project uses [shtracer](https://github.com/qq3g7bad/shtracer) for
requirements traceability.

```bash
cd docs/traceability && ./run_shtracer.sh    # generate traceability.html
```

Requirements, architecture, implementation and tests are tagged with
`@REQ-*` / `@ARCH-*` / `@IMPL-*` / test tags. See
[docs/requirements.md](docs/requirements.md) and
[docs/design.md](docs/design.md).
