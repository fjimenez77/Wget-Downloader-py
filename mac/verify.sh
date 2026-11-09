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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import time
root = Path(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == '/head-blocked':
            self.send_response(403)
            self.send_header('Content-Length', '12')
        else:
            self.send_response(200)
            self.send_header('Content-Length', str(256 * 1024 if self.path.startswith('/slow/') else 5))
        self.end_headers()

    def do_GET(self):
        (root/'agent').write_text(self.headers.get('User-Agent', ''))
        offset = int(self.headers.get('Range','bytes=0-').split('=')[1].split('-')[0])
        (root/'offset').write_text(str(offset))
        if self.path.startswith('/slow/'):
            total = 256 * 1024
            self.send_response(206 if offset else 200)
            self.send_header('Content-Length', str(total - offset))
            if offset: self.send_header('Content-Range', f'bytes {offset}-{total-1}/{total}')
            self.end_headers()
            try:
                for position in range(offset, total, 16384):
                    self.wfile.write(b'x' * min(16384, total - position))
                    self.wfile.flush()
                    time.sleep(.15)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self.send_response(206 if offset else 200)
        self.send_header('Content-Length', str(5-offset))
        if offset: self.send_header('Content-Range', f'bytes {offset}-4/5')
        self.end_headers()
        self.wfile.write(b'hello'[offset:])
server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
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
    @MainActor static func waitForQueue(_ queue: Queue) async {
        let deadline = Date().addingTimeInterval(20)
        while queue.running && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        precondition(!queue.running, "Queue timed out")
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let template = URL(fileURLWithPath: CommandLine.arguments[2])
        let templateRows = try readRows(template)
        precondition(templateRows[0].contains("url"))
        let port = try String(contentsOf: root.appendingPathComponent("port"), encoding: .utf8)
        let url = "http://127.0.0.1:\(port)/file?token=example"
        let probe = Queue()
        probe.jobs = try pastedJobs("http://127.0.0.1:\(port)/metadata.bin\nhttp://127.0.0.1:\(port)/head-blocked")
        probe.lookupSizes()
        let probeDeadline = Date().addingTimeInterval(5)
        while probe.jobs[0].expectedBytes == nil && Date() < probeDeadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        precondition(probe.jobs[0].expectedBytes == 5)
        let blocked = await remoteFileSize(probe.jobs[1].url, session: .shared)
        precondition(blocked == nil)
        precondition(probe.jobs.allSatisfy { $0.status == "Ready" && $0.bytes == 0 })
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("offset").path))
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
        queue.enqueue(minimumDelay: 0, maximumDelay: 0)
        await waitForQueue(queue)
        precondition(queue.jobs[0].status == "Downloaded", queue.jobs[0].status)
        let range = try String(contentsOf: root.appendingPathComponent("offset"), encoding: .utf8)
        precondition(range == "2")
        let agent = try String(contentsOf: root.appendingPathComponent("agent"), encoding: .utf8)
        precondition(browserAgents.contains(agent))
        queue.jobs.append(second)
        queue.enqueue(minimumDelay: 0, maximumDelay: 0, rotateAgent: false)
        await waitForQueue(queue)
        precondition(queue.jobs[1].status == "Verified", queue.jobs[1].status)
        let history = try readHistory(root)
        precondition(history["resume file.txt"]?.attempts == 2)
        precondition(history["checked.txt"]?.status == "completed")
        let manifest = try String(contentsOf: historyURL(root), encoding: .utf8)
        precondition(!manifest.contains("token=example"))
        queue.jobs = try pastedJobs("wget -O 'resume file.txt' '\(url)'")
        queue.enqueue(minimumDelay: 0, maximumDelay: 0)
        await waitForQueue(queue)
        precondition(queue.jobs[0].status == "Already downloaded", queue.jobs[0].status)
        let folderCheck = Queue()
        folderCheck.folder = root
        folderCheck.jobs = try loadJobs([
            ["url", "file", "sha256"],
            [url, "checked.txt", hash],
            [url, "resume file.txt", ""],
            [url, "flat.txt", hash],
            [url, "unknown.txt", ""],
            [url, "bad.txt", hash],
            [url, "missing.txt", hash],
        ])
        try Data("hello".utf8).write(to: root.appendingPathComponent("flat.txt"))
        try Data("hello".utf8).write(to: root.appendingPathComponent("unknown.txt"))
        try Data("wrong".utf8).write(to: root.appendingPathComponent("bad.txt"))
        await folderCheck.checkExistingFiles()
        precondition(folderCheck.jobs.map(\.status) == [
            "Verified", "Already downloaded", "Verified", "On disk · checksum needed", "Checksum mismatch", "Ready"
        ], "\(folderCheck.jobs.map(\.status))")
        try FileManager.default.removeItem(at: root.appendingPathComponent("flat.txt"))
        await folderCheck.checkExistingFiles()
        precondition(folderCheck.jobs[2].status == "Ready")
        print("Passed folder checks for nested and flat files, history, missing checksums, mismatches, and removed files.")
        let csv = root.appendingPathComponent("sample.csv")
        try "uri,file_name,sha256_checksum\r\n\(url),\"comma,\"\"quote\"\".txt\",\(hash)\r\n".write(to: csv, atomically: true, encoding: .utf8)
        let imported = try loadJobs(csv)
        precondition(imported.first?.name == "comma,\"quote\".txt")
        queue.jobs = try pastedJobs((1...4).map { "http://127.0.0.1:\(port)/slow/\($0).bin" }.joined(separator: "\n"))
        let ids = queue.jobs.map(\.id)
        queue.enqueue(minimumDelay: 0, maximumDelay: 0)
        precondition(queue.active == Set(ids.prefix(2)))
        queue.enqueue(ids[3], minimumDelay: 0, maximumDelay: 0)
        precondition(queue.pending == [ids[3], ids[2]])
        let deadline = Date().addingTimeInterval(5)
        while !queue.jobs.prefix(2).allSatisfy({ $0.bytesPerSecond > 0 }) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        precondition(queue.jobs.prefix(2).allSatisfy { $0.bytesPerSecond > 0 })
        queue.pause(ids[0])
        while queue.active.contains(ids[0]) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        precondition(queue.jobs[0].status == "Paused")
        precondition(queue.jobs[0].expectedBytes == 256 * 1024)
        precondition(queue.jobs[0].bytes > 0 && queue.jobs[0].bytes < 256 * 1024)
        precondition(queue.active.contains(ids[1]) && queue.active.contains(ids[3]))
        queue.enqueue(ids[0], minimumDelay: 0, maximumDelay: 0)
        await waitForQueue(queue)
        precondition(queue.jobs.allSatisfy { $0.expectedBytes == 256 * 1024 })
        precondition(queue.jobs.allSatisfy(\.completed), "\(queue.jobs.map(\.status))")
        precondition(fileSize(destinationURL(root, "1.bin")) == 256 * 1024)
        precondition(try! readHistory(root)["1.bin"]?.attempts == 2)
        print("Passed two simultaneous transfers, live rates, queue priority, independent pause, and resume.")
        print("Passed pasted URLs and wget commands, unsafe-name rejection, Excel and CSV import, CLI partial migration and Range resume, user-agent rotation, SHA-256, history and smart skip.")
    }
}
SWIFT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/modules" "$test_dir/Checks.swift" -o "$test_dir/check"
"$test_dir/check" "$test_dir" "$PWD/downloads_template.xlsx"
