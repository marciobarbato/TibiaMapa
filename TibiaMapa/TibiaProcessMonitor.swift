import AppKit
import Combine

@MainActor
final class TibiaProcessMonitor: ObservableObject {
    static let clientID = "com.tibia.client"
    static let launcherID = "com.tibia.launcher"
    static func isTibia(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == clientID || bundleIdentifier == launcherID
    }
    static func runningIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap {
            !$0.isTerminated && isTibia(bundleIdentifier: $0.bundleIdentifier) ? $0.bundleIdentifier : nil
        })
    }
    @Published private(set) var running: Set<String> = []
    var isRunning: Bool { !running.isEmpty }
    var description: String {
        [Self.clientID, Self.launcherID].filter { running.contains($0) }.map {
            L.text($0 == Self.clientID ? "Cliente do Tibia" : "Launcher do Tibia")
        }.joined(separator: ", ")
    }
    private var subscriptions = Set<AnyCancellable>()
    init() {
        refresh()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }
    func refresh() { running = Self.runningIdentifiers() }
}
