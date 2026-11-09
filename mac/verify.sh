#!/bin/bash
set -euo pipefail
if [ "$#" -gt 0 ]; then xls_fixture="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; fi
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
server=""
mount_dir="$test_dir/mount"
mounted=false
mkdir "$mount_dir"
cleanup() {
    if [ -n "$server" ]; then
        kill "$server" 2>/dev/null || true
        wait "$server" 2>/dev/null || true
    fi
    if "$mounted"; then hdiutil detach "$mount_dir" >/dev/null; fi
    rm -rf "$test_dir"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "dist/Wget Downloader.dmg" >/dev/null
mounted=true
app="$mount_dir/Wget Downloader.app"
codesign --verify --deep --strict "$app"
test "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" = "AppIcon"
test -s "$app/Contents/Resources/AppIcon.icns"
cmp LICENSE "$mount_dir/Apache-2.0 License.txt"
cmp mac/vendor/libxls/LICENSE "$mount_dir/libxls BSD-2-Clause License.txt"
test "$(plutil -extract URL raw "$mount_dir/Wget Downloader on GitHub.webloc")" = "https://github.com/fjimenez77/Wget-Downloader-py"
test "$(plutil -extract NSHumanReadableCopyright raw "$app/Contents/Info.plist")" = "Copyright © 2026 Felix J. (@fjimenez77) and contributors"
grep -Fq 'Copyright © 2026 Felix J. (@fjimenez77) and contributors' "$mount_dir/About Wget Downloader.txt"
echo "Disk image attribution, license texts, and GitHub shortcut verified."
if [ -n "${xls_fixture:-}" ]; then
    "$app/Contents/MacOS/ReadLegacyExcel" "$xls_fixture" > "$test_dir/legacy.csv"
    test -s "$test_dir/legacy.csv"
    echo "Bundled legacy Excel reader converted the .xls fixture."
fi
open -n "$app"
sleep 1
pid=$(ps -axo pid=,comm= | awk -v binary="$(cd "$mount_dir" && pwd -P)/Wget Downloader.app/Contents/MacOS/Downloader" 'index($0,binary) { print $1; exit }')
test -n "$pid"
kill "$pid"
echo "Packaged app launches and its signature is valid."
cat > "$test_dir/server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import sys
root = Path(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        (root/'agent').write_text(self.headers.get('User-Agent', ''))
        offset = int(self.headers.get('Range','bytes=0-').split('=')[1].split('-')[0])
        (root/'offset').write_text(str(offset))
        self.send_response(206 if offset else 200)
        self.send_header('Content-Length', str(5-offset))
        if offset: self.send_header('Content-Range', f'bytes {offset}-4/5')
        self.end_headers()
        self.wfile.write(b'hello'[offset:])
server = HTTPServer(('127.0.0.1',0),Handler)
(root/'port').write_text(str(server.server_port))
server.serve_forever()
PY
python3 "$test_dir/server.py" "$test_dir" > "$test_dir/server.log" 2>&1 &
server=$!
for attempt in {1..40}; do [ -f "$test_dir/port" ] && break; sleep .1; done
sed '/^@main/,$d' mac/Downloader.swift > "$test_dir/Checks.swift"
cat >> "$test_dir/Checks.swift" <<'SWIFT'
@main
struct Checks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let template = URL(fileURLWithPath: CommandLine.arguments[2])
        let templateRows = try readRows(template)
        precondition(templateRows[0].contains("url"))
        let port = try String(contentsOf: root.appendingPathComponent("port"), encoding: .utf8)
        let url = "http://127.0.0.1:\(port)/file?token=example"
        let hash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let signed = "https://example.invalid/upgrade/file.sh?AWSAccessKeyId=TEST&Signature=a%2Bb%3D&Expires=2000000000"
        let link = "[\(signed)](\(signed.replacingOccurrences(of: "&", with: #"\&"#)))"
        let vendor = try pastedJobs("""
        **Download URL**
        \(link)
        **SHA-256 checksum**
        \(hash)
        **wget command**
        wget -O firmware.sh "\(link)"
        **Checksum + wget**
        Checksum: \(hash) wget -O firmware.sh "\(link)"
        """)
        precondition(vendor.count == 1 && vendor[0].url.absoluteString == signed)
        precondition(vendor[0].name == "firmware.sh" && vendor[0].hash == hash)
        let combined = try pastedJobs("Checksum: \(hash) wget -O firmware.sh \(signed)")
        precondition(combined.first?.hash == hash)
        let queue = Queue()
        try queue.addLinks("wget -c -O 'resume file.txt' '\(url)'\n\(url)\tchecked.txt\t\(hash)")
        precondition(queue.jobs.map(\.name) == ["resume file.txt", "checked.txt"])
        let bad = try? pastedJobs("wget -O ../bad '\(url)'")
        precondition(bad == nil)
        let destination = destinationURL(root, "resume file.txt")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("he".utf8).write(to: destination)
        try JSONEncoder().encode(["resume file.txt": Record(url: url, status: "failed", size_bytes: 2, attempts: 1)])
            .write(to: historyURL(root))
        queue.folder = root
        let second = queue.jobs.removeLast()
        await queue.start(minimumDelay: 0, maximumDelay: 0)
        precondition(queue.jobs[0].status == "Downloaded", queue.jobs[0].status)
        let range = try String(contentsOf: root.appendingPathComponent("offset"), encoding: .utf8)
        precondition(range == "2")
        let agent = try String(contentsOf: root.appendingPathComponent("agent"), encoding: .utf8)
        precondition(browserAgents.contains(agent))
        queue.jobs.append(second)
        await queue.start(minimumDelay: 0, maximumDelay: 0, rotateAgent: false)
        precondition(queue.jobs[1].status == "Verified", queue.jobs[1].status)
        let history = try readHistory(root)
        precondition(history["resume file.txt"]?.attempts == 2)
        precondition(history["checked.txt"]?.status == "completed")
        let manifest = try String(contentsOf: historyURL(root), encoding: .utf8)
        precondition(!manifest.contains("token=example"))
        queue.jobs = try pastedJobs("wget -O 'resume file.txt' '\(url)'")
        await queue.start(minimumDelay: 0, maximumDelay: 0)
        precondition(queue.jobs[0].status == "Already downloaded", queue.jobs[0].status)
        let csv = root.appendingPathComponent("sample.csv")
        try "uri,file_name,sha256_checksum\r\n\(url),\"comma,\"\"quote\"\".txt\",\(hash)\r\n".write(to: csv, atomically: true, encoding: .utf8)
        let imported = try loadJobs(csv)
        precondition(imported.first?.name == "comma,\"quote\".txt")
        print("Passed pasted URLs and wget commands, unsafe-name rejection, Excel and CSV import, CLI partial migration and Range resume, user-agent rotation, SHA-256, history and smart skip.")
    }
}
SWIFT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/modules" "$test_dir/Checks.swift" -o "$test_dir/check"
"$test_dir/check" "$test_dir" "$PWD/downloads_template.xlsx"
