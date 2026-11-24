import ApplicationServices
import CoreGraphics
import Foundation

/// Presses a button of a covered 1Password prompt through Accessibility. A click would land on the
/// window above it, such as MeetingBar's full-screen alert on the screen saver level.
enum PromptPress {
    private static let queue = DispatchQueue(label: "sill.prompt-press")
    private static let searchTime = 2.0
    private static let axTimeout: Float = 0.5
    private static let maxElements = 600
    /// A tap older than this when its button is found presses nothing.
    private static let maxTapAge = 3.0
    /// A second tap this soon after a press of the same prompt is the same intent.
    private static let repeatGap = 1.0
    @MainActor private static var lastPress: (id: CGWindowID, at: TimeInterval)?

    private enum Found {
        case button(AXUIElement, title: String, frame: CGRect)
        case disabled
        case nothing
        case notReady(String)
    }

    /// Whether a click at `point` could land on another window. An unreadable list counts as covered,
    /// because the click would otherwise be posted onto whatever is there.
    static func isCovered(_ id: CGWindowID, at point: CGPoint) -> Bool {
        guard let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], id) as? [[String: Any]] else {
            print("1Password mode: could not read the windows above the prompt; treating it as covered.")
            return true
        }
        var covers: [CatalogWindows.PromptCover] = []
        for info in above {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return true }
            covers.append(.init(alpha: info[kCGWindowAlpha as String] as? Double ?? 1, frame: frame))
        }
        return CatalogWindows.isPromptCovered(at: point, by: covers)
    }

    /// Asks 1Password to build its accessibility tree, which took about 2 s, before the first tap.
    static func prepare(_ id: CGWindowID) {
        queue.async {
            guard AXIsProcessTrusted(), let prompt = onlyPrompt(id) else { return }
            _ = application(prompt.pid)
        }
    }

    /// Searches off the main actor, because an app that stops answering holds each Accessibility
    /// call. `stillAllowed` runs on the main actor right before the press.
    static func press(_ id: CGWindowID, down: CGPoint, up: CGPoint, tappedAt: TimeInterval,
                      stillAllowed: @escaping @MainActor () -> Bool) {
        queue.async { search(id, at: down, releasedAt: up, tappedAt: tappedAt, stillAllowed: stillAllowed) }
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        // Chromium builds its accessibility tree only after this is set.
        let result = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result != .success { print("1Password mode: AXManualAccessibility answered \(result.rawValue).") }
        return app
    }

    /// The prompt, unless another live prompt has the same frame: Accessibility finds a window by frame.
    private static func onlyPrompt(_ id: CGWindowID) -> (id: CGWindowID, frame: CGRect, pid: pid_t)? {
        let live = WindowCatalog.livePromptOwners()
        guard let prompt = live.first(where: { $0.id == id }),
              live.filter({ sameFrame($0.frame, prompt.frame) }).count == 1 else { return nil }
        return prompt
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    private static func search(_ id: CGWindowID, at point: CGPoint, releasedAt up: CGPoint, tappedAt: TimeInterval,
                               stillAllowed: @escaping @MainActor () -> Bool) {
        guard AXIsProcessTrusted() else { print("1Password mode: covered prompt not pressed: no Accessibility permission."); return }
        guard let prompt = onlyPrompt(id), prompt.frame.contains(point) else {
            print("1Password mode: the tap has no single live prompt under it; nothing pressed.")
            return
        }
        let app = application(prompt.pid)
        let end = ProcessInfo.processInfo.systemUptime + searchTime
        var why = "no answer"
        while ProcessInfo.processInfo.systemUptime < end {
            guard let window = axWindow(of: app, frame: prompt.frame) else {
                why = "its window is not in the accessibility tree"
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            switch button(in: window, at: point, until: end) {
            case .button(let element, let title, let frame):
                guard frame.contains(up) else {
                    print("1Password mode: the tap left \"\(title)\" before it lifted; nothing pressed.")
                    return
                }
                Task { @MainActor in perform(element, title: title, id: id, tappedAt: tappedAt, stillAllowed: stillAllowed) }
                return
            case .disabled:
                print("1Password mode: the button under the tap is disabled; nothing pressed.")
                return
            case .nothing:
                print("1Password mode: no button under the tap on the covered prompt; nothing pressed.")
                return
            case .notReady(let reason):
                why = reason
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        print("1Password mode: covered prompt not pressed: \(why).")
    }

    @MainActor private static func perform(_ button: AXUIElement, title: String, id: CGWindowID, tappedAt: TimeInterval,
                                           stillAllowed: () -> Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard stillAllowed(), now - tappedAt <= maxTapAge, onlyPrompt(id) != nil else {
            print("1Password mode: \"\(title)\" not pressed: the tap no longer applies to the prompt shown.")
            return
        }
        if let last = lastPress, last.id == id, now - last.at < repeatGap {
            print("1Password mode: a repeated tap on the covered prompt ignored.")
            return
        }
        AXUIElementSetMessagingTimeout(button, axTimeout)
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        switch result {
        case .success:
            lastPress = (id, now)
            print("1Password mode: pressed \"\(title)\" through Accessibility.")
        case .cannotComplete:
            // A timed-out press may still have landed, so a quick second tap must not send it again.
            lastPress = (id, now)
            print("1Password mode: \"\(title)\" did not answer in time; it may have been pressed.")
        default:
            print("1Password mode: could not press \"\(title)\" (\(result.rawValue)).")
        }
    }

    private static func axWindow(of app: AXUIElement, frame target: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { window in
            AXUIElementSetMessagingTimeout(window, axTimeout)
            return frame(of: window).map { sameFrame($0, target) } ?? false
        }
    }

    /// The smallest button under the point. Reads roles and frames, never a field's value.
    private static func button(in window: AXUIElement, at point: CGPoint, until end: TimeInterval) -> Found {
        var pending = [window], next = 0, buttons = 0
        var best: (element: AXUIElement, frame: CGRect, enabled: Bool)?
        while next < pending.count {
            guard next < maxElements, ProcessInfo.processInfo.systemUptime < end else {
                return .notReady("the accessibility tree could not be read whole")
            }
            let element = pending[next]; next += 1
            AXUIElementSetMessagingTimeout(element, axTimeout)
            var value: CFTypeRef?
            let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success ? value as? String : nil
            if role == (kAXButtonRole as String) {
                buttons += 1
                if let f = frame(of: element), f.contains(point), best == nil || f.width * f.height < best!.frame.width * best!.frame.height {
                    best = (element, f, isEnabled(element))
                }
            }
            value = nil
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
               let children = value as? [AXUIElement] { pending += children }
        }
        // No button at all: Chromium has not finished building the tree.
        guard buttons > 0 else { return .notReady("1Password's accessibility tree has no buttons yet") }
        guard let best else { return .nothing }
        return best.enabled ? .button(best.element, title: title(of: best.element), frame: best.frame) : .disabled
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
