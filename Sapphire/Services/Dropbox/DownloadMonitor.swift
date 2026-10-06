//
//  DownloadMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine
import Darwin
import SQLite3

struct DownloadTask: Identifiable, Equatable {
    var id: URL { fileURL }
    let fileURL: URL
    var fileName: String
    var progress: Double = 0.0
    var isComplete: Bool = false
    var totalBytes: Int64 = 0
    var currentBytes: Int64 = 0
    var startTime: Date = Date()
    var estimatedTimeRemaining: TimeInterval?
    var downloadSpeed: Double?
    var source: DownloadSource = .browser
    var status: String = "Downloading..."
    /// Finished files stay in Downloads, so the notch keeps them only until this time.
    var autoDismissAt: Date? = nil
}

enum DownloadSource {
    case browser
    case rsync
    case generic
}

enum DownloadType {
    case safari
    case chrome
    case firefox
    case generic

    var partialExtension: String? {
        switch self {
        case .safari: return "download"
        case .chrome: return "crdownload"
        case .firefox: return "part"
        case .generic: return nil
        }
    }
}

class DownloadProgressExtractor {

    struct ProgressInfo {
        var currentBytes: Int64
        var totalBytes: Int64?
        var progress: Double?
        var displayFileName: String?
        var isFinished: Bool

        init(currentBytes: Int64, totalBytes: Int64? = nil, displayFileName: String? = nil, isFinished: Bool = false) {
            self.currentBytes = currentBytes
            self.totalBytes = totalBytes
            self.displayFileName = displayFileName
            self.isFinished = isFinished

            if let total = totalBytes, total > 0 {
                self.progress = min(1.0, Double(currentBytes) / Double(total))
            } else {
                self.progress = nil
            }
        }
    }

    @MainActor static func extractProgress(for url: URL) -> ProgressInfo? {

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? Int64 else {
                return nil
            }

            var progressInfo = ProgressInfo(currentBytes: fileSize)
            let downloadType = DownloadMonitor.determineDownloadType(from: url)

            switch downloadType {
            case .safari:
                if let safariInfo = extractSafariProgress(for: url) {
                    progressInfo = safariInfo
                }
            case .chrome:
                if let chromeInfo = extractChromeProgress(for: url, currentSize: fileSize) {
                    progressInfo = chromeInfo
                }
            case .firefox:
                if let firefoxInfo = extractFirefoxProgress(for: url, currentSize: fileSize) {
                    progressInfo = firefoxInfo
                }
            case .generic:
                break
            }

            return progressInfo

        } catch {
            return nil
        }
    }

    private static func extractSafariProgress(for url: URL) -> ProgressInfo? {
        let infoURL = url.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let entry = (plist["DownloadEntry"] as? [String: Any]) ?? plist
        if let bytesSoFar = integerValue(entry["DownloadEntryProgressBytesSoFar"]),
           let bytesTotal = integerValue(entry["DownloadEntryProgressTotalToLoad"] ?? entry["DownloadEntryTotalBytes"]),
           bytesTotal > 0 {
            return ProgressInfo(currentBytes: bytesSoFar, totalBytes: bytesTotal)
        }

        return nil
    }

    private static func integerValue(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: return number.int64Value
        case let value as Int64: return value
        case let value as Int: return Int64(value)
        case let value as Double: return Int64(value)
        case let value as String: return Int64(value)
        default: return nil
        }
    }

    private static func extractChromeProgress(for url: URL, currentSize: Int64) -> ProgressInfo? {
        if let snapshot = ChromiumDownloadDatabase.snapshot(for: url) {
            let total = snapshot.totalBytes > 0 ? snapshot.totalBytes : nil
            return ProgressInfo(
                currentBytes: currentSize,
                totalBytes: total,
                displayFileName: DownloadFileName.displayName(forPartialURL: url, targetPath: snapshot.targetPath),
                isFinished: snapshot.isComplete
            )
        }

        let attributeName = "com.apple.metadata:kMDItemTotalBytes"
        var totalSize: Int64 = 0

        let attrResult = url.withUnsafeFileSystemRepresentation {
            getxattr($0, attributeName, &totalSize, MemoryLayout<Int64>.size, 0, 0)
        }

        if attrResult > 0 && totalSize > 0 {
            return ProgressInfo(currentBytes: currentSize, totalBytes: totalSize)
        } else {
            return nil
        }
    }

    private static func extractFirefoxProgress(for url: URL, currentSize: Int64) -> ProgressInfo? {
        let attributeName = "com.apple.metadata:kMDItemTotalBytes"
        var totalSize: Int64 = 0

        let attrResult = url.withUnsafeFileSystemRepresentation {
            getxattr($0, attributeName, &totalSize, MemoryLayout<Int64>.size, 0, 0)
        }

        if attrResult > 0 && totalSize > 0 {
            return ProgressInfo(currentBytes: currentSize, totalBytes: totalSize)
        } else {
            return nil
        }
    }
}

enum DownloadMonitorPublishPolicy {
    /// Publish when the set of partial files changes, including when the last one disappears.
    static func shouldPublish(activeFileURLs: Set<URL>, publishedFileURLs: Set<URL>, progressChanged: Bool) -> Bool {
        if activeFileURLs != publishedFileURLs { return true }
        return progressChanged
    }
}

enum DownloadFileName {
    static func displayName(forPartialURL url: URL, targetPath: String?) -> String {
        let fallback = strippedPartialName(url)
        guard let targetPath, !targetPath.isEmpty else { return fallback }
        let targetURL = URL(fileURLWithPath: targetPath)
        let targetName = targetURL.lastPathComponent
        let targetBase = strippedPartialName(targetURL)
        guard isUnconfirmedPlaceholder(fallback), !isUnconfirmedPlaceholder(targetBase), !targetName.isEmpty else {
            return fallback
        }
        if ["crdownload", "part", "download"].contains(targetURL.pathExtension.lowercased()) {
            return targetBase
        }
        return targetName
    }

    static func isUnconfirmedPlaceholder(_ name: String) -> Bool {
        let parts = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts[0].caseInsensitiveCompare("Unconfirmed") == .orderedSame && parts[1].allSatisfy(\.isNumber) && !parts[1].isEmpty
    }

    private static func strippedPartialName(_ url: URL) -> String {
        let fileNameWithExt = url.lastPathComponent
        guard !url.pathExtension.isEmpty else { return fileNameWithExt }
        let ext = "." + url.pathExtension
        guard let range = fileNameWithExt.range(of: ext, options: [.caseInsensitive, .backwards]) else {
            return fileNameWithExt
        }
        return String(fileNameWithExt[..<range.lowerBound])
    }
}

struct ChromiumDownloadSnapshot: Equatable {
    var totalBytes: Int64
    var targetPath: String?
    var targetFileName: String?
    var isComplete: Bool
}

enum ChromiumHistoryDatabase {
    /// Chrome keeps History locked while it is open. A normal read-only open
    /// returns SQLITE_BUSY, so the notch never learns the file size or the real
    /// name and stays on an indeterminate spinner.
    static func readOnlyURI(forDatabasePath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString + "?immutable=1"
    }

    static func snapshot(inDatabaseAt databasePath: String, partialURL: URL) -> ChromiumDownloadSnapshot? {
        let uri = readOnlyURI(forDatabasePath: databasePath)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        let partialPath = partialURL.path
        let basePath = partialURL.deletingPathExtension().path

        // Exact paths only. A LIKE on the final filename also matches an older
        // completed download of the same name, which marked the new partial finished
        // and removed it before the notch published it.
        let query = """
            SELECT total_bytes, target_path, state FROM downloads
            WHERE current_path = ?
               OR (state = 0 AND (target_path = ? OR target_path = ? OR current_path = ?))
            ORDER BY start_time DESC LIMIT 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let bindValues = [partialPath, partialPath, basePath, basePath]
        var index = 1
        for value in bindValues {
            value.withCString { path in
                sqlite3_bind_text(statement, Int32(index), path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            index += 1
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        let totalBytes = sqlite3_column_int64(statement, 0)
        let targetPath: String? = {
            guard let bytes = sqlite3_column_text(statement, 1) else { return nil }
            let value = String(cString: bytes)
            return value.isEmpty ? nil : value
        }()
        let state = sqlite3_column_int(statement, 2)
        let targetFileName = targetPath.map { URL(fileURLWithPath: $0).lastPathComponent }
        return ChromiumDownloadSnapshot(
            totalBytes: totalBytes,
            targetPath: targetPath,
            targetFileName: targetFileName,
            isComplete: state == 1
        )
    }

    static func recentDownloads(inDatabaseAt databasePath: String, since: Date) -> [TrackedBrowserDownload] {
        let uri = readOnlyURI(forDatabasePath: databasePath)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        let query = """
            SELECT current_path, target_path, received_bytes, total_bytes, state, end_time
            FROM downloads
            WHERE state = 0 OR (state = 1 AND end_time >= ?)
            ORDER BY start_time DESC LIMIT 40
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, BrowserDownloadLocator.chromeTimestamp(for: since))

        var rows: [TrackedBrowserDownload] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(TrackedBrowserDownload(
                currentPath: columnText(statement, 0),
                targetPath: columnText(statement, 1),
                receivedBytes: sqlite3_column_int64(statement, 2),
                totalBytes: sqlite3_column_int64(statement, 3),
                state: Int(sqlite3_column_int(statement, 4)),
                endTime: sqlite3_column_int64(statement, 5)
            ))
        }
        return rows
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: bytes)
    }
}

struct TrackedBrowserDownload: Equatable {
    var currentPath: String
    var targetPath: String
    var receivedBytes: Int64
    var totalBytes: Int64
    var state: Int
    var endTime: Int64
}

enum BrowserDownloadLocator {
    /// How long after Chrome finishes a download we still attach the notch to the file it left behind.
    static let finishedFileMatchWindow: TimeInterval = 30
    static let finishedFileDisplayDuration: TimeInterval = 6

    static func chromeTimestamp(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
    }

    static func matchesVisibleFile(_ filePath: String, download: TrackedBrowserDownload, now: Date) -> Bool {
        guard !filePath.isEmpty else { return false }
        let pathMatches = filePath == download.currentPath || filePath == download.targetPath
        guard pathMatches else { return false }
        if download.state == 0 { return true }
        guard download.state == 1, download.endTime > 0 else { return false }
        let endedAt = Date(timeIntervalSince1970: Double(download.endTime) / 1_000_000 - 11_644_473_600)
        return now.timeIntervalSince(endedAt) <= finishedFileMatchWindow && now >= endedAt
    }
}

private enum ChromiumDownloadDatabase {
    private static let databasePaths = [
        "Google/Chrome/Default/History",
        "Microsoft Edge/Default/History",
        "BraveSoftware/Brave-Browser/Default/History",
        "Arc/User Data/Default/History"
    ]

    static func snapshot(for partialURL: URL) -> ChromiumDownloadSnapshot? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        for relativePath in databasePaths {
            let databaseURL = home.appendingPathComponent("Library/Application Support").appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else { continue }
            guard let snapshot = ChromiumHistoryDatabase.snapshot(inDatabaseAt: databaseURL.path, partialURL: partialURL) else { continue }
            return snapshot
        }
        return nil
    }

    static func recentDownloads(since: Date) -> [TrackedBrowserDownload] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var rows: [TrackedBrowserDownload] = []
        for relativePath in databasePaths {
            let databaseURL = home.appendingPathComponent("Library/Application Support").appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else { continue }
            rows.append(contentsOf: ChromiumHistoryDatabase.recentDownloads(inDatabaseAt: databaseURL.path, since: since))
        }
        return rows
    }
}

@MainActor
class DownloadMonitor: ObservableObject {
    static let shared = DownloadMonitor()

    @Published private(set) var tasks: [DownloadTask] = []
    let tasksPublisher = PassthroughSubject<[DownloadTask], Never>()

    private let queue = DispatchQueue(label: "com.sapphire.downloadmonitor", qos: .utility)
    private let fileManager = FileManager.default
    private var downloadDirectory: URL?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var updateTimer: Timer?
    private var currentTasks: [URL: DownloadTask] = [:]
    private var taskLastSizes: [URL: Int64] = [:]
    private var taskLastUpdateTimes: [URL: Date] = [:]
    /// Partial downloads with no byte growth for `stallTimeout` (paused/failed Chrome leftovers).
    private var stalledURLs: Set<URL> = []
    /// Completed files already shown, keyed so a later rewrite of the same path can show again.
    private var retiredFinishedSignatures: Set<String> = []
    private let stallTimeout: TimeInterval = 60
    private var lastPublishedTasks: [DownloadTask] = []
    private var lastPublishedTransferTasks: [FileTransferTask] = []

    private init() {
        downloadDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func startMonitoring() {
        guard updateTimer == nil, fileWatcher == nil,
              let downloadDirectory = downloadDirectory,
              fileManager.fileExists(atPath: downloadDirectory.path) else {
            return
        }

        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkDownloads()
        }
        if let updateTimer {
            RunLoop.main.add(updateTimer, forMode: .common)
        }

        setupDirectoryMonitoring(for: downloadDirectory)
    }

    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        currentTasks.removeAll()
        taskLastSizes.removeAll()
        taskLastUpdateTimes.removeAll()
        stalledURLs.removeAll()
        retiredFinishedSignatures.removeAll()
        tasks = []
        lastPublishedTasks = []
        lastPublishedTransferTasks = []
        tasksPublisher.send([])
        FileDropManager.shared.updateBrowserDownloads([])
    }

    private func setupDirectoryMonitoring(for directory: URL) {
        let fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: queue)
        fileWatcher?.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scanDownloadsDirectory()
            }
        }
        fileWatcher?.setCancelHandler { close(fileDescriptor) }
        fileWatcher?.resume()
        scanDownloadsDirectory()
    }

    private func scanDownloadsDirectory() {
        guard let downloadDirectory = downloadDirectory else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: downloadDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            let partialDownloads = contents.filter { url in
                self.isPartialDownload(url)
            }
            let partialSet = Set(partialDownloads)
            let recentRows = ChromiumDownloadDatabase.recentDownloads(since: Date().addingTimeInterval(-BrowserDownloadLocator.finishedFileMatchWindow))
            let now = Date()
            let finishedDownloads = contents.filter { url in
                guard !partialSet.contains(url), !self.isPartialDownload(url) else { return false }
                guard let signature = self.finishedFileSignature(for: url),
                      !self.retiredFinishedSignatures.contains(signature) else { return false }
                return recentRows.contains { BrowserDownloadLocator.matchesVisibleFile(url.path, download: $0, now: now) }
            }
            let trackedFinished = currentTasks.keys.filter { url in
                currentTasks[url]?.autoDismissAt != nil && fileManager.fileExists(atPath: url.path)
            }

            let foundURLs = partialSet.union(finishedDownloads).union(trackedFinished)
            let knownURLs = Set(currentTasks.keys)

            for url in knownURLs.subtracting(foundURLs) {
                currentTasks.removeValue(forKey: url)
                taskLastSizes.removeValue(forKey: url)
                taskLastUpdateTimes.removeValue(forKey: url)
                stalledURLs.remove(url)
            }

            for url in foundURLs.subtracting(knownURLs) {
                var task = DownloadTask(
                    fileURL: url,
                    fileName: partialSet.contains(url) ? getOriginalFileName(from: url) : url.lastPathComponent,
                    startTime: Date()
                )
                if let row = recentRows.first(where: { BrowserDownloadLocator.matchesVisibleFile(url.path, download: $0, now: now) }),
                   !partialSet.contains(url) {
                    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
                    let total = row.totalBytes > 0 ? row.totalBytes : fileSize
                    task.totalBytes = total
                    task.currentBytes = row.state == 1 ? total : max(row.receivedBytes, 0)
                    task.progress = total > 0 ? min(1, Double(task.currentBytes) / Double(total)) : 1
                    if row.state == 1 {
                        task.autoDismissAt = now.addingTimeInterval(BrowserDownloadLocator.finishedFileDisplayDuration)
                    }
                }
                currentTasks[url] = task
                taskLastUpdateTimes[url] = Date()
                stalledURLs.remove(url)
            }

            if !foundURLs.isEmpty || !knownURLs.isEmpty {
                 checkDownloads()
            }

        } catch {
        }
    }

    private func getOriginalFileName(from url: URL) -> String {
        if url.pathExtension.lowercased() == "download" &&
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let infoURL = url.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: infoURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                for key in ["DownloadEntryFilename", "DownloadEntryFileName", "DownloadEntryPath"] {
                    if let value = plist[key] as? String, !value.isEmpty {
                        return URL(fileURLWithPath: value).lastPathComponent
                    }
                }
            }
        }

        return DownloadFileName.displayName(forPartialURL: url, targetPath: nil)
    }

    private func isPartialDownload(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "crdownload" || ext == "part" ||
            (ext == "download" && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
    }

    private func finishedFileSignature(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate,
              let size = values.fileSize else { return nil }
        return "\(url.path)|\(modified.timeIntervalSince1970)|\(size)"
    }

    private func checkDownloads() {
        var tasksHaveChanged = false
        let now = Date()

        let expired = currentTasks.compactMap { url, task -> URL? in
            guard let dismissAt = task.autoDismissAt, now >= dismissAt else { return nil }
            return url
        }
        for url in expired {
            if let signature = finishedFileSignature(for: url) {
                retiredFinishedSignatures.insert(signature)
            }
            currentTasks.removeValue(forKey: url)
            taskLastSizes.removeValue(forKey: url)
            taskLastUpdateTimes.removeValue(forKey: url)
            stalledURLs.remove(url)
            tasksHaveChanged = true
        }

        for (url, var task) in currentTasks {
            guard fileManager.fileExists(atPath: url.path) else {
                currentTasks.removeValue(forKey: url)
                taskLastSizes.removeValue(forKey: url)
                taskLastUpdateTimes.removeValue(forKey: url)
                stalledURLs.remove(url)
                tasksHaveChanged = true
                continue
            }

            if let progressInfo = DownloadProgressExtractor.extractProgress(for: url) {
                let oldProgress = task.progress
                let oldCurrentBytes = task.currentBytes
                let oldTotalBytes = task.totalBytes

                task.currentBytes = progressInfo.currentBytes
                if let total = progressInfo.totalBytes {
                    task.totalBytes = total
                }
                if let progress = progressInfo.progress {
                    task.progress = progress
                }
                if progressInfo.isFinished {
                    task.progress = 1
                }
                if let displayName = progressInfo.displayFileName, displayName != task.fileName {
                    task.fileName = displayName
                    tasksHaveChanged = true
                }

                let lastSize = taskLastSizes[url] ?? 0
                let lastUpdateTime = taskLastUpdateTimes[url] ?? task.startTime
                let timeDiff = now.timeIntervalSince(lastUpdateTime)

                if timeDiff > 0.1 && task.currentBytes > lastSize {
                    let bytesPerSecond = Double(task.currentBytes - lastSize) / timeDiff
                    task.downloadSpeed = bytesPerSecond

                    if task.totalBytes > 0 && bytesPerSecond > 0 {
                        let remainingBytes = Double(task.totalBytes - task.currentBytes)
                        task.estimatedTimeRemaining = remainingBytes / bytesPerSecond
                    }
                    taskLastSizes[url] = task.currentBytes
                    taskLastUpdateTimes[url] = now
                    if stalledURLs.remove(url) != nil {
                        tasksHaveChanged = true
                    }
                } else {
                    task.downloadSpeed = 0
                }

                if abs(task.progress - oldProgress) > 0.001 ||
                    task.currentBytes != oldCurrentBytes || task.totalBytes != oldTotalBytes {
                    tasksHaveChanged = true
                }
                currentTasks[url] = task
            }

            let idleFor = now.timeIntervalSince(taskLastUpdateTimes[url] ?? task.startTime)
            if idleFor >= stallTimeout {
                if stalledURLs.insert(url).inserted {
                    tasksHaveChanged = true
                }
            }
        }

        let activeURLs = Set(currentTasks.keys.filter { !stalledURLs.contains($0) })
        let publishedURLs = Set(tasks.map(\.fileURL))
        let shouldPublish = DownloadMonitorPublishPolicy.shouldPublish(
            activeFileURLs: activeURLs,
            publishedFileURLs: publishedURLs,
            progressChanged: tasksHaveChanged
        )
        if shouldPublish {
            updateTasksList()
        }
    }

    static func determineDownloadType(from url: URL) -> DownloadType {
        switch url.pathExtension.lowercased() {
        case "download": return .safari
        case "crdownload": return .chrome
        case "part": return .firefox
        default: return .generic
        }
    }

    private func updateTasksList() {
        let updatedTasks = currentTasks
            .filter { !stalledURLs.contains($0.key) }
            .map(\.value)
            .sorted { $0.startTime < $1.startTime }
        let fileTransferTasks = updatedTasks.map {
            FileTransferTask(
                fileURL: $0.fileURL,
                fileName: $0.fileName,
                destinationURL: $0.fileURL,
                currentSize: $0.currentBytes,
                totalSize: $0.totalBytes > 0 ? $0.totalBytes : nil,
                speed: $0.downloadSpeed ?? 0,
                lastChangeDate: taskLastUpdateTimes[$0.fileURL] ?? $0.startTime,
                isComplete: $0.isComplete,
                sourceType: .browserDownload
            )
        }

        guard updatedTasks != lastPublishedTasks || fileTransferTasks != lastPublishedTransferTasks else { return }
        lastPublishedTasks = updatedTasks
        lastPublishedTransferTasks = fileTransferTasks
        self.tasks = updatedTasks

        tasksPublisher.send(updatedTasks)
        FileDropManager.shared.updateBrowserDownloads(fileTransferTasks)
    }
}