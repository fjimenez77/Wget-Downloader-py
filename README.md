# WGET Bulk Downloader - Batch File Download Manager with Resume & Checksum Verification

A Python CLI bulk download manager with resume capability, SHA256 checksum verification, and privacy features. Built on `wget` for downloading large files (OVA images, firmware, ISO, virtual appliances) from pre-signed AWS S3 URLs, Azure Blob Storage, or any HTTP/HTTPS source. Supports batch downloading from spreadsheets (Excel `.xlsx`, `.csv`) with automatic retry, user-agent rotation, and VPN integration.

```
 ██╗    ██╗ ██████╗ ███████╗████████╗    ██████╗ ██╗
 ██║    ██║██╔════╝ ██╔════╝╚══██╔══╝    ██╔══██╗██║
 ██║ █╗ ██║██║  ███╗█████╗     ██║       ██║  ██║██║
 ██║███╗██║██║   ██║██╔══╝     ██║       ██║  ██║██║
 ╚███╔███╔╝╚██████╔╝███████╗   ██║       ██████╔╝███████╗
  ╚══╝╚══╝  ╚═════╝ ╚══════╝   ╚═╝       ╚═════╝ ╚══════╝
```

## Features

- **Resume support** -- interrupted downloads pick up where they left off via `wget -c`
- **SHA256 verification** -- optional per-file checksum validation after download
- **Download manifest** -- `download_manifest.json` tracks completion status; re-runs skip verified files
- **User-Agent rotation** -- cycles through real browser UA strings to avoid bot detection
- **Human-like delays** -- configurable random pauses between downloads (default 4-15s)
- **VPN guidance** -- built-in IP checker with geolocation + VPN recommendations
- **Spreadsheet input** -- reads `.xlsx`, `.csv`, or `.tsv` files
- **Auto file discovery** -- scans current directory for spreadsheets on startup
- **Graceful interrupts** -- Ctrl+C saves manifest and returns to menu cleanly
- **Template generator** -- creates blank CSV templates with correct headers

## Requirements

- **Python 3.7+**
- **wget** (`brew install wget` on macOS, `sudo apt install wget` on Linux)
- Python packages: `requests`, `pandas`, `openpyxl` (auto-installed on first run)

## Quick Start

```bash
# Clone
git clone https://github.com/fjimenez77/Wget-Downloader-py.git
cd Wget-Downloader-py

# Run
python3 bulk_downloader.py
```

On first run, the script checks for dependencies and installs any missing packages automatically.

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

## Spreadsheet Format

Use option **[6]** to generate a blank template, or fill in the included `downloads_template.xlsx`.

| Column | Required | Description |
|--------|----------|-------------|
| `#` | no | Row number |
| `url` | **yes** | Full download URL (including any query params for pre-signed URLs) |
| `file` | no | Output filename (auto-detected from URL if blank) |
| `sha256` | no | SHA256 checksum for post-download verification (64 hex chars) |
| `notes` | no | Your comments (ignored by the downloader) |

### Example: Vendor Share Link to Spreadsheet

Your vendor gives you:

```
File:           firmware-v2.1.ova
SHA256:         c1cfa83b7539202b9ac91e6e7cb1fff9005b23c97b1e25d98a1a6d0c38644f2a
Link:           wget -O firmware-v2.1.ova "https://vendor.s3.amazonaws.com/firmware-v2.1.ova?AWSAccessKeyId=..."
```

Map it to the CSV:

```csv
#,url,file,sha256,notes
1,https://vendor.s3.amazonaws.com/firmware-v2.1.ova?AWSAccessKeyId=...,firmware-v2.1.ova,c1cfa83b7539202b9ac91e6e7cb1fff9005b23c97b1e25d98a1a6d0c38644f2a,
```

## How Resume Works

1. Files download to `downloads/<filename_stem>/<filename>`
2. `wget -c` resumes partial files on re-run
3. `download_manifest.json` tracks what completed successfully
4. On re-run, completed + verified files are **skipped instantly**
5. Failed or interrupted files are **retried automatically**

## Privacy & VPN

The script includes a built-in privacy toolkit:

- **Option [3]** checks your public IP with geolocation -- confirms VPN is active
- **Option [2]** provides VPN recommendations (Mullvad, ProtonVPN, IVPN)
- **User-Agent rotation** hides `wget` identity from server logs
- **Random delays** between downloads avoid bot-like traffic patterns

> The script does NOT hide your IP address. Use a VPN for that.

## Output Structure

```
downloads/
  download_manifest.json          # completion tracking
  firmware-v2.1/
    firmware-v2.1.ova             # downloaded file
  toolbox-setup/
    toolbox-setup.sh              # downloaded file
```

## Use Cases

- Bulk downloading OVA/OVF virtual machine images from vendor portals
- Batch firmware downloads with integrity verification
- Automated file retrieval from pre-signed AWS S3 or GovCloud URLs
- Large ISO/archive downloads over unstable or VPN connections
- Downloading files from vendor share links (wget commands) at scale
- Air-gapped environment file staging with checksum validation

## Keywords

`wget bulk download`, `batch file downloader`, `resume download python`, `sha256 file verification`, `pre-signed S3 URL downloader`, `OVA download tool`, `firmware bulk download`, `download manager CLI`, `wget automation`, `checksum verification tool`, `VPN download tool`, `spreadsheet batch download`, `large file downloader`, `wget resume interrupted download`, `Python download script`

## License

MIT
