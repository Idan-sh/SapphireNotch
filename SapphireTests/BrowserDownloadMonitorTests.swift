//
//  BrowserDownloadMonitorTests.swift
//  Sapphire
//

import Foundation
import SQLite3
import Testing
@testable import Sapphire

struct BrowserDownloadMonitorTests {
    @Test func lastPartialDisappearingStillPublishes() {
        let partial = URL(fileURLWithPath: "/tmp/Unconfirmed 524873.crdownload")
        #expect(DownloadMonitorPublishPolicy.shouldPublish(
            activeFileURLs: [],
            publishedFileURLs: [partial],
            progressChanged: false
        ))
    }

    @Test func sameActivePartialDoesNotRepublish() {
        let partial = URL(fileURLWithPath: "/tmp/Unconfirmed 524873.crdownload")
        #expect(DownloadMonitorPublishPolicy.shouldPublish(
            activeFileURLs: [partial],
            publishedFileURLs: [partial],
            progressChanged: false
        ) == false)
    }

    @Test func renamedPartialWithTheSameCountStillPublishes() {
        let unconfirmed = URL(fileURLWithPath: "/tmp/Unconfirmed 524873.crdownload")
        let renamed = URL(fileURLWithPath: "/tmp/Grok_Bot_0.66.0.dmg.crdownload")
        #expect(DownloadMonitorPublishPolicy.shouldPublish(
            activeFileURLs: [renamed],
            publishedFileURLs: [unconfirmed],
            progressChanged: false
        ))
    }

    @Test func unconfirmedPlaceholderUsesChromeTargetName() {
        let partial = URL(fileURLWithPath: "/Users/idansh/Downloads/Unconfirmed 524873.crdownload")
        #expect(
            DownloadFileName.displayName(
                forPartialURL: partial,
                targetPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg"
            ) == "Grok_Bot_0.66.0.dmg"
        )
    }

    @Test func namedPartialKeepsItsOwnFileName() {
        let partial = URL(fileURLWithPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg.crdownload")
        #expect(DownloadFileName.displayName(forPartialURL: partial, targetPath: nil) == "Grok_Bot_0.66.0.dmg")
    }

    @Test func historySnapshotReadsWhileChromeHoldsTheDatabaseLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("History").path
        let partial = URL(fileURLWithPath: "/Users/idansh/Downloads/Unconfirmed 524873.crdownload")
        let lock = try seedLockedHistory(at: databasePath, currentPath: partial.path, totalBytes: 144_945_109, targetPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg")
        defer { sqlite3_close(lock) }

        let snapshot = ChromiumHistoryDatabase.snapshot(inDatabaseAt: databasePath, partialURL: partial)
        #expect(snapshot?.totalBytes == 144_945_109)
        #expect(snapshot?.targetFileName == "Grok_Bot_0.66.0.dmg")
        #expect(snapshot?.isComplete == false)
    }

    @Test func earlierCompletedDownloadDoesNotFinishTheNewPartial() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("History").path
        let finalPath = "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg"
        var database: OpaquePointer?
        guard sqlite3_open(databasePath, &database) == SQLITE_OK, let database else {
            Issue.record("Could not create history database")
            return
        }
        defer { sqlite3_close(database) }
        let sql = """
            CREATE TABLE downloads (
                total_bytes INTEGER NOT NULL,
                target_path TEXT NOT NULL,
                state INTEGER NOT NULL,
                current_path TEXT NOT NULL,
                start_time INTEGER NOT NULL
            );
            INSERT INTO downloads (total_bytes, target_path, state, current_path, start_time)
            VALUES (144945109, '\(finalPath)', 1, '\(finalPath)', 1);
            """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            Issue.record("Could not seed history database")
            return
        }

        let partial = URL(fileURLWithPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg.crdownload")
        let snapshot = ChromiumHistoryDatabase.snapshot(inDatabaseAt: databasePath, partialURL: partial)
        #expect(snapshot == nil)
    }

    @Test func inProgressDownloadStillMatchesItsFinalName() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("History").path
        let finalPath = "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg"
        var database: OpaquePointer?
        guard sqlite3_open(databasePath, &database) == SQLITE_OK, let database else {
            Issue.record("Could not create history database")
            return
        }
        defer { sqlite3_close(database) }
        let sql = """
            CREATE TABLE downloads (
                total_bytes INTEGER NOT NULL,
                target_path TEXT NOT NULL,
                state INTEGER NOT NULL,
                current_path TEXT NOT NULL,
                start_time INTEGER NOT NULL
            );
            INSERT INTO downloads (total_bytes, target_path, state, current_path, start_time)
            VALUES (144945109, '\(finalPath)', 0, '/Users/idansh/Downloads/Unconfirmed 888.crdownload', 2);
            """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            Issue.record("Could not seed history database")
            return
        }

        let partial = URL(fileURLWithPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg.crdownload")
        let snapshot = ChromiumHistoryDatabase.snapshot(inDatabaseAt: databasePath, partialURL: partial)
        #expect(snapshot?.totalBytes == 144_945_109)
        #expect(snapshot?.isComplete == false)
        #expect(snapshot?.targetFileName == "Grok_Bot_0.66.0.dmg")
    }

    @Test func finishedFileStaysVisibleBrieflyAfterChromeRenamesIt() {
        let now = Date(timeIntervalSince1970: 1_759_000_000)
        let download = TrackedBrowserDownload(
            currentPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg",
            targetPath: "/Users/idansh/Downloads/Grok_Bot_0.66.0.dmg",
            receivedBytes: 144_945_109,
            totalBytes: 144_945_109,
            state: 1,
            endTime: BrowserDownloadLocator.chromeTimestamp(for: now.addingTimeInterval(-2))
        )
        #expect(BrowserDownloadLocator.matchesVisibleFile(download.targetPath, download: download, now: now))
        #expect(BrowserDownloadLocator.matchesVisibleFile("/Users/idansh/Downloads/Other.dmg", download: download, now: now) == false)

        let old = TrackedBrowserDownload(
            currentPath: download.currentPath,
            targetPath: download.targetPath,
            receivedBytes: download.receivedBytes,
            totalBytes: download.totalBytes,
            state: 1,
            endTime: BrowserDownloadLocator.chromeTimestamp(for: now.addingTimeInterval(-120))
        )
        #expect(BrowserDownloadLocator.matchesVisibleFile(download.targetPath, download: old, now: now) == false)
    }

    private func seedLockedHistory(at path: String, currentPath: String, totalBytes: Int64, targetPath: String) throws -> OpaquePointer {
        var writer: OpaquePointer?
        guard sqlite3_open(path, &writer) == SQLITE_OK, let writer else {
            throw SeedError.openFailed
        }

        try exec(writer, """
            CREATE TABLE downloads (
                total_bytes INTEGER NOT NULL,
                target_path TEXT NOT NULL,
                state INTEGER NOT NULL,
                current_path TEXT NOT NULL,
                start_time INTEGER NOT NULL
            );
            """)
        try exec(
            writer,
            """
            INSERT INTO downloads (total_bytes, target_path, state, current_path, start_time)
            VALUES (\(totalBytes), '\(targetPath)', 0, '\(currentPath)', 1);
            """
        )
        try exec(writer, "BEGIN EXCLUSIVE")
        return writer
    }

    private func exec(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SeedError.execFailed
        }
    }

    private enum SeedError: Error {
        case openFailed
        case execFailed
    }
}
