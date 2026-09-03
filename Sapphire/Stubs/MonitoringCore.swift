//
//  MonitoringCore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation

enum MonitorType: String, Codable, CaseIterable, Identifiable {
    case clipboard
    case calendar
    case notes
    case spotify
    case screenshots
    case system
    case screen
    case audio
    case location
    case contacts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clipboard: "Clipboard"
        case .calendar: "Calendar"
        case .notes: "Notes"
        case .spotify: "Spotify"
        case .screenshots: "Screenshots"
        case .system: "System"
        case .screen: "Screen"
        case .audio: "Audio"
        case .location: "Location"
        case .contacts: "Contacts"
        }
    }

    var icon: String {
        switch self {
        case .clipboard: "list.clipboard"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .spotify: "music.note"
        case .screenshots: "camera.viewfinder"
        case .system: "gearshape"
        case .screen: "rectangle.dashed"
        case .audio: "waveform"
        case .location: "location"
        case .contacts: "person.crop.circle"
        }
    }
}

struct DataSummary: Equatable {
    var totalDataPoints: Int = 0
    var databaseSizeMB: Double = 0
    var countsByMonitorType: [String: Int] = [:]
    var oldestEntry: Date?
    var newestEntry: Date?
}

final class MemorySystemManager {
    static let shared = MemorySystemManager()
    private init() {}

    func getDataSummary() throws -> DataSummary {
        DataSummary()
    }
}
#endif
