# Contributing to WGET Bulk Downloader

Thanks for considering a contribution! This project is intentionally small and focused — a single-file CLI tool that does one thing well. PRs and issues are welcome.

## Ways to Contribute

- 🐛 **Report bugs** — open an issue with reproduction steps
- 💡 **Suggest features** — open an issue describing the use case first
- 🔧 **Submit fixes** — small focused PRs are easier to review and merge
- 📖 **Improve docs** — README clarifications, typo fixes, better examples
- 🧪 **Test on platforms** — Linux/macOS/Windows-WSL feedback is valuable
- ⭐ **Star the repo** — helps visibility

## Reporting Issues

Before opening an issue, please:

1. **Search existing issues** to avoid duplicates
2. **Try the latest `main` branch** — your bug may already be fixed
3. **Include reproduction steps**:
   - OS + Python version (`python3 --version`)
   - wget version (`wget --version | head -1`)
   - The exact menu options/inputs you used
   - Full error message or relevant output

### Issue Template

```
**Environment**
- OS: macOS 14.4 / Ubuntu 22.04 / Windows 11 WSL2
- Python: 3.11.5
- wget: 1.25.0

**What I did**
1. Ran `python3 wget_downloader.py`
2. Selected option [1]
3. Picked `my_urls.csv`
4. ...

**What I expected**
The download to resume from byte 850 MB.

**What happened**
Download restarted from 0.

**Output**
[paste relevant terminal output]
```

## Pull Request Guidelines

### Before You Start

- **Open an issue first** for non-trivial changes. Avoids wasted effort if the feature doesn't fit the project's scope.
- **Keep it focused** — one logical change per PR. Don't mix a bug fix with a new feature.
- **Match the existing style** — the codebase is intentionally a single file, no frameworks, minimal dependencies.

### Development Setup

```bash
# Fork the repo on GitHub, then:
git clone https://github.com/YOUR_USERNAME/Wget-Downloader-py.git
cd Wget-Downloader-py

# Create a feature branch
git checkout -b feature/your-feature-name

# Make your changes, test locally
python3 wget_downloader.py

# Verify Python syntax
python3 -m py_compile wget_downloader.py
```

### Code Style

- **Python 3.9+** compatible (avoid 3.10+ syntax like `match` statements)
- **No new dependencies** unless absolutely necessary — keep `requests`, `pandas`, `openpyxl` as the only third-party packages
- **Single file** — `wget_downloader.py` stays the only Python file
- **Comments where logic isn't obvious** — explain the *why*, not the *what*
- **No type hints required** but welcome for public functions
- **Match existing formatting** — 4-space indent, double quotes for strings, `divider()` for visual separators

### Testing Your Changes

The project doesn't have a formal test suite (yet). Please manually verify:

1. **Syntax check**: `python3 -m py_compile wget_downloader.py`
2. **Smoke test the menu**: launch the script, exercise each menu option
3. **Test edge cases** for whatever you changed:
   - Empty spreadsheet
   - Missing `wget` on PATH
   - Interrupted download (Ctrl+C mid-transfer)
   - Bad URL (404, 403, timeout)
   - SHA256 mismatch
   - Path traversal attempts (`../../etc/passwd`)

### Commit Messages

Follow conventional commit style:

```
Short summary in imperative mood (under 70 chars)

Optional longer body explaining the change, motivation,
and any context reviewers need.

Closes #42
```

Examples:
- `Fix wget -c resume across runs`
- `Add SHA256 verification on download completion`
- `Improve error message when wget is missing`

### Pull Request Checklist

- [ ] Branch is up to date with `main`
- [ ] Python syntax check passes (`python3 -m py_compile wget_downloader.py`)
- [ ] Manually tested the affected functionality
- [ ] No real URLs, AWS keys, or vendor-specific data committed
- [ ] README updated if user-facing behavior changed
- [ ] Commit messages are clear

### What We Won't Merge

- New external dependencies without strong justification
- Breaking changes to spreadsheet column format without backward compat
- Multi-file refactors that fragment the codebase
- Features that compromise the single-file CLI design
- Anything that leaks user data, real URLs, or credentials in examples

## Security

If you discover a security vulnerability:

- **Do NOT open a public issue**
- Email the maintainer or open a [security advisory](https://github.com/fjimenez77/Wget-Downloader-py/security/advisories/new)
- Allow reasonable time for a fix before public disclosure

## Code of Conduct

Be respectful. Assume good intent. Disagree with ideas, not people.

## Recognition

All contributors are credited in the README. Significant contributions get co-authored commits via `Co-Authored-By` in git history.

## Questions?

Open a [Discussion](https://github.com/fjimenez77/Wget-Downloader-py/discussions) or an issue tagged `question`.

---

Thanks for helping make this tool better.
