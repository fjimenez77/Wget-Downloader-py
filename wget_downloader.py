#!/usr/bin/env python3
"""
WGET Bulk Downloader v2.0
Human-like · Resume-capable · Privacy-aware
Usage:  python wget_downloader.py
"""

import subprocess
import sys
import os


# ─────────────────────────────────────────────────────────────────
#  DEPENDENCY BOOTSTRAP  (runs before anything else)
# ─────────────────────────────────────────────────────────────────

REQUIRED = {
    "requests": "requests",
    "pandas":   "pandas",
    "openpyxl": "openpyxl",
}

def _check_dependencies():
    """Check all required packages; install any that are missing."""
    missing = []
    for module, package in REQUIRED.items():
        try:
            __import__(module)
        except ImportError:
            missing.append(package)

    if not missing:
        return True   # all good, silent

    print("\n  ┌─────────────────────────────────────────────────┐")
    print(  "  │  Dependency check — installing missing packages │")
    print(  "  └─────────────────────────────────────────────────┘\n")

    all_ok = True
    for pkg in missing:
        print(f"  Installing {pkg} ...", end="", flush=True)
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", pkg, "--quiet"],
            capture_output=True
        )
        if result.returncode == 0:
            print(" ✓")
        else:
            print(f" ✗  FAILED")
            print(f"     {result.stderr.decode().strip()}")
            all_ok = False

    print()
    if all_ok:
        print("  ✓  All dependencies installed successfully.\n")
    else:
        print("  ✗  Some packages failed to install.")
        print("     Try manually:  pip install requests pandas openpyxl\n")
        input("  Press ENTER to continue anyway, or Ctrl+C to exit...")

    return all_ok


def _check_wget():
    """Verify wget is available on the system."""
    try:
        result = subprocess.run(["wget", "--version"], capture_output=True)
        if result.returncode == 0:
            return True
    except FileNotFoundError:
        pass
    print("  ✗  wget is NOT installed or not found in PATH.")
    print("     Linux  : sudo apt install wget")
    print("     macOS  : brew install wget")
    print("     Windows: use WSL or install wget for Windows")
    print()
    input("  Press ENTER to continue anyway, or Ctrl+C to exit...")
    return False


def _startup_check():
    """Run all checks and print a status summary."""
    print("\n  Checking dependencies...")

    deps_ok = _check_dependencies()

    print("  Checking wget...", end="", flush=True)
    wget_ok = _check_wget()
    if wget_ok:
        print(" ✓")

    if deps_ok and wget_ok:
        print("\n  ✅  All systems go. Loading...\n")
        import time as _t; _t.sleep(1)
    else:
        print("\n  ⚠️   Some checks failed — tool may not work fully.\n")
        import time as _t; _t.sleep(2)


_startup_check()


# ─────────────────────────────────────────────────────────────────
#  MAIN IMPORTS  (safe now that packages are installed)
# ─────────────────────────────────────────────────────────────────

import hashlib
import json
import random
import time
from datetime import datetime
from pathlib import Path

try:
    import requests
except ImportError:
    requests = None

try:
    import pandas as pd
except ImportError:
    pd = None


VERSION = "2.0"

LOGO = """
 ██╗    ██╗ ██████╗ ███████╗████████╗    ██████╗ ██╗
 ██║    ██║██╔════╝ ██╔════╝╚══██╔══╝    ██╔══██╗██║
 ██║ █╗ ██║██║  ███╗█████╗     ██║       ██║  ██║██║
 ██║███╗██║██║   ██║██╔══╝     ██║       ██║  ██║██║
 ╚███╔███╔╝╚██████╔╝███████╗   ██║       ██████╔╝███████╗
  ╚══╝╚══╝  ╚═════╝ ╚══════╝   ╚═╝       ╚═════╝ ╚══════╝
       Bulk Downloader  v{v}  |  Human-like & Resume-capable
""".format(v=VERSION)

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
]

VPN_INFO = """
╔══════════════════════════════════════════════════════════════════╗
║           TRAFFIC OBFUSCATION & VPN GUIDE                       ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  WHY YOUR IP MATTERS                                             ║
║  ─────────────────────────────────────────────────────────────  ║
║  Every download logs your IP, timestamp, filename, and bytes    ║
║  transferred in the server's access log. A VPN replaces your    ║
║  real IP with the VPN server's IP address.                      ║
║                                                                  ║
║  WHAT THIS SCRIPT ALREADY DOES                                   ║
║  ─────────────────────────────────────────────────────────────  ║
║  ✓  Rotates browser User-Agent strings (hides wget identity)    ║
║  ✓  Random human-like delays between downloads                   ║
║  ✓  Resume support — never re-downloads what you already have   ║
║  ✓  3 retries + timeout (patient, not bot-like)                  ║
║                                                                  ║
║  WHAT REQUIRES A VPN                                             ║
║  ─────────────────────────────────────────────────────────────  ║
║  ✗  Your real IP is still visible without a VPN                  ║
║  ✗  Your ISP can still see outbound connections without a VPN    ║
║                                                                  ║
║  RECOMMENDED VPN SERVICES                                        ║
║  ─────────────────────────────────────────────────────────────  ║
║                                                                  ║
║  ★  MULLVAD  (mullvad.net)                                       ║
║     Best overall privacy. No account email needed — just a      ║
║     random account number. Accepts cash by mail, Monero, and    ║
║     Bitcoin — no payment trail. Independently audited no-log    ║
║     policy. ~$5/month flat. Windows, Mac, Linux, iOS, Android.  ║
║     Supports WireGuard, OpenVPN, and obfuscated modes.           ║
║                                                                  ║
║  ★  PROTONVPN  (protonvpn.com)                                   ║
║     Reputable, Swiss jurisdiction (strong legal protections).   ║
║     Free tier available (slower, limited servers). Open-source  ║
║     apps, audited no-log policy. Stealth protocol available.    ║
║                                                                  ║
║  ★  IVPN  (ivpn.net)                                             ║
║     Privacy-focused, no-log audited annually. Accepts cash and  ║
║     crypto, no email required. Supports multi-hop (two VPN      ║
║     servers chained) for extra anonymity. WireGuard + OpenVPN.  ║
║                                                                  ║
║  CHECKLIST BEFORE DOWNLOADING                                    ║
║  ─────────────────────────────────────────────────────────────  ║
║  [ ] Connect to VPN                                              ║
║  [ ] Use option [3] in this menu to verify your IP changed      ║
║  [ ] Run the downloader                                          ║
║  [ ] Disconnect VPN when done                                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
"""


# ─────────────────────────────────────────────────────────────────
#  UTILITIES
# ─────────────────────────────────────────────────────────────────

def clear():
    os.system("cls" if os.name == "nt" else "clear")

def pause():
    input("\n  Press ENTER to return to menu...")

def divider(char="─", width=60):
    print("  " + char * width)

def find_column(df, candidates):
    lower_map = {c.lower(): c for c in df.columns}
    for c in candidates:
        if c.lower() in lower_map:
            return lower_map[c.lower()]
    return None

def filename_from_url(url):
    return url.rstrip("/").split("/")[-1].split("?")[0]

def safe_filename(name):
    """Strip any path components — reject traversal attempts.
    Returns a bare filename (no slashes, no '..'), or '' if unsafe."""
    if not name:
        return ""
    # Take only the final path component, reject any traversal
    bare = Path(name).name
    if bare in ("", ".", "..") or bare != name.replace("\\", "/").split("/")[-1]:
        return ""
    return bare

def load_spreadsheet(path):
    ext = Path(path).suffix.lower()
    if ext in (".xlsx", ".xlsm", ".xls"):
        return pd.read_excel(path, dtype=str)
    elif ext in (".csv", ".tsv"):
        return pd.read_csv(path, dtype=str, sep="\t" if ext == ".tsv" else ",")
    else:
        try:
            return pd.read_excel(path, dtype=str)
        except Exception:
            return pd.read_csv(path, dtype=str)

def human_pause(min_sec=4.0, max_sec=15.0):
    delay = random.uniform(min_sec, max_sec)
    print(f"\n  ⏱  Human pause: {delay:.1f}s ...", end="", flush=True)
    time.sleep(delay)
    print(" go.")

MANIFEST_FILE = "download_manifest.json"

def load_manifest(output_dir):
    """Load manifest from output dir. Returns empty dict if missing."""
    path = Path(output_dir) / MANIFEST_FILE
    if path.exists():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
    return {}

def save_manifest(output_dir, manifest):
    """Atomically write manifest (write tmp, then rename)."""
    path = Path(output_dir) / MANIFEST_FILE
    tmp  = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(manifest, indent=2))
    tmp.replace(path)

def update_manifest(manifest, filename, url, status, size_bytes=0, error=None):
    """Update a single entry in the manifest dict (in memory)."""
    entry = manifest.get(filename, {"attempts": 0})
    entry.update({
        "url":          url,
        "status":       status,
        "size_bytes":   size_bytes,
        "attempts":     entry.get("attempts", 0) + (1 if status != "skipped" else 0),
        "error":        error,
    })
    if status == "completed":
        entry["completed_at"] = datetime.now().isoformat(timespec="seconds")
    manifest[filename] = entry
    return manifest

def is_already_complete(manifest, filename, dest_path):
    """Check if file is completed in manifest AND exists on disk at expected size."""
    entry = manifest.get(filename)
    if not entry or entry.get("status") != "completed":
        return False
    if not dest_path.exists():
        return False
    # If we recorded a size, verify it still matches
    expected = entry.get("size_bytes", 0)
    if expected > 0 and dest_path.stat().st_size != expected:
        return False
    return True

def human_size(nbytes):
    """Format byte count as human-readable string."""
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(nbytes) < 1024:
            return f"{nbytes:.1f} {unit}"
        nbytes /= 1024
    return f"{nbytes:.1f} PB"


def verify_sha256(file_path, expected_hash):
    """Compute SHA256 of a file and compare with expected hash.
    Returns (matched: bool, actual_hash: str).
    Reads in 8 MB chunks to handle large OVAs without eating all RAM."""
    sha = hashlib.sha256()
    size = Path(file_path).stat().st_size
    done = 0
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(8 * 1024 * 1024)   # 8 MB
            if not chunk:
                break
            sha.update(chunk)
            done += len(chunk)
            pct = done * 100 / size if size else 100
            print(f"\r  🔒  Verifying SHA256... {pct:.0f}%", end="", flush=True)
    actual = sha.hexdigest()
    matched = actual.lower() == expected_hash.lower()
    if matched:
        print(f"\r  🔒  SHA256 VERIFIED ✓                     ")
    else:
        print(f"\r  🔒  SHA256 MISMATCH ✗                     ")
        print(f"       Expected : {expected_hash.lower()}")
        print(f"       Got      : {actual}")
    return matched, actual


def wget_download(url, dest_path, user_agent):
    """
    Download <url> to <dest_path>, with resume support via -c -O.

    Uses -c -O which works for single-URL-to-single-file downloads when
    the server supports Range headers (S3 does). The partial file keeps
    its target name, so re-runs resume seamlessly.

    wget flags:
      -c               resume partial download
      -O               explicit output path (predictable name for resume)
      --show-progress  keep progress bar visible
      --tries 3        retry up to 3 times on error
      --timeout 60     abort stalled connection after 60s
    """
    dest_path = Path(dest_path)
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "wget",
        "-c",
        "-O", str(dest_path),
        "--user-agent", user_agent,
        "--no-verbose",
        "--show-progress",
        "--progress=bar:force:noscroll",
        "--tries", "3",
        "--timeout", "60",
        url,
    ]
    print(f"  ↓  UA : {user_agent[:58]}...")
    if dest_path.exists() and dest_path.stat().st_size > 0:
        mb = dest_path.stat().st_size / 1048576
        print(f"  ↻  Resuming from {mb:.1f} MB partial file")
    else:
        print(f"  ↻  Starting fresh download")

    try:
        rc = subprocess.run(cmd).returncode
    except FileNotFoundError:
        print("  [FAIL] wget not found on PATH.")
        return False

    return rc == 0 and dest_path.exists()


# ─────────────────────────────────────────────────────────────────
#  MENU ACTIONS
# ─────────────────────────────────────────────────────────────────

def check_ip():
    clear()
    print(LOGO)
    divider("═")
    print("  CHECK CURRENT PUBLIC IP ADDRESS")
    divider("═")

    if requests is None:
        print("\n  [ERROR] 'requests' not installed.")
        print("  Run:  pip install requests")
        pause()
        return

    services = [
        ("https://api.ipify.org?format=json", lambda r: r.json().get("ip")),
        ("https://ip.me/",                    lambda r: r.text.strip()),
        ("https://ifconfig.me/ip",            lambda r: r.text.strip()),
    ]

    ip = None
    for url, extractor in services:
        try:
            print(f"\n  Querying {url} ...")
            r = requests.get(url, timeout=8)
            ip = extractor(r)
            if ip:
                break
        except Exception as e:
            print(f"  ✗ {url} unreachable: {e}")

    print()
    if ip:
        divider()
        print(f"  Your current public IP address:")
        print(f"\n      ➤  {ip}\n")
        divider()

        # Geo / ISP lookup — ip-api.com is free, no auth, 45 req/min
        geo = None
        try:
            print(f"\n  Looking up location for {ip} ...")
            r = requests.get(
                f"http://ip-api.com/json/{ip}"
                "?fields=status,country,regionName,city,isp,org,as,proxy,hosting",
                timeout=8,
            )
            data = r.json()
            if data.get("status") == "success":
                geo = data
        except Exception as e:
            print(f"  ✗ Geolocation lookup failed: {e}")

        if geo:
            print()
            divider()
            print("  LOCATION & NETWORK")
            divider()
            print(f"    Country : {geo.get('country', '?')}")
            print(f"    Region  : {geo.get('regionName', '?')}")
            print(f"    City    : {geo.get('city', '?')}")
            print(f"    ISP     : {geo.get('isp', '?')}")
            print(f"    Org     : {geo.get('org', '?') or '(none)'}")
            print(f"    ASN     : {geo.get('as', '?')}")
            flags = []
            if geo.get("hosting"):
                flags.append("datacenter/hosting")
            if geo.get("proxy"):
                flags.append("proxy/VPN detected")
            if flags:
                print(f"    Flags   : {', '.join(flags)}")
            divider()

            print()
            if geo.get("hosting") or geo.get("proxy"):
                print("  ✓  This looks like a VPN / datacenter IP — good.")
            else:
                print("  ⚠  This looks like a residential ISP — VPN may NOT be active.")
                print("     Double-check your VPN client before downloading.")
        else:
            print()
            print("  ℹ  If connected to a VPN this should be the VPN server's IP.")
            print("     If it shows your real home/office IP, VPN is NOT active.")
    else:
        print("  [FAIL] Could not retrieve IP from any service.")
        print("         Check your internet connection.")

    pause()


def show_vpn_info():
    clear()
    print(LOGO)
    print(VPN_INFO)
    pause()


def run_downloads():
    clear()
    print(LOGO)
    divider("═")
    print("  DOWNLOAD FROM FILE")
    divider("═")

    if pd is None:
        print("\n  [ERROR] 'pandas' not installed.")
        print("  Run:  pip install pandas openpyxl")
        pause()
        return

    print()

    # Auto-discover spreadsheet files in the current working directory.
    # Skips the template (empty by default) and Excel lock files (~$foo.xlsx).
    cwd = Path.cwd()
    candidates = sorted(
        p for p in cwd.iterdir()
        if p.is_file()
        and p.suffix.lower() in (".xlsx", ".xlsm", ".xls", ".csv", ".tsv")
        and not p.name.startswith("~$")
    )

    file_path = ""
    if candidates:
        print(f"  Spreadsheet files found in {cwd}:\n")
        for i, p in enumerate(candidates, 1):
            size_kb = p.stat().st_size / 1024
            print(f"    [{i}]  {p.name}   ({size_kb:.1f} KB)")
        print(f"    [0]  Enter a path manually")
        print()

        choice = input("  Select file: ").strip()
        if choice.isdigit():
            idx = int(choice)
            if 1 <= idx <= len(candidates):
                file_path = str(candidates[idx - 1])
                print(f"  → {candidates[idx - 1].name}")
            elif idx == 0:
                file_path = input("  Path to .xlsx or .csv file: ").strip().strip('"').strip("'")
        else:
            # User typed a path directly instead of a number
            file_path = choice.strip('"').strip("'")
    else:
        print(f"  No spreadsheet files found in {cwd}")
        file_path = input("  Path to .xlsx or .csv file: ").strip().strip('"').strip("'")

    if not file_path or not os.path.exists(file_path):
        print(f"\n  [ERROR] File not found: '{file_path}'")
        pause()
        return

    out = input("  Output folder [downloads]: ").strip()
    output_dir = out if out else "downloads"

    try:
        mn = input("  Min delay between files in seconds [4]: ").strip()
        mx = input("  Max delay between files in seconds [15]: ").strip()
        min_wait = float(mn) if mn else 4.0
        max_wait = float(mx) if mx else 15.0
    except ValueError:
        min_wait, max_wait = 4.0, 15.0

    # Clamp + swap if user entered non-sensical values
    if min_wait < 0:
        min_wait = 0.0
    if max_wait < 0:
        max_wait = 0.0
    if min_wait > max_wait:
        print(f"  [WARN] min ({min_wait}) > max ({max_wait}); swapping.")
        min_wait, max_wait = max_wait, min_wait

    print(f"\n  Loading spreadsheet...")
    df = load_spreadsheet(file_path)
    df.dropna(how="all", inplace=True)
    df.columns = df.columns.str.strip()

    url_col  = find_column(df, ["url","link","download_url","download url","uri"])
    file_col = find_column(df, ["file","filename","file_name","name","output"])
    sha_col  = find_column(df, ["sha256","sha256 checksum","sha256_checksum",
                                 "checksum","sha","hash"])

    if url_col is None:
        print(f"\n  [ERROR] No URL column found.")
        print(f"  Columns detected: {list(df.columns)}")
        print(f"  Rename a column to 'url' and try again.")
        pause()
        return

    rows = [
        (idx, row) for idx, row in df.iterrows()
        if pd.notna(row.get(url_col))
        and str(row[url_col]).strip().lower() not in ("", "nan", "none", "url")
    ]
    total = len(rows)

    print(f"  URL column   : '{url_col}'")
    print(f"  File column  : '{file_col or 'auto from URL'}'")
    print(f"  SHA256 column: '{sha_col or 'none — no verification'}'")
    print(f"  Delay range  : {min_wait}–{max_wait}s")
    print(f"  Total URLs   : {total}")

    if total == 0:
        print("\n  [INFO] No valid URLs found in the file.")
        pause()
        return

    base_dir = Path(output_dir)
    base_dir.mkdir(parents=True, exist_ok=True)

    # Load manifest from previous run (if any)
    manifest = load_manifest(base_dir)
    prev_completed = sum(1 for e in manifest.values() if e.get("status") == "completed")
    if prev_completed:
        print(f"\n  ℹ  Manifest found: {prev_completed} file(s) already completed — will skip.")

    print()
    divider()
    proceed = input("  Start downloading? [Y/n]: ").strip().lower()
    if proceed == "n":
        return

    ok_count = fail_count = skip_count = verify_fail = 0

    try:
        for pos, (idx, row) in enumerate(rows):
            url = str(row[url_col]).strip()
            raw_filename = (
                str(row[file_col]).strip()
                if file_col and pd.notna(row.get(file_col))
                else filename_from_url(url)
            )

            # Get expected SHA256 if column exists
            expected_sha = None
            if sha_col and pd.notna(row.get(sha_col)):
                val = str(row[sha_col]).strip()
                if len(val) == 64:   # valid SHA256 hex length
                    expected_sha = val

            if not raw_filename or raw_filename.lower() in ("nan", "none", ""):
                print(f"\n  [SKIP] Row {idx+1}: cannot determine filename.")
                skip_count += 1
                continue

            filename = safe_filename(raw_filename)
            if not filename:
                print(f"\n  [SKIP] Row {idx+1}: unsafe filename '{raw_filename}' "
                      f"(path traversal blocked).")
                skip_count += 1
                continue

            folder = base_dir / Path(filename).stem
            dest   = folder / filename

            # ── Smart skip: check manifest for already-completed files ──
            if is_already_complete(manifest, filename, dest):
                size = dest.stat().st_size
                print(f"\n  [{pos+1}/{total}] {filename}")
                print(f"  [SKIP] Already completed ({human_size(size)})")
                skip_count += 1
                continue

            print(f"\n  [{pos+1}/{total}] {filename}")
            print(f"  URL    : {url}")
            print(f"  Folder : {folder}")
            if expected_sha:
                print(f"  SHA256 : {expected_sha[:16]}...{expected_sha[-8:]}")

            ua = random.choice(USER_AGENTS)

            if wget_download(url, dest, ua):
                size = dest.stat().st_size if dest.exists() else 0
                print(f"  [OK]  {human_size(size)}  →  {dest}")

                # SHA256 verification (if checksum provided)
                sha_ok = True
                if expected_sha and dest.exists():
                    sha_ok, actual_sha = verify_sha256(dest, expected_sha)
                    if not sha_ok:
                        verify_fail += 1
                        update_manifest(manifest, filename, url, "sha256_mismatch",
                                        size, f"expected {expected_sha[:16]}...")
                        save_manifest(base_dir, manifest)
                        fail_count += 1
                        if pos < total - 1:
                            human_pause(min_wait, max_wait)
                        continue

                update_manifest(manifest, filename, url, "completed", size)
                save_manifest(base_dir, manifest)
                ok_count += 1
            else:
                size = dest.stat().st_size if dest.exists() else 0
                print(f"  [FAIL] wget error — partial file kept for resume.")
                update_manifest(manifest, filename, url, "failed", size,
                                "wget non-zero exit")
                save_manifest(base_dir, manifest)
                fail_count += 1

            if pos < total - 1:
                human_pause(min_wait, max_wait)

    except KeyboardInterrupt:
        print("\n\n  ⚠  Interrupted by user (Ctrl+C)")
        print("  Saving manifest...")
        save_manifest(base_dir, manifest)

    print("\n  " + "═" * 58)
    summary = f"  DONE   ✓ {ok_count} downloaded   ✗ {fail_count} failed   ⊘ {skip_count} skipped"
    if verify_fail:
        summary += f"   🔒 {verify_fail} checksum mismatch"
    print(summary)
    print(f"  Manifest : {(base_dir / MANIFEST_FILE).resolve()}")
    print(f"  Files    : {base_dir.resolve()}")
    print("  " + "═" * 58)
    pause()


def view_status():
    clear()
    print(LOGO)
    divider("═")
    print("  DOWNLOAD STATUS")
    divider("═")

    out = input("\n  Output folder [downloads]: ").strip()
    output_dir = out if out else "downloads"
    base_dir = Path(output_dir)

    manifest = load_manifest(base_dir)
    if not manifest:
        print(f"\n  No manifest found in '{base_dir}'.")
        print(f"  Run a download first to generate one.")
        pause()
        return

    print()
    divider()

    completed = failed = other = 0
    total_bytes = 0
    status_icon = {
        "completed": "✓",
        "failed": "✗",
        "sha256_mismatch": "🔒✗",
    }

    for filename, entry in manifest.items():
        st = entry.get("status", "?")
        icon = status_icon.get(st, "?")
        size = entry.get("size_bytes", 0)
        total_bytes += size if st == "completed" else 0
        ts = entry.get("completed_at", "")[:16] if st == "completed" else ""
        err = entry.get("error", "") or ""
        attempts = entry.get("attempts", 0)

        # Check if file still exists on disk
        folder = base_dir / Path(filename).stem
        dest = folder / filename
        on_disk = "📁" if dest.exists() else "⚠️"

        info = ts if st == "completed" else err
        print(f"  {icon}  {on_disk}  {filename:<40s}  {human_size(size):>10s}  {info}")
        if st == "completed":
            completed += 1
        elif st in ("failed", "sha256_mismatch"):
            failed += 1
        else:
            other += 1

    divider()
    print(f"\n  Total: {completed} completed ({human_size(total_bytes)}), "
          f"{failed} failed, {other} other")
    print(f"  Manifest: {(base_dir / MANIFEST_FILE).resolve()}")
    pause()


def generate_template():
    clear()
    print(LOGO)
    divider("═")
    print("  GENERATE DOWNLOAD TEMPLATE")
    divider("═")

    print("""
  This creates a blank CSV template with all the correct
  headers for the downloader. Fill it in and use option [1].

  COLUMNS
  ─────────────────────────────────────────────────────
  #       Row number (auto-filled)
  url     Full download URL (required)
            e.g. https://vendor.s3.amazonaws.com/file.ova?AWSAccessKeyId=...
  file    Output filename (optional — auto-detected from URL)
            e.g. firmware-v2.1.ova
  sha256  SHA256 checksum from vendor (optional)
            e.g. c1cfa83b7539202b9ac91e6e7cb1fff9005b23c97b1e25d98a1a6d0c38644f2a
            If provided, the file is verified after download.
            Leave blank if you don't have it.
  notes   Your comments (ignored by downloader)
""")
    divider()

    name = input("\n  Template filename [download_template.csv]: ").strip()
    if not name:
        name = "download_template.csv"
    if not name.endswith(".csv"):
        name += ".csv"

    try:
        rows_input = input("  Number of empty rows [50]: ").strip()
        num_rows = int(rows_input) if rows_input else 50
    except ValueError:
        num_rows = 50

    # Build CSV content
    lines = ["#,url,file,sha256,notes"]
    for i in range(1, num_rows + 1):
        lines.append(f"{i},,,,")

    path = Path(name)
    path.write_text("\n".join(lines) + "\n")

    print(f"\n  ✓  Template created: {path.resolve()}")
    print(f"     {num_rows} empty rows ready to fill")
    print()
    print("  HOW TO FILL IT IN")
    print("  ─────────────────────────────────────────────────────")
    print("  Your vendor gives you something like:")
    print()
    print("    File:           firmware-v2.1.ova")
    print('    SHA256:         c1cfa83b7539202b...')
    print('    Link:           wget -O firmware-v2.1.ova "https://..."')
    print()
    print("  Copy into the CSV:")
    print('    url   = the https://... URL (without quotes, without "wget -O")')
    print("    file  = firmware-v2.1.ova")
    print("    sha256= the full 64-character hash")
    print("    notes = whatever you want (or leave blank)")

    pause()


def show_help():
    clear()
    print(LOGO)
    divider("═")
    print("  QUICK START GUIDE")
    divider("═")
    print("""
  SPREADSHEET FORMAT  (.xlsx or .csv)
  ─────────────────────────────────────────────────────
  Use option [6] to generate a blank template, or open
  downloads_template.xlsx.

  Column  │ Required │ Description
  ────────┼──────────┼─────────────────────────────────
  url     │ YES      │ Full https:// download URL
  file    │ no       │ Filename e.g. erf-OS-1.8.17.ova
  sha256  │ no       │ SHA256 checksum (64 hex chars)
  notes   │ no       │ Your comments (ignored)

  If 'file' is blank the name is extracted from the URL.
  If 'sha256' is provided, the file is verified after
  download. Leave blank if you don't have a checksum.

  RESUME & TRACKING
  ─────────────────────────────────────────────────────
  If a download is interrupted, just run again.
  wget -c picks up from exactly where it left off.
  Completed files are tracked in download_manifest.json
  and automatically skipped on re-run.

  PRIVACY CHECKLIST
  ─────────────────────────────────────────────────────
  1. Connect to VPN (see option [2] for recommendations)
  2. Verify IP changed — use option [3]
  3. Run the downloader
  4. Default delay: 4–15s random pause between files
     (increase for lower detection profile)

  INSTALL REQUIREMENTS
  ─────────────────────────────────────────────────────
  pip install pandas openpyxl requests

  wget must be on your system:
    Linux   →  sudo apt install wget
    macOS   →  brew install wget
    Windows →  use WSL or wget for Windows
""")
    pause()


# ─────────────────────────────────────────────────────────────────
#  MAIN MENU
# ─────────────────────────────────────────────────────────────────

def main():
    while True:
        clear()
        print(LOGO)
        divider("═")
        print("  MAIN MENU")
        divider("═")
        print("""
  [1]  Download from file          (.xlsx or .csv)
  [2]  Traffic obfuscation guide   (VPN info & tips)
  [3]  Check my current public IP
  [4]  Quick start & help
  [5]  View download status        (manifest report)
  [6]  Generate download template  (blank .csv)
  [0]  Exit
""")
        divider()
        choice = input("  Select option: ").strip()

        if   choice == "1":  run_downloads()
        elif choice == "2":  show_vpn_info()
        elif choice == "3":  check_ip()
        elif choice == "4":  show_help()
        elif choice == "5":  view_status()
        elif choice == "6":  generate_template()
        elif choice == "0":
            clear()
            print("\n  Goodbye.\n")
            sys.exit(0)
        else:
            print("  Invalid option.")
            time.sleep(1)


if __name__ == "__main__":
    main()
