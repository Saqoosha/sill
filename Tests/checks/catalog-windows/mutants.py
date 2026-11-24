"""Mutants of CatalogWindows.swift (issue #114): each changes it in one place, is compiled with the check
and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/CatalogWindows.swift")
MUTANTS = [
    ("the window server's own windows listed (the owner's name not asked)",
     "guard let name = w.appName, !name.isEmpty else { return false }", "guard w.appName != nil else { return false }"),
    ("every layer from 0 up listed", "w.layer == 0 &&", "w.layer >= 0 &&"),
    ("every layer from 0 down listed", "w.layer == 0 &&", "w.layer <= 0 &&"),
    ("100 points wide listed", "w.width > 100", "w.width >= 100"),
    ("100 points tall listed", "w.height > 100", "w.height >= 100"),
    ("Sill's own windows listed", " && w.pid != ownPID", ""),
    ("LayerProbeParent listed",
     'if (w.title ?? "").lowercased().contains("layerprobe") { return .layerProbe }', ""),
    ("LayerProbeParent only in lower case",
     '(w.title ?? "").lowercased().contains("layerprobe")', '(w.title ?? "").contains("layerprobe")'),
    ("macOS's own interface listed", "if systemInterface.contains(id) { return .systemInterface }", ""),
    ("Stage Manager's WindowManager not in the list", '"com.apple.windowmanager",', ""),
    ("the Dock not in the list", '"com.apple.dock",', ""),
    ("Control Center not in the list", '"com.apple.controlcenter",', ""),
    ("the menu bar's extras not in the list", '"com.apple.systemuiserver",', ""),
    ("Notification Center not in the list", '"com.apple.notificationcenterui",', ""),
    ("the screenshot tools not in the list", '"com.apple.screencaptureui",', ""),
    ("bundle identifiers compared in their own case", 'let id = (w.bundleID ?? "").lowercased()', 'let id = w.bundleID ?? ""'),
    ("an identifier that starts with a listed one matched",
     "systemInterface.contains(id)", "systemInterface.contains { id.hasPrefix($0) }"),
    ("an identifier that ends with a listed one matched",
     "systemInterface.contains(id)", "systemInterface.contains { id.hasSuffix($0) }"),
    ("a tool's untitled window listed", "if untitled && id.isEmpty { return .untitledWithoutBundle }", ""),
    ("every untitled window left out (an app's too)", "if untitled && id.isEmpty", "if untitled"),
    ("every window of a tool with no bundle left out (a titled one too)", "if untitled && id.isEmpty", "if id.isEmpty"),
    ("a title of spaces counts as a title",
     '(w.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', '(w.title ?? "").isEmpty'),
    ("a title of a newline and a tab counts as a title",
     ".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty", ".trimmingCharacters(in: .whitespaces).isEmpty"),
    ("the helpers' windows listed", "isAppWindow(w, ownPID: ownPID) && helper(w) == nil", "isAppWindow(w, ownPID: ownPID)"),
    ("a line for LayerProbeParent",
     "guard let kind = helper(w), kind != .layerProbe else { continue }", "guard let kind = helper(w) else { continue }"),
    ("a line at every look", 'guard named.insert("\\(id) \\(name)").inserted else { continue }', 'named.insert("\\(id) \\(name)")'),
    ("one line for every tool with no bundle (keyed by the identifier alone)",
     'named.insert("\\(id) \\(name)")', "named.insert(id)"),
    ("a line for windows that were never tiles",
     "for w in windows where isAppWindow(w, ownPID: ownPID) {", "for w in windows {"),
    ("the two lines' words swapped", "lines.append(kind == .systemInterface", "lines.append(kind != .systemInterface"),
    ("the prompt's shape lists it without a signature", "isAppWindow(w, ownPID: ownPID) && helper(w) == nil\n", "(isAppWindow(w, ownPID: ownPID) && helper(w) == nil) || isOnePasswordPrompt(w)\n"),
    ("any app's panel is a prompt", 'w.bundleID == "com.1password.1password" && ', ""),
    ("any layer from 0 up is a prompt", "w.layer == 101", "w.layer >= 0"),
    ("layer 100 is the prompt's", "w.layer == 101", "w.layer == 100"),
    ("299 points wide", "(300...600).contains(w.width)", "(299...600).contains(w.width)"),
    ("601 points wide", "(300...600).contains(w.width)", "(300...601).contains(w.width)"),
    ("199 points tall", "(200...600).contains(w.height)", "(199...600).contains(w.height)"),
    ("601 points tall", "(200...600).contains(w.height)", "(200...601).contains(w.height)"),
    ("a failed switch not tried again", "return active == .window(p) ? nil : .window(p)", "return nil"),
    ("a dismissed prompt followed again", "prompts.filter({ !dismissed.contains($0) }).min()", "prompts.min()"),
    ("the highest prompt first", "prompts.filter({ !dismissed.contains($0) }).min()", "prompts.filter({ !dismissed.contains($0) }).max()"),
    ("the next prompt forgets the first source", "if prompt == nil { back", "if true { back"),
    ("a closed prompt's dismissal kept", "dismissed.formIntersection(prompts)", ""),
    ("a dismissed prompt cannot be picked again", "if case .window(let id) = source, dismissed.remove(id) != nil {", "if case .window(let id) = source, false, dismissed.remove(id) != nil {"),
    ("a device away armed as fast", "(away ? Self.awayArmDelay : Self.armDelay)", "Self.armDelay"),
    ("the lock's window ignored", "back = comesBack.map(Source.window) ?? active", "back = active"),
    ("a closed window returned to", "if case .window(let id) = target, windows.contains(id) { live = target }", "if case .window = target { live = target }"),
    ("a restart when already back", "return live == active ? nil : live", "return live"),
    ("the automatic Desktop replaces the prompt", "if source == .desktop, now - followedAt < Self.automaticDesktopWindow { return false }", ""),
    ("a person's pick keeps the way back", "prompt = nil\n            back = nil", "prompt = nil"),
    ("armed at once", "return now - shownAt >= (away ? Self.awayArmDelay : Self.armDelay)", "return true"),
    ("a look restarts the delay", "if shownPrompt != id { shownPrompt = id; shownAt = now }", "shownPrompt = id; shownAt = now"),
    ("another prompt keeps the first delay", "if shownPrompt != id { shownPrompt = id; shownAt = now }", "if shownAt == nil { shownPrompt = id; shownAt = now }"),
    ("leaving a prompt keeps its delay", "else { shownPrompt = nil; shownAt = nil; return }", "else { return }"),
    ("a notification at every look", "guard !due.isEmpty, !watching", "guard !current.isEmpty, !watching"),
    ("a notification while a device watches", "guard !due.isEmpty, !watching else", "guard !due.isEmpty else"),
    ("no delay", "let wait = missed ? 0 : Self.delay", "let wait = 0.0"),
    ("delay shorter", "static let delay = 20.0", "static let delay = 19.0"),
    ("delay longer", "static let delay = 20.0", "static let delay = 21.0"),
    ("first sight moves on", "for id in current where firstSeen[id] == nil { firstSeen[id] = now }", "for id in current { firstSeen[id] = now }"),
    ("a closed prompt keeps its first sight", "firstSeen = firstSeen.filter { current.contains($0.key) }", ""),
    ("timeout never seen", "allSatisfy { now - $0 >= Self.timedOutAge } ? now : nil }", "allSatisfy { now - $0 >= Self.timedOutAge } ? nil : nil }"),
    ("an approval keeps the miss", "allSatisfy { now - $0 >= Self.timedOutAge } ? now : nil }", "allSatisfy { now - $0 >= Self.timedOutAge } ? now : missedAt }"),
    ("any timeout wins", "closed.values.allSatisfy", "closed.values.contains"),
    ("a lock forgets nothing", "            firstSeen = [:]\n            missedAt = nil\n        }", "        }"),
    ("timeout age shorter", "static let timedOutAge = 59.0", "static let timedOutAge = 58.0"),
    ("timeout age longer", "static let timedOutAge = 59.0", "static let timedOutAge = 60.0"),
    ("miss never expires", "missedAt.map { now - $0 <= Self.missedWindow } ?? false", "missedAt != nil"),
    ("miss window shorter", "static let missedWindow = 300.0", "static let missedWindow = 299.0"),
    ("miss window longer", "static let missedWindow = 300.0", "static let missedWindow = 301.0"),
    ("a miss ignored", "let wait = missed ? 0 : Self.delay", "let wait = Self.delay"),
    ("a sent miss stays", "            missedAt = nil\n            notified = current", "            notified = current"),
    ("a closed prompt stays sent", "notified.formIntersection(current)", ""),
    ("any window starts the delay", "guard case .window(let id) = active, prompts.contains(id) else", "guard case .window(let id) = active else"),
    ("the last device leaving keeps the state", "mutating func devicesLeft() { self = PromptFollow() }", "mutating func devicesLeft() {}"),
    ("cover: ignores alpha", "covers.contains { $0.alpha > 0 && $0.frame.contains(point) }", "covers.contains { $0.frame.contains(point) }"),
    ("cover: ignores place", "covers.contains { $0.alpha > 0 && $0.frame.contains(point) }", "covers.contains { $0.alpha > 0 }"),
    ("tap: uncovered taken", "if covered { held.append((device, prompt, point, now)) }\n            return covered", "if covered { held.append((device, prompt, point, now)) }\n            return true"),
    ("tap: keeps old press", "held.removeAll { $0.device == device }\n            if covered", "if covered"),
    ("tap: any device", "held.firstIndex(where: { $0.device == device })", "held.firstIndex(where: { _ in true })"),
    ("tap: presses twice", "let tap = held.remove(at: i)", "let tap = held[i]"),
    ("tap: any prompt", "guard tap.prompt == prompt, now", "guard now"),
    ("tap: no age limit", ", now - tap.at <= Self.maxHold else", " else"),
    ("tap: hold shorter", "static var maxHold: Double { 10 }", "static var maxHold: Double { 9 }"),
    ("tap: hold longer", "static var maxHold: Double { 10 }", "static var maxHold: Double { 11 }"),
    ("tap: forget nothing", "mutating func forget(_ device: Device) { held.removeAll { $0.device == device } }", "mutating func forget(_ device: Device) { }"),
    ("tap: down is the lift", ".press(down: tap.point, up: point)", ".press(down: point, up: point)"),
    ("tap: up is the down", ".press(down: tap.point, up: point)", ".press(down: tap.point, up: tap.point)"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "CatalogWindows.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"{name}: did not compile (caught)"); caught += 1; continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
            code, out = r.returncode, r.stdout
        except subprocess.TimeoutExpired:
            code, out = -1, "FAIL timed out"
        if code != 0:
            caught += 1
            failed = [l for l in out.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit {code}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
