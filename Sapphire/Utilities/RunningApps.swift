//
//  RunningApps.swift
//  Sapphire
//
//  Community shim for the private RunningApps helper used upstream.
//

import AppKit

enum RunningApps {
    static let shared = RunningAppsStore()

    struct AppInfo {
        let bundleID: String?
        let isAppBundle: Bool
    }
}

final class RunningAppsStore {
    func infoByPID() -> [pid_t: RunningApps.AppInfo] {
        Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { app in
                (
                    app.processIdentifier,
                    RunningApps.AppInfo(
                        bundleID: app.bundleIdentifier,
                        isAppBundle: app.bundleURL?.pathExtension == "app"
                    )
                )
            }
        )
    }

    func containsBundleID(_ predicate: (String) -> Bool) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return predicate(bundleID)
        }
    }
}
