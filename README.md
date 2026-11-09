# WGET Bulk Downloader - Batch File Download Manager with Resume & Checksum Verification

A Python CLI bulk download manager with resume capability, SHA256 checksum verification, and privacy features. Built on `wget` for downloading large files (OVA images, firmware, ISO, virtual appliances) from pre-signed AWS S3 URLs, Azure Blob Storage, or any HTTP/HTTPS source. Supports batch downloading from spreadsheets (Excel `.xlsx`, `.csv`) with automatic retry, user-agent rotation, and VPN integration.

> **On a Mac?** There is now a native macOS app — no Terminal, no Python, no `wget` to install. See [macOS App](#macos-app-v13).

```
 ██╗    ██╗ ██████╗ ███████╗████████╗    ██████╗ ██╗
 ██║    ██║██╔════╝ ██╔════╝╚══██╔══╝    ██╔══██╗██║
 ██║ █╗ ██║██║  ███╗█████╗     ██║       ██║  ██║██║
 ██║███╗██║██║   ██║██╔══╝     ██║       ██║  ██║██║
 ╚███╔███╔╝╚██████╔╝███████╗   ██║       ██████╔╝███████╗
  ╚══╝╚══╝  ╚═════╝ ╚══════╝   ╚═╝       ╚═════╝ ╚══════╝
       Bulk Downloader  v2.0  |  Human-like & Resume-capable
```

---

## Why This Exists

You get a vendor email with 15 pre-signed S3 download links, each pointing to a multi-gigabyte OVA. You're supposed to `wget -O` each one manually, pray your connection holds, and hope the file isn't corrupt when it lands. If it drops at 90%, you start over.

**Not anymore.**

Drop your URLs into a spreadsheet, paste in the vendor's SHA256 checksums, fire up the script, and walk away. It downloads everything in sequence with human-like timing, resumes interrupted transfers automatically, verifies every file against its checksum, and tracks exactly what's done vs. what still needs pulling. If your VPN drops or your laptop sleeps mid-transfer, just re-run -- it picks up right where it left off and skips anything already verified.

---

## Core Capabilities

### Downloads & Resume
- **True resume support** -- interrupted downloads pick up from the exact byte via `wget -c`. No re-downloading 20 GB because your connection hiccuped at 19.8 GB.
- **Automatic retry** -- 3 retries per file with 60-second timeout on stalled connections.
- **Batch processing** -- reads URLs from `.xlsx`, `.csv`, or `.tsv` spreadsheets. One file, dozens of downloads.
- **Auto file discovery** -- scans your working directory for spreadsheets and lets you pick from a list. No typing paths.
- **Smart skip on re-run** -- completed + verified files are skipped instantly. Only failed or missing files get retried.

### Integrity & Verification
- **SHA256 checksum verification (optional)** -- paste the vendor's hash into the `sha256` column and the script verifies the file after download. Leave the column blank or omit it entirely if you don't have a checksum -- the file still downloads, verification is just skipped.
- **Download manifest** -- `download_manifest.json` persists in the output folder. Tracks status (`completed`, `failed`, `sha256_mismatch`), file sizes, timestamps, and attempt counts.
- **Corruption detection** -- if a file downloads but the checksum doesn't match, it's flagged immediately. No deploying a corrupt OVA into production.
- **Path traversal protection** -- filenames from spreadsheets are sanitized. No `../../etc/passwd` escaping the output folder.

### Privacy & OPSEC
- **User-Agent rotation** -- cycles through 6 real browser User-Agent strings (Chrome, Firefox, Safari on Windows/macOS/Linux). Server logs see a browser, not `Wget/1.25.0`.
- **Human-like timing** -- configurable random delays between downloads (default 4-15 seconds). Traffic pattern looks like a person clicking links, not a script hammering an endpoint.
- **Built-in IP checker** -- option [3] queries your public IP and runs geolocation. Shows country, city, ISP, ASN, and whether it's flagged as a datacenter/VPN IP. Know your exit node before you start.
- **VPN detection** -- automatically tells you if your current IP looks like a VPN/datacenter or a residential ISP. If it's residential, you get a warning before downloading.
- **VPN recommendations** -- built-in guide covering Mullvad, ProtonVPN, and IVPN with privacy comparisons, payment anonymity, and setup checklists.

### Operational
- **Graceful Ctrl+C** -- interrupt mid-download and the manifest saves, a summary prints, and you return to the menu cleanly. No tracebacks, no lost state.
- **Template generator** -- option [6] creates a blank `.csv` with the correct headers. Fill it in, run it, done.
- **Status dashboard** -- option [5] reads the manifest and prints a table: what completed, what failed, file sizes, timestamps, and whether the file still exists on disk.
- **Dependency bootstrap** -- first run auto-installs `requests`, `pandas`, and `openpyxl` if missing. Checks for `wget` on PATH. Zero manual setup.

---

## Menu

```
  [1]  Download from file          (.xlsx or .csv)
  [2]  Traffic obfuscation guide   (VPN info & tips)
  [3]  Check my current public IP
  [4]  Quick start & help
  [5]  View download status        (manifest report)
  [6]  Generate download template  (blank .csv)
  [0]  Exit
```

---

## Quick Start

```bash
# Clone
git clone https://github.com/fjimenez77/Wget-Downloader-py.git
cd Wget-Downloader-py

# Run
python3 wget_downloader.py
```

On first run, the script checks for dependencies and installs any missing packages automatically.

### Requirements

- **Python 3.11+** (minimum) — tested on Python 3.14.4 (latest)
- **wget** (`brew install wget` on macOS, `sudo apt install wget` on Linux)
- Python packages: `requests`, `pandas`, `openpyxl` (auto-installed on first run)

---

## macOS App (v1.3)

<p align="center">
  <img src="docs/macos/wget-downloader-logo.png" alt="Wget Downloader app icon — a bright green arrow pointing down into an open tray, on a dark rounded square" width="150">
</p>

A native SwiftUI app for Apple Silicon Macs. Same job as the CLI — bulk downloads, resume, SHA-256 verification, randomized delays and user-agent rotation — with no Terminal, no Python, no Homebrew, and no `wget` to install. It downloads with the system `curl`.

![Wget Downloader main window on macOS — a queue of four files each marked Ready, the chosen download folder, the Paste Links and Choose Spreadsheet buttons, and Start Downloads](docs/macos/wget-downloader.png)

### Install

1. Download `Wget Downloader.dmg` from the **[Releases page](https://github.com/fjimenez77/Wget-Downloader-py/releases)**.
2. Open the disk image and drag **Wget Downloader** onto the **Applications** shortcut.
3. Launch it from Applications or Spotlight.

**Requirements:** an Apple Silicon Mac (M1 or later) running **macOS 13 Ventura or later**. Intel Macs are not supported by this build.

The disk image also carries the credits, the full Apache 2.0 and libxls BSD 2-Clause license texts, and a clickable shortcut back to this repository.

#### Or build it yourself

```bash
git clone https://github.com/fjimenez77/Wget-Downloader-py.git
cd Wget-Downloader-py
bash mac/build.sh    # writes dist/Wget Downloader.dmg
bash mac/verify.sh   # signature, license and download regression checks
```

Requires the Xcode command line tools. `mac/verify.sh` takes an optional path to a legacy `.xls` fixture to exercise the bundled reader.

### Two ways to queue downloads

**Choose Spreadsheet** reads the first worksheet of a `.csv`, `.tsv`, `.xlsx`, `.xlsm`, or legacy `.xls` file, using the same `url`, `file`, and `sha256` columns as the CLI — including the CLI's header aliases.

**Paste Links** takes one entry per line, straight from a vendor email.

![The Paste download links sheet — a text area holding one plain URL per line alongside a wget -O command, with Cancel and Add to Queue buttons](docs/macos/paste-links.png)

It understands:

- raw HTTP and HTTPS URLs, including presigned S3 links
- Markdown-wrapped links
- `wget URL`, `wget -O filename URL`, `--output-document` in place of `-O`, and an optional `-c` / `--continue`
- labeled vendor download blocks, and a combined `Checksum: <SHA-256> wget -O ...` line
- a plain URL plus an optional filename and SHA-256, separated by tabs

Pasted text is parsed as data and never passed through a shell. Arbitrary `wget` flags and shell syntax are outside the supported input format, and filenames are sanitized the same way as in the CLI.

### Built-in help and tools

![The How to Use sheet — numbered steps for adding downloads, choosing a folder and starting, and pausing or resuming, followed by network and settings guidance](docs/macos/how-to-use.png)

**How to Use** explains the spreadsheet columns and every supported paste format without leaving the app. **Tools** adds a configurable CSV template generator, a quick start, VPN guidance, and a user-initiated public IP / geolocation and proxy-hosting check that ports the CLI's service chain — detection is approximate. **Settings** persists the randomized delay range and browser user-agent rotation, defaulting to the CLI's 4–15 seconds with rotation enabled.

**History** reads `download_manifest.json` from the selected output folder and shows status, size, attempt count, on-disk state, and the last completion or error. New downloads use the CLI's `output/filename-stem/filename` layout, so a transfer the CLI already completed can be skipped, and a transfer the CLI recorded as failed can be resumed. New manifest rows store a source fingerprint in place of the full URL; older rows written by the CLI remain readable.

### macOS app vs. Python CLI

| | macOS app | Python CLI |
| --- | --- | --- |
| Interface | Native window, installed from a DMG | Terminal menu |
| Download engine | System `curl` | GNU `wget` |
| Dependencies | None | Python 3.11+, `wget`, `requests`, `pandas`, `openpyxl` |
| Platform | Apple Silicon, macOS 13+ | macOS, Linux |
| Input | Spreadsheet **or** Paste Links | Spreadsheet |
| Resume, SHA-256, manifest | Yes | Yes |

Both versions accept raw HTTP and HTTPS URLs, including presigned S3 URLs, and support optional SHA-256 verification. The Python CLI takes the raw link in the spreadsheet's `url` column, with optional `file` and `sha256` columns. The Mac app also offers **Paste Links**, which accepts raw URLs, Markdown links, supported `wget -O` commands, and labeled vendor blocks with checksums. For the CLI, copy the URL, filename, and checksum from those blocks into the corresponding spreadsheet columns.

The Mac app uses the system `curl` and the CLI uses GNU `wget`. Both support resuming on servers that support HTTP Range requests. Their in-progress files use different locations, so avoid running both versions against the same output folder concurrently.

---

## Spreadsheet Format

Use option **[6]** to generate a blank template, or fill in the included `downloads_template.xlsx`.

| Column | Required | Description |
|--------|----------|-------------|
| `#` | no | Row number |
| `url` | **yes** | Full download URL (including any query params for pre-signed URLs) |
| `file` | no | Output filename (auto-detected from URL if blank) |
| `sha256` | no | SHA256 checksum for post-download verification (64 hex chars) |
| `notes` | no | Your comments (ignored by the downloader) |

> **Only `url` is required.** The script works fine without `sha256`, `file`, or `notes`. If you don't have a checksum from the vendor, leave the `sha256` cell blank (or omit the column entirely) -- the file downloads normally and verification is skipped. SHA256 is a recommended safety check, not a dependency.

### Example: Vendor Share Link to Spreadsheet

Your vendor gives you:

```
File:           firmware-v2.1.ova
SHA256:         e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
Link:           wget -O firmware-v2.1.ova "https://vendor.s3.amazonaws.com/firmware-v2.1.ova?AWSAccessKeyId=..."
```

Map it to the CSV:

```csv
#,url,file,sha256,notes
1,https://vendor.s3.amazonaws.com/firmware-v2.1.ova?AWSAccessKeyId=...,firmware-v2.1.ova,e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855,
```

---

## At a Glance

![WGET Bulk Downloader — Features and Live Session](docs/banner.png)

---

## How It Works

### Download Flow

```
Spreadsheet (.xlsx/.csv)
    │
    ▼
┌─────────────────────────────────┐
│  Load URLs + filenames + SHA256 │
│  Load manifest (skip completed) │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│  For each file:                 │
│    ├─ Already verified? → SKIP  │
│    ├─ wget -c (resume partial)  │
│    ├─ SHA256 verify (optional)  │
│    ├─ Update manifest           │
│    └─ Human-like pause          │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│  Summary: OK / FAIL / SKIP     │
│  Manifest saved to disk        │
└─────────────────────────────────┘
```

### Resume Across Runs

1. First run: downloads file, verifies SHA256, marks `completed` in manifest
2. Connection drops mid-file: partial file stays on disk, manifest shows `failed`
3. Re-run: completed files skip instantly, partial files resume from last byte
4. All files done: manifest shows everything `completed + SHA256 verified`

### IP Check & VPN Verification

```
  ➤  198.51.100.42

  LOCATION & NETWORK
  ────────────────────────────────────────────────────────────
    Country : United States
    Region  : Example State
    City    : Example City
    ISP     : Example VPN Provider
    Org     : Example Org
    ASN     : AS00000 Example Hosting, Inc.
    Flags   : datacenter/hosting, proxy/VPN detected
  ────────────────────────────────────────────────────────────

  ✓  This looks like a VPN / datacenter IP — good.
```

### Status Dashboard

```
  ✓  📁  firmware-v2.1.ova                    21.3 GB  2026-04-15T12:30
  ✓  📁  OS-1.8.17.ova                        33.0 GB  2026-04-15T13:05
  ✗  ⚠️   OS-1.8.12.ova                        31.2 GB  SHA256 mismatch
  ✗      toolbox-setup.sh                       0.0 B  Never downloaded
  ────────────────────────────────────────────────────────────
  Total: 2 completed (54.3 GB), 2 failed, 0 other
```

---

## Output Structure

```
downloads/
  download_manifest.json          # completion + verification tracking
  firmware-v2.1/
    firmware-v2.1.ova             # downloaded & verified
  toolbox-setup/
    toolbox-setup.sh              # downloaded & verified
```

---

## Use Cases

- **IT / Infrastructure teams** pulling OVA/OVF virtual machine images from vendor portals
- **Security teams** staging firmware and patch files with integrity verification before deployment
- **Ops engineers** batch-downloading from pre-signed AWS S3 or GovCloud URLs
- **Air-gapped environments** where files need to be staged and checksummed before transfer
- **Anyone** tired of babysitting multi-gigabyte downloads over flaky VPN connections
- **Compliance workflows** requiring proof of file integrity via SHA256 verification logs

---

## Keywords

`wget bulk download`, `batch file downloader`, `resume download python`, `sha256 file verification`, `pre-signed S3 URL downloader`, `OVA download tool`, `firmware bulk download`, `download manager CLI`, `wget automation`, `checksum verification tool`, `VPN download tool`, `spreadsheet batch download`, `large file downloader`, `wget resume interrupted download`, `Python download script`

## Contributing

Pull requests, bug reports, and feature suggestions are welcome. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for full guidelines.

**Quick version:**

```bash
# 1. Fork the repo on GitHub
# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/Wget-Downloader-py.git
cd Wget-Downloader-py

# 3. Create a feature branch
git checkout -b feature/your-idea

# 4. Make changes, test locally
python3 wget_downloader.py
python3 -m py_compile wget_downloader.py

# 5. Commit + push + open a PR
git commit -m "Add: your change"
git push origin feature/your-idea
```

**Before opening a PR:**
- Open an issue first for non-trivial changes
- Keep PRs focused (one logical change per PR)
- Test the affected functionality manually
- No new external dependencies without discussion
- No real URLs, AWS keys, or vendor data in commits

**Reporting bugs?** Include OS, Python version, `wget --version`, and reproduction steps.

**Found a security issue?** Don't open a public issue — use [GitHub Security Advisories](https://github.com/fjimenez77/Wget-Downloader-py/security/advisories/new) instead.

## Contributors

- [@fjimenez77](https://github.com/fjimenez77) (Felix J.)
- [@netsecops-76](https://github.com/netsecops-76) (Brian Canaday)
- [@DevForgeAtlas](https://github.com/DevForgeAtlas)

## License

Apache License 2.0 — see [LICENSE](LICENSE) for full text.

```
Copyright 2026 Felix J. (@fjimenez77) and contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
```
