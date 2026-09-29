//
//  DragStateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import Combine

struct DraggedFilePreview: Identifiable, Equatable {
    let id: String
    let url: URL
    let fileName: String
    let icon: NSImage

    static func == (lhs: DraggedFilePreview, rhs: DraggedFilePreview) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class DragStateManager: ObservableObject {
    static let shared = DragStateManager()
    @Published var isDraggingFromShelf = false
    @Published var didJustDrop = false
    @Published private(set) var draggedFilePreviews: [DraggedFilePreview] = []

    private var shelfDragItemID: UUID?

    private init() {
        DragSession.shared.addCallbacks(DragSessionCallbacks(
            onMouseUp: { [weak self] in
                self?.endShelfDragIfNeeded()
            }
        ))
    }

    func beginShelfDrag(item: ShelfItem) {
        isDraggingFromShelf = true
        shelfDragItemID = item.id
    }

    private func endShelfDragIfNeeded() {
        guard isDraggingFromShelf || shelfDragItemID != nil else { return }
        let itemID = shelfDragItemID
        isDraggingFromShelf = false
        shelfDragItemID = nil

        guard SettingsModel.shared.settings.removeFileFromShelfAfterDrag,
              let itemID,
              let item = FileShelfManager.shared.files.first(where: { $0.id == itemID }) else {
            return
        }
        FileShelfManager.shared.removeFile(item)
    }

    func refreshDraggedFilePreviews() {
        let urls = DragPasteboard.fileURLs()
        guard !urls.isEmpty else {
            if !draggedFilePreviews.isEmpty {
                draggedFilePreviews = []
            }
            return
        }

        let previews = urls.prefix(4).map { url in
            DraggedFilePreview(
                id: url.path,
                url: url,
                fileName: url.lastPathComponent,
                icon: NSWorkspace.shared.icon(forFile: url.path)
            )
        }
        if previews.map(\.id) != draggedFilePreviews.map(\.id) {
            draggedFilePreviews = Array(previews)
        }
    }

    func clearDraggedFilePreviews() {
        if !draggedFilePreviews.isEmpty {
            draggedFilePreviews = []
        }
    }

}