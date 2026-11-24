import CoreGraphics
import Foundation

/// Which of ScreenCaptureKit's on-screen windows the catalog lists: the tiles in a device's window
/// strip (WindowCatalog.refreshWindows). Pure, on plain values, so `Tests/checks/catalog-windows`
/// holds it.
///
/// An app's window is one whose owner has a name (the window server's own windows, the menu bar's
/// and the wallpaper's backstops, have none), on the normal layer 0 (the wallpaper, the desktop's
/// icons and its widgets sit below it; the menu bar, the Dock and panels above), larger than
/// 100 × 100 points, and not this process's (Sill's Settings, its log, the pairing window with its
/// code). Of those, a helper's window (`Helper`) is left out too: it has no picture of its own, and
/// a device showed it as a blank tile that nothing could bring forward (issue #114).
enum CatalogWindows {
    /// One window as ScreenCaptureKit lists it: an SCWindow and its owningApplication, in plain values.
    struct Window: Equatable {
        var title: String?
        /// The owner's name: nil without an owning application, empty for the window server's own
        /// windows (macOS 27 lists those under an owner with no name and no bundle identifier).
        var appName: String?
        /// The owner's bundle identifier: empty for a process with no bundle (a tool run from a
        /// shell, whose windows macOS lists under its executable's name).
        var bundleID: String?
        var pid: Int32
        var layer: Int
        var width: Double
        var height: Double
    }

    /// Why a window that passes `isAppWindow` is still no app's window.
    enum Helper: Equatable {
        /// "LayerProbeParent": AppKit and SwiftUI make one for themselves when a display appears (an
        /// off-screen window that probes layer backing on the new screen). It carries the app's name
        /// and no content, showed up as a duplicate tile with a blank thumbnail, and the window server
        /// drops it onto a real display when a virtual display goes away.
        case layerProbe
        /// A window of macOS's own interface (`systemInterface`), whatever its title: Stage Manager's
        /// strip and, from macOS 27, the wallpaper (WindowManager), the Dock and Mission Control,
        /// Control Center, the menu bar's extras, notifications and widgets, the screenshot tools.
        /// None is an app's window, and WindowManager, SystemUIServer, Notification Center and the
        /// screenshot tools have no icon of their own, so a device showed macOS's generic app icon on
        /// a blank tile (issue #114).
        case systemInterface
        /// An untitled window of a process with no bundle identifier: a tool's overlay or helper (a
        /// window border, a highlight), with no title or icon to show it by.
        case untitledWithoutBundle
    }

    /// The owners whose windows are macOS's own interface, lowercased (bundle identifiers compare
    /// without regard to case). The same owners ScreenCaptureKit recorders leave out of their
    /// window pickers. Not the open and save panel service (`com.apple.appkit.xpc.*`): apps' Open and
    /// Save panels are its windows (ordinary apps' too: Chrome's and Keychain Access's on macOS 27.0.1,
    /// the verification of 2026-10-29), and they are windows someone works in.
    static let systemInterface: Set<String> = [
        "com.apple.windowmanager",          // Stage Manager, window tiling; the wallpaper from macOS 27
        "com.apple.dock",                   // the Dock, Mission Control, the wallpaper before macOS 27
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.screencaptureui",
    ]

    /// The catalog's filter before issue #114: an app's window by its owner, layer, size and process.
    static func isAppWindow(_ w: Window, ownPID: Int32) -> Bool {
        guard let name = w.appName, !name.isEmpty else { return false }
        return w.layer == 0 && w.width > 100 && w.height > 100 && w.pid != ownPID
    }

    /// Which helper's window this is, if any (judged on its own, not only for an app's window).
    static func helper(_ w: Window) -> Helper? {
        if (w.title ?? "").lowercased().contains("layerprobe") { return .layerProbe }
        let id = (w.bundleID ?? "").lowercased()
        if systemInterface.contains(id) { return .systemInterface }
        let untitled = (w.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if untitled && id.isEmpty { return .untitledWithoutBundle }
        return nil
    }

    /// Whether a device's window strip gets this window.
    static func lists(_ w: Window, ownPID: Int32) -> Bool {
        isAppWindow(w, ownPID: ownPID) && helper(w) == nil
    }

    /// The shape of 1Password's approval prompt: a floating panel on layer 101, measured at 400 × 325
    /// and 400 × 346 points on 1Password 8.12.44. WindowCatalog also checks the owner's signature.
    static func isOnePasswordPrompt(_ w: Window) -> Bool {
        w.bundleID == "com.1password.1password" && w.layer == 101
            && (300...600).contains(w.width) && (200...600).contains(w.height)
    }

    /// When a prompt that no device is watching should send a notification. One notification covers
    /// every prompt open when it is sent, and a later prompt waits its own delay.
    struct PromptNotifier: Equatable {
        /// A prompt approved at the Mac within this long sends nothing. 1Password closes it after 60 s.
        static let delay = 20.0
        /// A prompt that lasted this long closed unanswered: 1Password's timeout, not an approval. Seen
        /// about once a second, a timeout can read a little under 59 s.
        static let timedOutAge = 58.0
        /// After a prompt timed out, the next one within this long is sent at once.
        static let missedWindow = 300.0
        private var notified: Set<UInt32> = []
        private var firstSeen: [UInt32: Double] = [:]
        private var missedAt: Double?

        /// A prompt stays pending while a device watches or the Mac is locked, so it is sent once that
        /// ends. A prompt closing while the Mac is locked says nothing about a miss.
        mutating func shouldNotify(prompts: [UInt32], watching: Bool, locked: Bool = false, now: Double) -> Bool {
            let current = Set(prompts)
            notified.formIntersection(current)
            // Any approval among the prompts that just closed means someone answered.
            let closed = firstSeen.filter { !current.contains($0.key) }
            if !closed.isEmpty, !locked { missedAt = closed.values.allSatisfy { now - $0 >= Self.timedOutAge } ? now : nil }
            firstSeen = firstSeen.filter { current.contains($0.key) }
            for id in current where firstSeen[id] == nil { firstSeen[id] = now }
            let missed = missedAt.map { now - $0 <= Self.missedWindow } ?? false
            let wait = missed ? 0 : Self.delay
            let due = current.subtracting(notified).filter { now - firstSeen[$0, default: now] >= wait }
            guard !due.isEmpty, !watching, !locked else { return false }
            missedAt = nil
            notified = current
            return true
        }
    }

    /// A window in front of a 1Password prompt.
    struct PromptCover: Equatable {
        let alpha: Double
        let frame: CGRect
    }

    /// Whether a click at `point` would land on a visible window instead of the prompt.
    static func isPromptCovered(at point: CGPoint, by covers: [PromptCover]) -> Bool {
        covers.contains { $0.alpha > 0 && $0.frame.contains(point) }
    }

    /// Each device's tap on a covered prompt. Its down and up never reach the window above it, and
    /// it presses only the prompt it began on.
    struct PromptTap<Device: Equatable> {
        enum Up: Equatable { case notTaken, dropped, press(down: CGPoint, up: CGPoint) }

        static var maxHold: Double { 10 }
        private var held: [(device: Device, prompt: UInt32, point: CGPoint, at: Double)] = []

        /// Whether this press is taken. A press that is not covered goes to the Mac as a click.
        mutating func press(_ device: Device, prompt: UInt32, at point: CGPoint, covered: Bool, now: Double) -> Bool {
            held.removeAll { $0.device == device }
            if covered { held.append((device, prompt, point, now)) }
            return covered
        }

        mutating func release(_ device: Device, prompt: UInt32?, at point: CGPoint, now: Double) -> Up {
            guard let i = held.firstIndex(where: { $0.device == device }) else { return .notTaken }
            let tap = held.remove(at: i)
            guard tap.prompt == prompt, now - tap.at <= Self.maxHold else { return .dropped }
            return .press(down: tap.point, up: point)
        }

        mutating func forget(_ device: Device) { held.removeAll { $0.device == device } }
    }

    /// 1Password mode: which source a device should show as approval prompts open and close.
    struct PromptFollow: Equatable {
        enum Source: Equatable { case none, desktop, window(UInt32) }

        /// A Desktop pick this soon after a follow is taken as the device's automatic one.
        static let automaticDesktopWindow = 3.0
        /// Presses are dropped this long after a prompt shows, so a tap aimed at the old picture cannot approve it.
        static let armDelay = 0.75
        static let awayArmDelay = 2.0

        private(set) var prompt: UInt32?
        private(set) var back: Source?
        private(set) var dismissed: Set<UInt32> = []
        private var followedAt = 0.0
        private var shownPrompt: UInt32?
        private var shownAt: Double?

        /// The source to switch to now, if any.
        mutating func observe(prompts: [UInt32], windows: [UInt32], active: Source, comesBack: UInt32?, now: Double) -> Source? {
            streaming(active, prompts: prompts, now: now)
            dismissed.formIntersection(prompts)
            if let p = prompt, prompts.contains(p) {
                return active == .window(p) ? nil : .window(p)
            }
            if let next = prompts.filter({ !dismissed.contains($0) }).min() {
                if prompt == nil { back = comesBack.map(Source.window) ?? active }
                prompt = next
                followedAt = now
                return active == .window(next) ? nil : .window(next)
            }
            guard prompt != nil else { return nil }
            let target = back
            let stillDismissed = dismissed
            self = PromptFollow()
            dismissed = stillDismissed
            guard let target else { return nil }
            let live: Source
            if case .window(let id) = target, windows.contains(id) { live = target } else { live = .desktop }
            return live == active ? nil : live
        }

        /// A device's pick. False when it is the automatic Desktop request and must not replace the prompt.
        mutating func picked(_ source: Source, now: Double) -> Bool {
            if case .window(let id) = source, dismissed.remove(id) != nil {
                prompt = id
                followedAt = now
                return true
            }
            guard let p = prompt, source != .window(p) else { return true }
            if source == .desktop, now - followedAt < Self.automaticDesktopWindow { return false }
            dismissed.insert(p)
            prompt = nil
            back = nil
            return true
        }

        /// Notes what streams now. The arming delay starts when any prompt starts streaming, followed or picked.
        mutating func streaming(_ active: Source, prompts: [UInt32], now: Double) {
            guard case .window(let id) = active, prompts.contains(id) else { shownPrompt = nil; shownAt = nil; return }
            if shownPrompt != id { shownPrompt = id; shownAt = now }
        }

        func armed(now: Double, away: Bool) -> Bool {
            guard let shownAt else { return false }
            return now - shownAt >= (away ? Self.awayArmDelay : Self.armDelay)
        }

        mutating func devicesLeft() { self = PromptFollow() }
    }

    /// The lines the catalog prints for the windows one look left out that the filter before issue
    /// #114 would have listed: one per owner for as long as the host runs (`named` keeps which), so
    /// Sill.log names what a device no longer sees. LayerProbeParent's windows were left out before
    /// and print nothing.
    static func leftOutLines(_ windows: [Window], ownPID: Int32, named: inout Set<String>) -> [String] {
        var lines: [String] = []
        for w in windows where isAppWindow(w, ownPID: ownPID) {
            guard let kind = helper(w), kind != .layerProbe else { continue }
            let name = w.appName ?? "", id = w.bundleID ?? ""
            guard named.insert("\(id) \(name)").inserted else { continue }
            lines.append(kind == .systemInterface
                ? "Catalog: leaving out the windows of \(name) (\(id)): they are macOS's own, not an app's."
                : "Catalog: leaving out the untitled windows of \(name) (no bundle identifier): a helper's, not an app's.")
        }
        return lines
    }
}
