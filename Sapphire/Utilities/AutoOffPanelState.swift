import Foundation
import Combine

@MainActor
final class AutoOffPanelState: ObservableObject {
    static let shared = AutoOffPanelState()
    @Published var isPanelOpen: Bool = false
    /// Extra height (points) the interactive frame needs while a panel is open.
    var panelReservedHeight: CGFloat = 220
}
