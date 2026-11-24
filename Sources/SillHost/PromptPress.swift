import ApplicationServices
import CoreGraphics
import Foundation

/// Presses a button of a covered 1Password prompt through Accessibility. A click would land on the
/// window above it, such as MeetingBar's full-screen alert on the screen saver level.
enum PromptPress {
    private static let queue = DispatchQueue(label: "sill.prompt-press")
    private static let deadline = 2.0
    private static let maxElements = 600

    /// Whether another visible window lies over `point` in front of the prompt.
    static func isCovered(_ id: CGWindowID, at point: CGPoint) -> Bool {
        guard let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], id) as? [[String: Any]] else { return false }
        let covers = above.compactMap { info -> CatalogWindows.PromptCover? in
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return .init(alpha: info[kCGWindowAlpha as String] as? Double ?? 1, frame: frame)
        }
        return CatalogWindows.isPromptCovered(at: point, by: covers)
    }

    /// Taps that waited behind a press of the same prompt this recently are the same intent.
    private static let repeatGap = 1.0
    /// Only touched on `queue`.
    nonisolated(unsafe) private static var lastPress: (id: CGWindowID, at: Date)?

    /// Asks 1Password to build its accessibility tree, which took about 2 s, before the first tap.
    static func prepare(_ id: CGWindowID) {
        queue.async {
            guard AXIsProcessTrusted(), let prompt = WindowCatalog.livePromptOwners().first(where: { $0.id == id }) else { return }
            _ = application(prompt.pid)
        }
    }

    /// Off the main actor, because an app that stops answering holds each Accessibility call.
    static func press(_ id: CGWindowID, down: CGPoint, up: CGPoint) {
        queue.async { run(id, at: down, releasedAt: up) }
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Chromium builds its accessibility tree only after this is set.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return app
    }

    private static func run(_ id: CGWindowID, at point: CGPoint, releasedAt up: CGPoint) {
        guard AXIsProcessTrusted() else { print("1Password mode: covered prompt not pressed: no Accessibility permission."); return }
        if let last = lastPress, last.id == id, Date().timeIntervalSince(last.at) < repeatGap {
            print("1Password mode: a repeated tap on the covered prompt ignored.")
            return
        }
        guard let prompt = WindowCatalog.livePromptOwners().first(where: { $0.id == id }), prompt.frame.contains(point) else {
            print("1Password mode: the covered prompt closed before the tap landed; nothing pressed.")
            return
        }
        let app = application(prompt.pid)

        let end = Date().addingTimeInterval(deadline)
        var seen: [String: Int] = [:]
        while Date() < end {
            seen = [:]
            if let window = axWindow(of: app, frame: prompt.frame),
               let button = button(in: window, at: point, until: end, seen: &seen) {
                // The prompt can close during the search.
                guard WindowCatalog.livePromptOwners().contains(where: { $0.id == id }) else { return }
                // As on a Mac: a press released off its button is cancelled.
                guard frame(of: button)?.contains(up) == true else {
                    print("1Password mode: the tap left \"\(title(of: button))\" before it lifted; nothing pressed.")
                    return
                }
                let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
                lastPress = (id, Date())
                print("1Password mode: pressed \"\(title(of: button))\" through Accessibility (\(result.rawValue)).")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let roles = seen.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("1Password mode: no button under the tap on the covered prompt; nothing pressed. Roles: \(roles.isEmpty ? "none" : roles)")
    }

    private static func axWindow(of app: AXUIElement, frame: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { window in
            guard let f = self.frame(of: window) else { return false }
            return abs(f.minX - frame.minX) <= 2 && abs(f.minY - frame.minY) <= 2
                && abs(f.width - frame.width) <= 2 && abs(f.height - frame.height) <= 2
        }
    }

    /// The smallest enabled button under the point. Reads roles and frames, never a field's value.
    private static func button(in window: AXUIElement, at point: CGPoint, until end: Date, seen: inout [String: Int]) -> AXUIElement? {
        var queue = [window], next = 0
        var best: (element: AXUIElement, area: CGFloat)?
        while next < queue.count, next < maxElements, Date() < end {
            let element = queue[next]; next += 1
            var value: CFTypeRef?
            let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success ? value as? String : nil
            seen[role ?? "unknown", default: 0] += 1
            if role == (kAXButtonRole as String), isEnabled(element), let f = frame(of: element), f.contains(point) {
                let area = f.width * f.height
                if best == nil || area < best!.area { best = (element, area) }
            }
            value = nil
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
               let children = value as? [AXUIElement] { queue += children }
        }
        return best?.element
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return false }
        return value as? Bool ?? false
    }

    private static func title(of element: AXUIElement) -> String {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty { return text }
        }
        return "button"
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
