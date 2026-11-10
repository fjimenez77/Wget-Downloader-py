import AppKit
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct Job: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let hash: String
    var status = "Ready"
    var bytes: Int64 = 0
    var expectedBytes: Int64?
    var bytesPerSecond: Int64 = 0

    var completed: Bool {
        ["Downloaded", "Verified", "Already downloaded"].contains(status)
    }
}

struct Problem: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func readRows(_ file: URL) throws -> [[String]] {
    if ["xlsx", "xlsm"].contains(file.pathExtension.lowercased()) {
        func xml(_ path: String) throws -> XMLDocument {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", file.path, path]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Problem("Missing workbook data.") }
            return try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        }
        let shared = (try? xml("xl/sharedStrings.xml").nodes(forXPath: "//*[local-name()='si']").map {
            try $0.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()
        }) ?? []
        let book = try xml("xl/workbook.xml")
        let sheet = try book.nodes(forXPath: "//*[local-name()='sheet']").first as? XMLElement
        let relation = sheet?.attribute(forName: "r:id")?.stringValue
        let links = try xml("xl/_rels/workbook.xml.rels")
        let link = try links.nodes(forXPath: "//*[local-name()='Relationship']").compactMap { $0 as? XMLElement }
            .first { $0.attribute(forName: "Id")?.stringValue == relation }
        guard let target = link?.attribute(forName: "Target")?.stringValue, !target.contains("..") else {
            throw Problem("Could not find the workbook’s first sheet.")
        }
        let sheetPath = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
        return try xml(sheetPath).nodes(forXPath: "//*[local-name()='row']").map { row in
            var fields: [String] = []
            for case let cell as XMLElement in try row.nodes(forXPath: "./*[local-name()='c']") {
                let reference = cell.attribute(forName: "r")?.stringValue ?? ""
                let column = reference.utf8.prefix { (65...90).contains($0) }.reduce(0) { $0 * 26 + Int($1) - 64 }
                guard (1...16384).contains(column) else { continue }
                while fields.count < column { fields.append("") }
                let value = try cell.nodes(forXPath: "./*[local-name()='v']").first?.stringValue ?? ""
                switch cell.attribute(forName: "t")?.stringValue {
                case "s":
                    if let index = Int(value), shared.indices.contains(index) { fields[column - 1] = shared[index] }
                case "inlineStr":
                    fields[column - 1] = try cell.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()
                default: fields[column - 1] = value
                }
            }
            return fields
        }
    }
    let delimiter: Character = file.pathExtension.lowercased() == "tsv" ? "\t" : ","
    let input: String
    if file.pathExtension.lowercased() == "xls" {
        guard let reader = Bundle.main.url(forAuxiliaryExecutable: "ReadLegacyExcel") else {
            throw Problem("The legacy Excel reader is missing from the app.")
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = reader
        process.arguments = [file.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let csv = String(data: data, encoding: .utf8) else {
            throw Problem("Could not read the legacy Excel workbook.")
        }
        input = csv
    } else {
        input = try String(contentsOf: file, encoding: .utf8)
    }
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var index = input.startIndex
    while index < input.endIndex {
        let character = input[index]
        input.formIndex(after: &index)
        if character == "\"" {
            if quoted && index < input.endIndex && input[index] == "\"" {
                field.append(character)
                input.formIndex(after: &index)
            } else if quoted || field.isEmpty {
                quoted.toggle()
            } else {
                field.append(character)
            }
        } else if !quoted && character == delimiter {
            row.append(field)
            field = ""
        } else if !quoted && character.isNewline {
            rows.append(row + [field])
            row = []
            field = ""
        } else { field.append(character) }
    }
    guard !quoted else { throw Problem("The spreadsheet has an unclosed quoted field.") }
    return rows + [row + [field]]
}

func loadJobs(_ file: URL) throws -> [Job] {
    try loadJobs(readRows(file))
}

func loadJobs(_ input: [[String]]) throws -> [Job] {
    let rows = input.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    let headers = (rows.first ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).lowercased() }
    guard let urlIndex = headers.firstIndex(where: { ["url", "link", "download_url", "download url", "download link", "uri"].contains($0) }) else {
        throw Problem("Add a column named url to the first row.")
    }
    let nameIndex = headers.firstIndex(where: { ["file", "filename", "file_name", "name", "output"].contains($0) })
    let hashIndex = headers.firstIndex(where: { ["sha256", "sha256 checksum", "sha256_checksum", "checksum", "sha", "hash", "sha256sum"].contains($0) })
    var names = Set<String>()
    return try rows.dropFirst().enumerated().compactMap { index, row in
        func field(_ column: Int?) -> String {
            guard let column, row.indices.contains(column) else { return "" }
            return row[column].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let address = field(urlIndex)
        if ["", "nan", "none", "url"].contains(address.lowercased()) { return nil }
        guard !address.contains(where: \.isWhitespace), let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else {
            throw Problem("Entry \(index + 1) needs a valid HTTP or HTTPS URL.")
        }
        let supplied = field(nameIndex)
        let name = supplied.isEmpty ? url.lastPathComponent : supplied
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
              names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
            throw Problem("Entry \(index + 1) needs a unique, plain filename.")
        }
        let hash = field(hashIndex).lowercased()
        guard hash.isEmpty || (hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }) else {
            throw Problem("Entry \(index + 1) has an invalid SHA-256 checksum.")
        }
        return Job(url: url, name: name, hash: hash)
    }
}

let browserAgents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
]

func pastedJobs(_ text: String) throws -> [Job] {
    var rows = [["url", "file", "sha256"]]
    let markdown = try NSRegularExpression(pattern: #"\[https?://[^\]\r\n]+\]\((https?://[^)\r\n]+)\)"#)
    let checksumPattern = try NSRegularExpression(pattern: #"(?i)^(?:(?:sha-?256(?: checksum)?|checksum)\s*:\s*)?([a-f0-9]{64})(?:\s+|$)"#)
    var pendingHash = ""
    var previous: Int?
    var labeled = false
    for line in text.split(whereSeparator: \.isNewline) {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { continue }
        let heading = value.trimmingCharacters(in: CharacterSet(charactersIn: "*: ")).lowercased()
        if ["download url", "sha-256 checksum", "sha256 checksum", "wget command", "checksum + wget"].contains(heading) {
            labeled = true
            continue
        }
        if let match = checksumPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let hashRange = Range(match.range(at: 1), in: value), let fullRange = Range(match.range, in: value) {
            let hash = String(value[hashRange])
            value = String(value[fullRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty, let previous {
                while rows[previous].count < 3 { rows[previous].append("") }
                rows[previous][2] = hash
            } else {
                pendingHash = hash
            }
            if value.isEmpty { continue }
        }
        value = markdown.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "$1")
            .replacingOccurrences(of: #"\&"#, with: "&")
        func add(_ fields: [String]) {
            var row = fields
            while row.count < 3 { row.append("") }
            if row[2].isEmpty { row[2] = pendingHash }
            pendingHash = ""
            if labeled, let previous, rows[previous][0] == row[0] {
                for index in 1...2 where !row[index].isEmpty { rows[previous][index] = row[index] }
            } else {
                rows.append(row)
                previous = rows.count - 1
            }
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            let fields = value.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count <= 3 else { throw Problem("Use URL, filename and SHA-256 separated by tabs.") }
            add(fields)
            continue
        }
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        for character in value {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { token.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty { tokens.append(token) }
        guard quote == nil, tokens.first == "wget" else {
            throw Problem("Use one HTTP(S) URL or wget command per line.")
        }
        switch tokens.dropFirst().filter({ !["-c", "--continue"].contains($0) }) {
        case let arguments where arguments.count == 1:
            add([arguments[0]])
        case let arguments where arguments.count == 3 && ["-O", "--output-document"].contains(arguments[0]):
            add([arguments[2], arguments[1]])
        default:
            throw Problem("Supported commands are wget URL and wget -O filename URL.")
        }
    }
    return try loadJobs(rows)
}

struct Record: Codable {
    var url: String?
    var status: String
    var source_id: String?
    var size_bytes: Int64?
    var attempts: Int?
    var error: String?
    var completed_at: String?
}

func sourceID(_ url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
}

func fileSize(_ url: URL) -> Int64? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
}

func responseSize(_ headers: URL) -> Int64? {
    guard let text = try? String(contentsOf: headers, encoding: .isoLatin1),
          let response = text.components(separatedBy: "\r\n\r\n").last(where: { $0.hasPrefix("HTTP/") }),
          let code = response.split(separator: " ").dropFirst().first,
          code == "200" || code == "206" else { return nil }
    for line in response.components(separatedBy: "\r\n") {
        let fields = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard fields.count == 2 else { continue }
        let value = fields[1].trimmingCharacters(in: .whitespaces)
        if code == "206", fields[0].lowercased() == "content-range" {
            return value.split(separator: "/").last.flatMap { Int64($0) }
        }
        if code == "200", fields[0].lowercased() == "content-length" {
            return Int64(value)
        }
    }
    return nil
}

func legacyHistoryURL(_ folder: URL) -> URL {
    folder.appendingPathComponent("download_manifest.json")
}

struct HistoryStore {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory
        .appendingPathComponent("Wget Downloader", isDirectory: true)
        .appendingPathComponent("Manifests", isDirectory: true)) {
        self.directory = directory
    }

    func manifestURL(for folder: URL) -> URL {
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    func read(_ folder: URL) throws -> [String: Record] {
        if let current = try readManifest(manifestURL(for: folder)) { return current }
        guard let legacy = try readManifest(legacyHistoryURL(folder)) else { return [:] }
        try write(legacy, for: folder)
        return legacy
    }

    func write(_ records: [String: Record], for folder: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(records).write(to: manifestURL(for: folder), options: .atomic)
    }

    private func readManifest(_ url: URL) throws -> [String: Record]? {
        do {
            return try JSONDecoder().decode([String: Record].self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }
}

func destinationURL(_ folder: URL, _ name: String) -> URL {
    folder.appendingPathComponent((name as NSString).deletingPathExtension, isDirectory: true)
        .appendingPathComponent(name)
}

func checksum(_ file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

private func existingStatus(_ job: Job, in folder: URL, record: Record?) throws -> (status: String, size: Int64?)? {
    let nested = destinationURL(folder, job.name)
    let flat = folder.appendingPathComponent(job.name)
    let directory = nested.deletingLastPathComponent()
    let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    let candidates = directoryValues?.isDirectory == true && directoryValues?.isSymbolicLink == false
        ? [nested, flat] : [flat]
    var found = false
    for file in candidates where file != legacyHistoryURL(folder) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let before = try? file.resourceValues(forKeys: keys),
              before.isRegularFile == true, before.isSymbolicLink == false else { continue }
        found = true
        if !job.hash.isEmpty {
            let matches = try checksum(file) == job.hash
            let after = try URL(fileURLWithPath: file.path).resourceValues(forKeys: keys)
            guard after.isRegularFile == true, after.isSymbolicLink == false,
                  before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else {
                return ("File changed during check", nil)
            }
            if matches { return ("Verified", before.fileSize.map(Int64.init)) }
        } else if file == nested, record?.status == "completed", let size = before.fileSize,
                  record?.size_bytes == Int64(size),
                  record?.source_id == sourceID(job.url) || record?.url == job.url.absoluteString {
            return ("Already downloaded", Int64(size))
        }
    }
    guard found else { return nil }
    return (job.hash.isEmpty ? "On disk · checksum needed" : "Checksum mismatch", nil)
}

/// Reads the persisted Settings toggle directly, because a size lookup can run
/// before the queue has been handed the value through `enqueue`.
var agentRotationEnabled: Bool {
    UserDefaults.standard.object(forKey: "rotateAgent") as? Bool ?? true
}

func remoteFileSize(_ url: URL, session: URLSession, agent: String? = nil) async -> Int64? {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
    request.httpMethod = "HEAD"
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    if let agent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
    guard let (_, response) = try? await session.data(for: request),
          let http = response as? HTTPURLResponse, http.statusCode == 200,
          let length = http.value(forHTTPHeaderField: "Content-Length"),
          let size = Int64(length), size >= 0 else { return nil }
    return size
}

@MainActor
final class Queue: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var spreadsheet: URL?
    @Published var folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    @Published var message = "Paste links or choose a spreadsheet."
    @Published private(set) var checkingFiles = false
    @Published var history: [String: Record] = [:]
    @Published private(set) var active = Set<UUID>()
    @Published private(set) var pending: [UUID] = []
    private let historyStore: HistoryStore
    private var sizeLookup: Task<Void, Never>?
    private var processes: [UUID: Process] = [:]
    private var pausing = Set<UUID>()
    private var cooldowns = Set<UUID>()
    private var limit = 2
    private var delayRange = 4.0...15.0
    private var rotateAgent = true

    init(historyStore: HistoryStore = HistoryStore()) {
        self.historyStore = historyStore
    }

    var running: Bool { !active.isEmpty || !pending.isEmpty }
    var queueLocked: Bool { running || checkingFiles }

    func choose(folderOnly: Bool) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folderOnly
        panel.canChooseDirectories = folderOnly
        if !folderOnly { panel.allowedContentTypes = ["csv", "tsv", "xlsx", "xlsm", "xls"].compactMap { UTType(filenameExtension: $0) } }
        guard panel.runModal() == .OK, let file = panel.url else { return }
        if folderOnly {
            if folder != file {
                folder = file
                for index in jobs.indices {
                    jobs[index].status = "Ready"
                    jobs[index].bytes = 0
                    jobs[index].bytesPerSecond = 0
                }
                message = "\(jobs.count) files ready."
            }
            return
        }
        do {
            let loaded = try loadJobs(file)
            spreadsheet = file
            jobs = loaded
            message = loaded.isEmpty ? "No download URLs found." : "\(loaded.count) files ready."
            if !loaded.isEmpty { await checkExistingFiles() }
            lookupSizes()
        } catch { message = error.localizedDescription }
    }

    func addLinks(_ text: String) throws {
        let added = try pastedJobs(text)
        guard !added.isEmpty else { throw Problem("Paste at least one download URL.") }
        let existing = Set(jobs.map { $0.name.precomposedStringWithCanonicalMapping.lowercased() })
        guard added.allSatisfy({ !existing.contains($0.name.precomposedStringWithCanonicalMapping.lowercased()) }) else {
            throw Problem("A filename is already in the queue. Supply a different filename or clear the queue.")
        }
        jobs += added
        message = "\(jobs.count) files in the queue."
        lookupSizes()
    }

    func lookupSizes() {
        sizeLookup?.cancel()
        let candidates = jobs.filter { $0.expectedBytes == nil && !$0.completed }
        let rotate = agentRotationEnabled
        sizeLookup = Task { [weak self] in
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.timeoutIntervalForResource = 10
            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }
            for job in candidates {
                guard !Task.isCancelled, let queue = self else { return }
                guard queue.jobs.contains(where: { $0.id == job.id && $0.expectedBytes == nil }),
                      !queue.active.contains(job.id) else { continue }
                let agent = rotate ? browserAgents.randomElement() : nil
                let size = await remoteFileSize(job.url, session: session, agent: agent)
                guard !Task.isCancelled else { return }
                if let size, let index = queue.jobs.firstIndex(where: { $0.id == job.id }),
                   queue.jobs[index].expectedBytes == nil, !queue.active.contains(job.id) {
                    queue.jobs[index].expectedBytes = size
                }
            }
        }
    }

    func clear() {
        sizeLookup?.cancel()
        jobs = []
        spreadsheet = nil
        message = "Paste links or choose a spreadsheet."
    }

    func refreshHistory() {
        do { history = try historyStore.read(folder) }
        catch { message = "Could not read download history: \(error.localizedDescription)" }
    }

    func checkExistingFiles() async {
        guard !queueLocked, !jobs.isEmpty else { return }
        checkingFiles = true
        defer { checkingFiles = false }
        let selectedFolder = folder
        let records = (try? historyStore.read(selectedFolder)) ?? [:]
        for index in jobs.indices {
            let job = jobs[index]
            message = "Checking file \(index + 1) of \(jobs.count)…"
            do {
                let status = try await Task.detached {
                    try existingStatus(job, in: selectedFolder, record: records[job.name])
                }.value
                if let status {
                    jobs[index].status = status.status
                    if let size = status.size { jobs[index].expectedBytes = size }
                }
                else if job.completed || job.status == "On disk · checksum needed" || job.status == "Checksum mismatch" {
                    jobs[index].status = "Ready"
                }
            } catch {
                jobs[index].status = "Could not check file"
            }
        }
        let complete = jobs.filter(\.completed).count
        let review = jobs.filter { ["On disk · checksum needed", "Checksum mismatch",
                                    "File changed during check", "Could not check file"].contains($0.status) }.count
        message = "Folder check · \(complete) complete · \(review) need review."
    }

    func pause(_ id: UUID) {
        if let index = pending.firstIndex(of: id) {
            pending.remove(at: index)
            if let jobIndex = jobs.firstIndex(where: { $0.id == id }) { jobs[jobIndex].status = "Paused" }
            if pending.isEmpty { cooldowns.removeAll() }
            updateMessage()
        } else if canPause(id) {
            pausing.insert(id)
            if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].status = "Pausing" }
            if let process = processes[id], process.isRunning { process.terminate() }
        }
    }

    func canPause(_ id: UUID) -> Bool {
        guard active.contains(id), !pausing.contains(id),
              let job = jobs.first(where: { $0.id == id }) else { return false }
        return job.status == "Starting" || job.status == "Downloading"
    }

    func stop() {
        cooldowns.removeAll()
        for id in pending { pause(id) }
        for id in active { pause(id) }
    }

    func enqueue(_ id: UUID? = nil, limit: Int = 2, minimumDelay: Double = 4,
                 maximumDelay: Double = 15, rotateAgent: Bool = true) {
        guard !checkingFiles else { return }
        self.limit = min(8, max(1, limit))
        delayRange = min(minimumDelay, maximumDelay)...max(minimumDelay, maximumDelay)
        self.rotateAgent = rotateAgent
        for index in jobs.indices {
            let job = jobs[index]
            guard (id == nil || id == job.id), !job.completed, !active.contains(job.id) else { continue }
            if id != nil {
                pending.removeAll { $0 == job.id }
                pending.insert(job.id, at: 0)
            } else if !pending.contains(job.id) {
                pending.append(job.id)
            }
            jobs[index].status = "Queued"
        }
        if id != nil, active.count < self.limit, active.count + cooldowns.count >= self.limit,
           let cooldown = cooldowns.first {
            cooldowns.remove(cooldown)
        }
        fillSlots()
    }

    private func fillSlots() {
        while active.count + cooldowns.count < limit, let id = pending.first {
            pending.removeFirst()
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { continue }
            active.insert(id)
            jobs[index].status = "Starting"
            let useAgent = rotateAgent
            Task {
                await transfer(index, rotateAgent: useAgent)
                let wasPaused = pausing.remove(id) != nil
                active.remove(id)
                if !wasPaused && !pending.isEmpty {
                    let delay = Double.random(in: delayRange)
                    if delay > 0 {
                        let token = UUID()
                        cooldowns.insert(token)
                        Task {
                            try? await Task.sleep(for: .seconds(delay))
                            if cooldowns.remove(token) != nil { fillSlots() }
                        }
                    }
                }
                fillSlots()
            }
        }
        updateMessage()
    }

    private func updateMessage() {
        if running {
            message = "\(active.count) active · \(pending.count) queued"
        } else {
            let completed = jobs.filter(\.completed).count
            let paused = jobs.filter { $0.status == "Paused" }.count
            message = "\(completed) of \(jobs.count) files completed."
            if paused > 0 { message += " \(paused) paused." }
        }
    }

    private func transfer(_ index: Int, rotateAgent: Bool) async {
        let job = jobs[index]
        let id = job.id
        let manager = FileManager.default
        defer {
            processes[id] = nil
            jobs[index].bytesPerSecond = 0
        }
        func save(_ job: Job, _ status: String, _ size: Int64, _ error: String? = nil) throws {
            var updated = try historyStore.read(folder)
            updated[job.name] = Record(url: nil, status: status, source_id: sourceID(job.url), size_bytes: size,
                                       attempts: (updated[job.name]?.attempts ?? 0) + 1, error: error,
                                       completed_at: status == "completed" ? ISO8601DateFormatter().string(from: Date()) : nil)
            try historyStore.write(updated, for: folder)
            history = updated
        }
        jobs[index].bytes = 0
        guard !pausing.contains(id) else {
            jobs[index].status = "Paused"
            return
        }
        let destination = destinationURL(folder, job.name)
        let legacy: Record?
        do { legacy = try historyStore.read(folder)[job.name] }
        catch {
            jobs[index].status = "Could not read download history"
            return
        }
        let sameSource = legacy?.source_id == sourceID(job.url) || legacy?.url == job.url.absoluteString
        let oldFlat = folder.appendingPathComponent(job.name)
        let key = SHA256.hash(data: Data((job.name + "\n" + job.hash + "\n" + (job.hash.isEmpty ? job.url.absoluteString : "")).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let partial = folder.appendingPathComponent(".wget-\(key).part")
        do {
            let directory = destination.deletingLastPathComponent()
            guard (try? manager.destinationOfSymbolicLink(atPath: directory.path)) == nil,
                  (try? manager.destinationOfSymbolicLink(atPath: destination.path)) == nil,
                  (try? manager.destinationOfSymbolicLink(atPath: partial.path)) == nil else {
                throw Problem("Invalid symbolic link in output folder")
            }
            if let size = fileSize(destination) {
                if !job.hash.isEmpty {
                    let actual = try await Task.detached { try checksum(destination) }.value
                    if actual == job.hash {
                        if legacy?.status != "completed" { try save(job, "completed", size) }
                        jobs[index].expectedBytes = size
                        jobs[index].status = "Verified"
                        return
                    }
                } else if legacy?.status == "completed", legacy?.size_bytes == size,
                          sameSource {
                    jobs[index].expectedBytes = size
                    jobs[index].status = "Already downloaded"
                    return
                }
                if legacy?.status == "failed", sameSource,
                   !manager.fileExists(atPath: partial.path) {
                    try manager.moveItem(at: destination, to: partial)
                } else {
                    throw Problem("File already exists · choose a different folder or filename")
                }
            } else if !job.hash.isEmpty, fileSize(oldFlat) != nil, oldFlat != legacyHistoryURL(folder),
                      (try? manager.destinationOfSymbolicLink(atPath: oldFlat.path)) == nil,
                      try await Task.detached(operation: { try checksum(oldFlat) }).value == job.hash {
                jobs[index].expectedBytes = fileSize(oldFlat)
                jobs[index].status = "Verified"
                return
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            if pausing.contains(id) {
                jobs[index].status = "Paused"
                return
            }
            jobs[index].status = "Downloading"
            let headers = manager.temporaryDirectory.appendingPathComponent("wget-headers-\(UUID().uuidString)")
            defer { try? manager.removeItem(at: headers) }
            let transfer = Process()
            transfer.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            var arguments = ["-q", "--silent", "--globoff", "--fail", "--location", "--proto", "=http,https",
                                  "--proto-redir", "=http,https", "--retry", "3", "--connect-timeout", "60", "--speed-limit", "1", "--speed-time", "60",
                                  "--continue-at", "-", "--dump-header", headers.path, "--output", partial.path]
            if rotateAgent, let agent = browserAgents.randomElement() { arguments += ["--user-agent", agent] }
            transfer.arguments = arguments + ["--", job.url.absoluteString]
            transfer.standardOutput = FileHandle.nullDevice
            transfer.standardError = FileHandle.nullDevice
            try transfer.run()
            processes[id] = transfer
            var lastSize = fileSize(partial) ?? 0
            var lastSample = ProcessInfo.processInfo.systemUptime
            var receivedTotal = false
            while transfer.isRunning {
                let bytes = fileSize(partial) ?? 0
                jobs[index].bytes = bytes
                if !receivedTotal, let size = responseSize(headers) {
                    jobs[index].expectedBytes = size
                    receivedTotal = true
                }
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = now - lastSample
                if elapsed >= 1 {
                    jobs[index].bytesPerSecond = Int64(Double(max(0, bytes - lastSize)) / elapsed)
                    lastSize = bytes
                    lastSample = now
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            processes[id] = nil
            jobs[index].bytesPerSecond = 0
            jobs[index].bytes = fileSize(partial) ?? 0
            if let size = responseSize(headers) { jobs[index].expectedBytes = size }
            if pausing.contains(id), transfer.terminationStatus != 0 {
                try save(job, "paused", fileSize(partial) ?? 0)
                jobs[index].status = "Paused"
                return
            }
            guard transfer.terminationStatus == 0 else {
                if transfer.terminationStatus == 33 {
                    try manager.removeItem(at: partial)
                    let detail = "Resume unavailable · retry to restart"
                    try save(job, "failed", 0, detail)
                    throw Problem(detail)
                }
                let detail = "Download failed (\(transfer.terminationStatus))"
                try save(job, "failed", fileSize(partial) ?? 0, detail)
                throw Problem(detail)
            }
            if !job.hash.isEmpty {
                jobs[index].status = "Verifying"
                let actual = try await Task.detached { try checksum(partial) }.value
                guard actual == job.hash else {
                    let size = fileSize(partial) ?? 0
                    try manager.removeItem(at: partial)
                    try save(job, "sha256_mismatch", size, "Checksum mismatch")
                    throw Problem("Checksum mismatch")
                }
            }
            try manager.moveItem(at: partial, to: destination)
            let size = fileSize(destination) ?? 0
            try save(job, "completed", size)
            jobs[index].expectedBytes = size
            jobs[index].status = job.hash.isEmpty ? "Downloaded" : "Verified"
        } catch { jobs[index].status = error.localizedDescription }
    }
}

struct NetworkInfo: Decodable {
    var status: String?
    var country: String?
    var regionName: String?
    var city: String?
    var isp: String?
    var org: String?
    var hosting: Bool?
    var proxy: Bool?
    var asn: String?

    enum CodingKeys: String, CodingKey {
        case status, country, regionName, city, isp, org, hosting, proxy
        case asn = "as"
    }
}

func publicNetwork() async throws -> String {
    func request(_ address: String) async throws -> Data {
        let url = URL(string: address)!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Problem("Service unavailable.") }
        return data
    }
    var publicIP: String?
    for endpoint in ["https://api.ipify.org", "https://ip.me/", "https://ifconfig.me/ip"] {
        guard let data = try? await request(endpoint),
              let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ip.isEmpty, ip.utf8.allSatisfy({ "0123456789abcdefABCDEF:.".utf8.contains($0) }) else { continue }
        publicIP = ip
        break
    }
    guard let ip = publicIP else { throw Problem("Could not retrieve your public IP.") }
    let address = "http://ip-api.com/json/\(ip)?fields=status,country,regionName,city,isp,org,as,proxy,hosting"
    guard let data = try? await request(address), let info = try? JSONDecoder().decode(NetworkInfo.self, from: data),
          info.status == "success" else { return "Public IP: \(ip)\nLocation and VPN indicators unavailable." }
    let location = [info.city, info.regionName, info.country].compactMap { $0 }.joined(separator: ", ")
    let signal = info.hosting == true || info.proxy == true
        ? "The provider flagged this address as hosting or proxy traffic."
        : "The provider returned no hosting or proxy flag."
    return "Public IP: \(ip)\nLocation: \(location)\nISP: \(info.isp ?? "Unknown")\nOrganization: \(info.org ?? "Unknown")\nASN: \(info.asn ?? "Unknown")\n\n\(signal) VPN detection is approximate."
}

struct HistoryRow: Identifiable {
    let name: String
    let record: Record
    let exists: Bool
    var id: String { name }
    var status: String { record.status.replacingOccurrences(of: "_", with: " ").capitalized }
    var size: String { ByteCountFormatter.string(fromByteCount: record.size_bytes ?? 0, countStyle: .file) }
    var attempts: String { String(record.attempts ?? 0) }
    var onDisk: String { exists ? "Yes" : "—" }
    var detail: String { record.error ?? record.completed_at ?? "" }
}

@main
struct Downloader: App {
    enum Panel: String, Identifiable {
        case paste, history, settings, network, guide, template
        var id: String { rawValue }
    }

    @StateObject private var queue = Queue()
    @State private var panel: Panel?
    @State private var pasted = ""
    @State private var pasteError = ""
    @State private var network = ""
    @State private var checkingNetwork = false
    @State private var templateRows = 50
    @AppStorage("parallelDownloads") private var parallelDownloads = 2
    @AppStorage("minimumDelay") private var minimumDelay = 4.0
    @AppStorage("maximumDelay") private var maximumDelay = 15.0
    @AppStorage("rotateAgent") private var rotateAgent = true

    var body: some Scene {
        Window("Wget Downloader", id: "main") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wget Downloader").font(.largeTitle.weight(.semibold))
                        Text("Batch downloads with resume and optional SHA-256 verification.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { panel = .guide } label: {
                        Label("How to Use", systemImage: "info.circle")
                    }.fixedSize()
                }
                HStack(alignment: .top) {
                    Button("Paste Links") { panel = .paste }.fixedSize()
                    Button("Choose Spreadsheet") {
                        Task { await queue.choose(folderOnly: false) }
                    }.fixedSize()
                    Text(queue.spreadsheet?.lastPathComponent ?? "CSV, TSV or Excel")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Clear Queue") {
                        queue.clear()
                    }.fixedSize().disabled(queue.jobs.isEmpty)
                }.disabled(queue.queueLocked)
                HStack(alignment: .top) {
                    Button("Choose Download Folder") {
                        Task { await queue.choose(folderOnly: true) }
                    }.fixedSize()
                    Text(queue.folder.path(percentEncoded: false))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: queue.folder.path) }
                        .fixedSize()
                }.disabled(queue.queueLocked)
                VStack(spacing: 0) {
                    queueRow("File", "Size", "Status") {
                        Text("Action").font(.subheadline.weight(.semibold))
                    }.font(.subheadline.weight(.semibold))
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(queue.jobs.enumerated()), id: \.element.id) { index, job in
                                VStack(alignment: .leading, spacing: 0) {
                                    queueRow(job.name, sizeLabel(job), completionLabel(job), completed: job.completed) {
                                        rowActions(job).disabled(queue.checkingFiles)
                                    }
                                    if job.status == "Downloading" {
                                        transferProgress(job)
                                            .padding(.horizontal, 12)
                                            .padding(.bottom, 8)
                                    }
                                }
                                .contextMenu {
                                    if queue.pending.contains(job.id) {
                                        Button("Start Next") { startDownloads(job.id) }
                                        Button("Pause") { queue.pause(job.id) }
                                    } else {
                                        rowActions(job)
                                    }
                                }
                                .background(job.completed ? Color.green.opacity(0.12)
                                    : index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.05))
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 120)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                HStack {
                    Button(queue.checkingFiles ? "Checking Files…" : "Check Existing Files") {
                        Task { await queue.checkExistingFiles() }
                    }.disabled(queue.queueLocked || queue.jobs.isEmpty)
                    Button("Settings") { panel = .settings }
                    Button("History") {
                        if !queue.running { queue.refreshHistory() }
                        panel = .history
                    }
                    Menu("Tools") {
                        Button("Check Public IP…") { panel = .network }
                        Button("Save CSV Template…") { panel = .template }
                    }.fixedSize()
                    Spacer()
                }
                HStack {
                    Text(queue.message).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if queue.running {
                        Button("Pause All") { queue.stop() }
                    }
                    Button("Start Downloads") { startDownloads() }
                        .buttonStyle(.borderedProminent)
                        .disabled(queue.checkingFiles || !queue.jobs.contains { !$0.completed && !queue.active.contains($0.id) && !queue.pending.contains($0.id) })
                }
                Divider()
                HStack {
                    Text("Copyright © 2026 Felix J. (@fjimenez77) and contributors")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Link(destination: URL(string: "https://github.com/fjimenez77/Wget-Downloader-py")!) {
                        Label("Open GitHub Repository", systemImage: "arrow.up.right.square")
                    }.fixedSize()
                }.font(.footnote)
            }
            .padding(24)
            .frame(minWidth: 720, minHeight: 520)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in queue.stop() }
            .sheet(item: $panel) { item in panelView(item) }
        }
        .defaultSize(width: 860, height: 600)
    }

    private func queueRow<Actions: View>(_ name: String, _ size: String, _ status: String, completed: Bool = false, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(size)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 100, alignment: .leading)
            HStack(alignment: .top, spacing: 5) {
                if completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                Text(status).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 180, alignment: .leading)
            ZStack(alignment: .leading) {
                Color.clear
                actions()
            }
            .frame(width: 154, height: 24, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func sizeLabel(_ job: Job) -> String {
        if job.status == "Paused", job.bytes > 0 {
            return "\(formattedBytes(job.bytes)) of \(job.expectedBytes.map(formattedBytes) ?? "unknown")"
        }
        return job.expectedBytes.map(formattedBytes) ?? "Unknown"
    }

    private func completionLabel(_ job: Job) -> String {
        switch job.status {
        case "Verified": return "Download complete · SHA-256 verified"
        case "Downloaded": return "Download complete"
        case "Already downloaded": return "Already complete"
        default: return job.status
        }
    }

    @ViewBuilder
    private func rowActions(_ job: Job) -> some View {
        if queue.pending.contains(job.id) {
            HStack {
                Button("Start Next") { startDownloads(job.id) }
                Button("Pause") { queue.pause(job.id) }
            }
        } else if queue.canPause(job.id) {
            Button("Pause") { queue.pause(job.id) }
        } else if !job.completed && !queue.active.contains(job.id) {
            Button(job.status == "Paused" ? "Resume" : job.status == "Ready" ? "Start" : "Retry") {
                startDownloads(job.id)
            }
        }
    }

    private func transferProgress(_ job: Job) -> some View {
        HStack {
            if let total = job.expectedBytes, total > 0 {
                ProgressView(value: Double(min(job.bytes, total)), total: Double(total))
                    .accessibilityLabel("Progress for \(job.name)")
                Text("\(formattedBytes(job.bytes)) / \(formattedBytes(total))")
            } else {
                ProgressView().controlSize(.small)
                Text(formattedBytes(job.bytes))
            }
            Text("\(formattedBytes(job.bytesPerSecond))/s")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }.font(.caption)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func startDownloads(_ id: UUID? = nil) {
        queue.enqueue(id, limit: parallelDownloads, minimumDelay: validDelay(minimumDelay),
                      maximumDelay: validDelay(maximumDelay), rotateAgent: rotateAgent)
    }

    private func validDelay(_ value: Double) -> Double {
        value.isFinite ? min(86_400, max(0, value)) : 0
    }

    private func saveTemplate() {
        let dialog = NSSavePanel()
        dialog.nameFieldStringValue = "download_template.csv"
        dialog.allowedContentTypes = [.commaSeparatedText]
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        let rows = templateRows > 0 ? (1...templateRows).map { "\($0),,,," } : []
        do {
            try (["#,url,file,sha256,notes"] + rows).joined(separator: "\n")
                .appending("\n").write(to: url, atomically: true, encoding: .utf8)
            queue.message = "Saved \(url.lastPathComponent)."
            panel = nil
        } catch { pasteError = error.localizedDescription }
    }

    private func title(_ text: String) -> some View { Text(text).font(.title2.bold()) }

    @ViewBuilder
    private func panelView(_ item: Panel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch item {
            case .paste:
                title("Paste download links")
                Text("Paste a URL, a wget command, or a vendor download block with its SHA-256 checksum. You can also use tab-separated URL, filename and checksum columns.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $pasted).font(.system(.body, design: .monospaced))
                    .frame(height: 170).border(.quaternary)
                    .accessibilityLabel("Download links")
                if !pasteError.isEmpty { Text(pasteError).foregroundStyle(.red) }
            case .settings:
                title("Download settings")
                Form {
                    Stepper("Simultaneous downloads: \(parallelDownloads)", value: $parallelDownloads, in: 1...8)
                    TextField("Minimum delay (seconds)", value: $minimumDelay, format: .number)
                    TextField("Maximum delay (seconds)", value: $maximumDelay, format: .number)
                    Toggle("Rotate browser user agents", isOn: $rotateAgent)
                }
                Text("The queue waits a random amount of time before refilling a slot. Set both delays to zero for immediate refill. Start Next prioritizes a file. Settings apply when you next start downloads.")
                    .foregroundStyle(.secondary)
                Button("Restore Defaults") { parallelDownloads = 2; minimumDelay = 4; maximumDelay = 15; rotateAgent = true }
            case .history:
                title("Download history")
                Text(queue.folder.path).foregroundStyle(.secondary)
                let rows = queue.history.keys.sorted().compactMap { name in
                    queue.history[name].map { record in
                        HistoryRow(name: name, record: record, exists: FileManager.default.fileExists(atPath: destinationURL(queue.folder, name).path))
                    }
                }
                Table(rows) {
                    TableColumn("File", value: \.name)
                    TableColumn("Status", value: \.status)
                    TableColumn("Size", value: \.size).width(72)
                    TableColumn("Attempts", value: \.attempts).width(56)
                    TableColumn("On disk", value: \.onDisk).width(50)
                    TableColumn("Details", value: \.detail)
                }.frame(width: 710, height: 240)
                Text("\(rows.count) records · \(rows.filter { $0.record.status == "completed" }.count) completed")
                    .foregroundStyle(.secondary)
            case .network:
                title("Public IP & network")
                Text("This sends a request to a public IP service and looks up the address with ip-api.com.")
                    .foregroundStyle(.secondary)
                if !network.isEmpty { Text(network).textSelection(.enabled) }
                Button(checkingNetwork ? "Checking…" : "Check Public IP") {
                    checkingNetwork = true
                    Task {
                        defer { checkingNetwork = false }
                        do { network = try await publicNetwork() }
                        catch { network = error.localizedDescription }
                    }
                }.disabled(checkingNetwork)
            case .guide:
                title("How to Use Wget Downloader")
                Text("1. Add downloads").font(.headline)
                Text("Paste HTTP or HTTPS links, including presigned S3 URLs, or paste a Markdown link, a wget -O command, or a vendor download block with its SHA-256 checksum.")
                Text("You can also import CSV, TSV, XLSX, XLSM, or XLS. Include a url column, with optional file and sha256 columns.")
                Text("2. Choose a folder and start").font(.headline)
                Text("Choose a download folder before importing a spreadsheet. Import checks that folder automatically and highlights confirmed files. Use Check Existing Files to scan again after changing folders or pasting links. The Size column shows totals when available and keeps them visible after pausing. Select Start Downloads for the remaining items.")
                Text("3. Pause, resume, or check history").font(.headline)
                Text("Use the row buttons to start, pause, resume, or prioritize a file. Active rows show download speed and progress. Settings controls how many files download at once. History shows completed and failed downloads.")
                Text("Network and settings").font(.headline)
                Text("Use Tools → Check Public IP to inspect your connection. If you use a VPN, connect before starting. Settings controls randomized delays and browser user-agent rotation.")
                HStack {
                    Link("Mullvad", destination: URL(string: "https://mullvad.net")!)
                    Link("Proton VPN", destination: URL(string: "https://protonvpn.com")!)
                    Link("IVPN", destination: URL(string: "https://www.ivpn.net")!)
                }
            case .template:
                title("Save a CSV template")
                Stepper("Blank rows: \(templateRows)", value: $templateRows, in: 0...1000)
                Text("The template includes url, file, sha256 and notes columns.").foregroundStyle(.secondary)
                if !pasteError.isEmpty { Text(pasteError).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button(item == .paste || item == .template ? "Cancel" : "Done") { panel = nil }
                    .keyboardShortcut(.cancelAction)
                if item == .paste {
                    Button("Add to Queue") {
                        do {
                            try queue.addLinks(pasted)
                            pasted = ""
                            panel = nil
                        } catch { pasteError = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
                if item == .template {
                    Button("Save…") { saveTemplate() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: item == .history ? 758 : 540)
        .onAppear { pasteError = "" }
    }
}
