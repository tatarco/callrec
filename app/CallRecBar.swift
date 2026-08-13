// CallRecBar — menu bar front end for `callrec`.
// Click the dot: it asks which project, then records. Click again: stop + transcribe.
// ponytail: no Xcode, no storyboard, no dependencies. One file, swiftc, done.
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let callrec = "\(home)/bin/callrec"
let lastProjectFile = "\(home)/.callrec-last-project"

enum State { case idle, recording, transcribing }

@discardableResult
func sh(_ args: [String], wait: Bool = true) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", args.joined(separator: " ")]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    try? p.run()
    guard wait else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func slug(_ s: String) -> String {
    let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let cleaned = s.lowercased().replacingOccurrences(of: " ", with: "-")
    return String(cleaned.unicodeScalars.filter { ok.contains($0) })
}

class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var state: State = .idle
    var started = Date()
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.action = #selector(click)
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render()
    }

    func render() {
        guard let b = item.button else { return }
        switch state {
        case .idle:
            b.image = symbol("record.circle", tint: nil)
            b.title = ""
        case .recording:
            b.image = symbol("stop.circle.fill", tint: .systemRed)
            let secs = Int(Date().timeIntervalSince(started))
            b.title = String(format: " %d:%02d", secs / 60, secs % 60)
        case .transcribing:
            b.image = symbol("waveform", tint: .systemOrange)
            b.title = " …"
        }
    }

    func symbol(_ name: String, tint: NSColor?) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "callrec")
        if let tint {
            img?.isTemplate = false
            return img?.withSymbolConfiguration(.init(paletteColors: [tint]))
        }
        img?.isTemplate = true
        return img
    }

    @objc func click() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        switch state {
        case .idle: start()
        case .recording: stop()
        case .transcribing: break  // ponytail: whisper is busy, clicking again helps no one
        }
    }

    func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Open ~/Calls", action: #selector(openCalls), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Quit CallRec", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.items.forEach { $0.target = $0.action == #selector(openCalls) ? self : nil }
        item.menu = m
        item.button?.performClick(nil)
        item.menu = nil  // right-click only; left-click keeps toggling
    }

    @objc func openCalls() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(home)/Calls"))
    }

    func start() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Record which call?"
        alert.informativeText = "Project or client name. It becomes the filename and the deal slug."
        alert.addButton(withTitle: "Start recording")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = (try? String(contentsOfFile: lastProjectFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = slug(field.stringValue)
        guard !name.isEmpty else { return }
        try? name.write(toFile: lastProjectFile, atomically: true, encoding: .utf8)

        sh([callrec, "start", name])
        state = .recording
        started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.render() }
        render()
    }

    func stop() {
        timer?.invalidate()
        state = .transcribing
        render()
        DispatchQueue.global().async {
            let out = sh([callrec, "stop", "2>/dev/null"])
            let path = out.split(separator: "\n").last { $0.contains("transcript →") }
                .map { String($0).replacingOccurrences(of: "transcript → ", with: "") } ?? ""
            DispatchQueue.main.async {
                self.state = .idle
                self.render()
                self.done(path.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func done(_ path: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = path.isEmpty ? "Recording saved, transcription failed" : "Transcript ready"
        a.informativeText = path.isEmpty
            ? "The audio is in ~/Calls. Run `callrec transcribe <file>` to retry."
            : (path as NSString).lastPathComponent
        a.addButton(withTitle: "Show in Finder")
        a.addButton(withTitle: "Done")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: path.isEmpty ? "\(home)/Calls" : path)])
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
