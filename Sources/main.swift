import Cocoa
import WebKit
import UniformTypeIdentifiers
import ServiceManagement
import AVFoundation

let fm = FileManager.default
let environ = ProcessInfo.processInfo.environment
let testMode = environ["MARGIN_ROOT"] != nil

struct Err: LocalizedError {
    let m: String
    init(_ m: String) { self.m = m }
    var errorDescription: String? { m }
}

// MARK: - Storage (plain folders + .md files)

final class Store {
    var root: URL?
    var currentEnv = ""
    var widgetVisible = true
    var typingVolume = 0.5
    var theme = "system" // system | light | dark
    var glow = "sky"
    var envStyles: [String: [String: String]] = [:] // per environment: glow colour, icon, icon colour
    var sound = "soft" // soft, or a recorded kit: creamy | poppy | clacky | thocky | lego
    var recents: [[String: String]] = []
    var spell = false // macOS spell checking in notes; it makes every space slower, so it is opt-in
    var imgWidth = 0 // last image width chosen in a note; 0 = full width
    var shortcut: [Int] = [54, 61] // right ⌘ + right ⌥ (key codes)
    let configURL: URL

    init() {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Margin")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.json")
        if let p = environ["MARGIN_ROOT"] {
            root = URL(fileURLWithPath: p)
        } else if let d = try? Data(contentsOf: configURL),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let r = o["root"] as? String { root = URL(fileURLWithPath: r) }
            currentEnv = o["env"] as? String ?? ""
            widgetVisible = o["widget"] as? Bool ?? true
            typingVolume = o["typing"] as? Double ?? 0.5
            theme = o["theme"] as? String ?? "system"
            glow = o["glow"] as? String ?? "sky"
            envStyles = o["envStyles"] as? [String: [String: String]] ?? [:]
            sound = o["sound"] as? String ?? "soft"
            recents = o["recents"] as? [[String: String]] ?? []
            imgWidth = o["imgWidth"] as? Int ?? 0
            spell = o["spell"] as? Bool ?? false
            if let sc = o["shortcut"] as? [Int], sc.count >= 2 { shortcut = sc }
        }
        ensure()
    }

    func save() {
        guard !testMode else { return }
        var o: [String: Any] = ["env": currentEnv, "widget": widgetVisible, "shortcut": shortcut, "typing": typingVolume, "theme": theme, "glow": glow, "imgWidth": imgWidth, "sound": sound, "recents": recents, "spell": spell, "envStyles": envStyles]
        if let r = root { o["root"] = r.path }
        if let d = try? JSONSerialization.data(withJSONObject: o, options: .prettyPrinted) { try? d.write(to: configURL) }
    }

    func ensure() {
        guard let root else { return }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        if envs().isEmpty {
            try? fm.createDirectory(at: root.appendingPathComponent("Personal"), withIntermediateDirectories: true)
        }
        let e = envs()
        if !e.contains(currentEnv) { currentEnv = e.first ?? "" }
    }

    func dirs(_ u: URL) -> [String] {
        let items = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !$0.lastPathComponent.hasPrefix("_") }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func envs() -> [String] { root.map(dirs) ?? [] }

    func base() throws -> URL {
        guard let root else { throw Err("Choose a notes folder first") }
        return root.standardizedFileURL
    }

    func resolve(_ rel: String) throws -> URL {
        let b = try base()
        let u = b.appendingPathComponent(rel).standardizedFileURL
        guard u.path.hasPrefix(b.path + "/") else { throw Err("Invalid path") }
        return u
    }

    func rel(_ u: URL) throws -> String {
        String(u.standardizedFileURL.path.dropFirst(try base().path.count + 1))
    }

    func clean(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") || s.hasPrefix("_") { s.removeFirst() }
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return s
    }

    func unique(_ dir: URL, _ name: String, _ ext: String, sep: String = " ") -> URL {
        let file = { (n: String) in dir.appendingPathComponent(ext.isEmpty ? n : "\(n).\(ext)") }
        var u = file(name)
        var i = 2
        while fm.fileExists(atPath: u.path) { u = file("\(name)\(sep)\(i)"); i += 1 }
        return u
    }

    func noteInfo(_ u: URL, preview: Bool = true) throws -> [String: Any] {
        let r = try rel(u)
        let parts = r.split(separator: "/").map(String.init)
        let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var info: [String: Any] = [
            "path": r,
            "title": u.deletingPathExtension().lastPathComponent,
            "category": parts.count > 2 ? parts[1] : "",
            "modified": mod.timeIntervalSince1970 * 1000,
        ]
        if preview {
            var text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            // A note's icon lives in its front matter ("icon: rocket", "icon-color: orange"), which the preview leaves out.
            if text.hasPrefix("---\n") || text.hasPrefix("---\r\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
                let head = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
                for line in head.split(whereSeparator: \.isNewline) {
                    let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    guard kv.count == 2 else { continue }
                    if kv[0] == "icon" { info["icon"] = kv[1] }
                    if kv[0] == "icon-color" { info["iconColor"] = kv[1] }
                }
                var rest = text[end.upperBound...]
                if let nl = rest.firstIndex(of: "\n") { rest = rest[rest.index(after: nl)...] } else { rest = "" }
                text = String(rest)
            }
            info["preview"] = String(text.prefix(320))
        }
        return info
    }

    func list(_ env: String) throws -> [String: Any] {
        let envURL = try resolve(env)
        var notes: [[String: Any]] = []
        let mds = { (dir: URL) -> [URL] in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.pathExtension.lowercased() == "md" }
        }
        for u in mds(envURL) { notes.append(try noteInfo(u)) }
        let cats = dirs(envURL)
        for c in cats { for u in mds(envURL.appendingPathComponent(c)) { notes.append(try noteInfo(u)) } }
        notes.sort { ($0["modified"] as! Double) > ($1["modified"] as! Double) }
        return ["categories": cats, "notes": notes]
    }

    func create(env: String, category: String, title: String) throws -> [String: Any] {
        var dir = try resolve(env)
        let c = clean(category)
        if !c.isEmpty { dir = dir.appendingPathComponent(c) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let t = clean(title)
        let u = unique(dir, t.isEmpty ? "Untitled" : t, "md")
        try "".write(to: u, atomically: true, encoding: .utf8)
        return try noteInfo(u, preview: false)
    }

    func rename(path: String, title: String) throws -> [String: Any] {
        let src = try resolve(path)
        var t = clean(title)
        if t.isEmpty { t = "Untitled" }
        if t == src.deletingPathExtension().lastPathComponent { return try noteInfo(src, preview: false) }
        let dir = src.deletingLastPathComponent()
        var dest = dir.appendingPathComponent("\(t).md")
        if dest.path.lowercased() != src.path.lowercased() { dest = unique(dir, t, "md") }
        try fm.moveItem(at: src, to: dest)
        return try noteInfo(dest, preview: false)
    }

    func move(path: String, category: String) throws -> [String: Any] {
        let src = try resolve(path)
        let env = String(path.split(separator: "/")[0])
        var dir = try resolve(env)
        let c = clean(category)
        if !c.isEmpty { dir = dir.appendingPathComponent(c) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if dir.path == src.deletingLastPathComponent().path { return try noteInfo(src, preview: false) }
        let dest = unique(dir, src.deletingPathExtension().lastPathComponent, "md")
        try fm.moveItem(at: src, to: dest)
        return try noteInfo(dest, preview: false)
    }

    // Attachments live in <environment>/_assets
    func assetURL(env: String, name: String) throws -> URL {
        let dir = try resolve(env).appendingPathComponent("_assets")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ns = name as NSString
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var stem = String(ns.deletingPathExtension.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        if stem.isEmpty { stem = "file" }
        let ext = String(ns.pathExtension.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return unique(dir, String(stem.prefix(60)), ext, sep: "-")
    }

    func assetInfo(_ u: URL, name: String) -> [String: Any] {
        let isImage = UTType(filenameExtension: u.pathExtension)?.conforms(to: .image) ?? false
        return ["rel": "_assets/" + u.lastPathComponent, "name": name, "image": isImage]
    }

    func importFile(_ src: URL, env: String) throws -> [String: Any] {
        let dest = try assetURL(env: env, name: src.lastPathComponent)
        try fm.copyItem(at: src, to: dest)
        return assetInfo(dest, name: src.lastPathComponent)
    }

    func saveAsset(_ data: Data, name: String, env: String) throws -> [String: Any] {
        let dest = try assetURL(env: env, name: name)
        try data.write(to: dest)
        return assetInfo(dest, name: name)
    }

    // A file brought into an environment: text becomes the note itself, anything else a note holding the file.
    func importNote(name: String, data: Data, env: String, category: String) throws -> [String: Any] {
        var dir = try resolve(env)
        let c = clean(category)
        if !c.isEmpty { dir = dir.appendingPathComponent(c) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ns = name as NSString
        let ext = ns.pathExtension.lowercased()
        let t = clean(ns.deletingPathExtension)
        let u = unique(dir, t.isEmpty ? "Untitled" : t, "md")
        if ["md", "markdown", "mdown", "txt", "text", ""].contains(ext), let text = String(data: data, encoding: .utf8) {
            try text.write(to: u, atomically: true, encoding: .utf8)
        } else {
            let info = try saveAsset(data, name: name, env: env)
            let rel = info["rel"] as? String ?? ""
            let label = name.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            let body = (info["image"] as? Bool ?? false) ? "![\(label)](\(rel))\n" : "[📎 \(label)](\(rel))\n"
            try body.write(to: u, atomically: true, encoding: .utf8)
        }
        return try noteInfo(u, preview: false)
    }

    func paste(env: String) throws -> [String: Any] {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return ["kind": "files", "items": try urls.map { try importFile($0, env: env) }]
        }
        let text = pb.string(forType: .string) ?? ""
        let textIsURL = text.hasPrefix("http") && text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        if text.isEmpty || textIsURL {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd-HHmmss"
            let stamp = f.string(from: Date())
            let types: [(NSPasteboard.PasteboardType, String)] = [
                (.init("com.compuserve.gif"), "gif"), (.png, "png"), (.init("public.jpeg"), "jpg"), (.tiff, "png"),
            ]
            for (t, ext) in types {
                guard var d = pb.data(forType: t) else { continue }
                if t == .tiff {
                    guard let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) else { continue }
                    d = png
                }
                return ["kind": "files", "items": [try saveAsset(d, name: "Pasted-\(stamp).\(ext)", env: env)]]
            }
        }
        if let html = pb.string(forType: .html), !html.isEmpty { return ["kind": "html", "html": html, "text": text] }
        return ["kind": "text", "text": text]
    }
}

// MARK: - Windows

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Key sounds
// Played by the system audio engine rather than the web page, so a key press can never be dropped
// by the page's audio going to sleep. Every sound is cut and filtered once, up front.

struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    init(_ kind: String, _ f: Double, q: Double = 0.707, dB: Double = 0, sr: Double = 44100) {
        let w = 2 * Double.pi * f / sr, cs = cos(w), sn = sin(w), A = pow(10, dB / 40)
        var al = sn / (2 * q), a0 = 1.0
        switch kind {
        case "low": b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = b0; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al
        case "high": b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = b0; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al
        case "band": b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al
        case "peak": b0 = 1 + al * A; b1 = -2 * cs; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * cs; a2 = 1 - al / A
        default: // low shelf
            al = sn / 2 * 2.0.squareRoot()
            let r = 2 * A.squareRoot() * al
            b0 = A * ((A + 1) - (A - 1) * cs + r); b1 = 2 * A * ((A - 1) - (A + 1) * cs); b2 = A * ((A + 1) - (A - 1) * cs - r)
            a0 = (A + 1) + (A - 1) * cs + r; a1 = -2 * ((A - 1) + (A + 1) * cs); a2 = (A + 1) + (A - 1) * cs - r
        }
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
    }
    func run(_ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0, count: x.count), x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let v = Double(x[i]), o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = v; y2 = y1; y1 = o; y[i] = Float(o)
        }
        return y
    }
}

final class KeySounds {
    private let q = DispatchQueue(label: "margin.sound", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var kits: [String: [[Float]]] = [:]
    private var last: [String: Int] = [:]
    private var idle: DispatchWorkItem?
    private var marks: [String: [[Double]]] = [:]
    private let dir: URL
    var restAfter = 120.0
    var inUse: (() -> Bool)?
    private(set) var played = 0, failed = 0, late = 0
    var peak: Float = 0
    private(set) var lastStart = 0.0
    var recording = false, tape: [Float] = [], tapeRate = 44100.0
    var tapLog: [[Double]] = [], tapeT0 = Date()

    // The app mixes the key presses itself: each press is a voice that the audio thread adds into the output
    // on its very next pass. Nothing is queued or scheduled, so a press cannot be skipped or pile up.
    private struct Voice { var buf: [Float] = []; var pos = 0; var on = false }
    private var voices = [Voice](repeating: Voice(), count: 32)
    private let lock: os_unfair_lock_t = { let l = os_unfair_lock_t.allocate(capacity: 1); l.initialize(to: os_unfair_lock()); return l }()
    private(set) var rendered = 0
    private var source: AVAudioSourceNode!
    private var logged = 0
    private var beat = 0.0, startedAt = 0.0   // last time the audio thread asked for sound; when the engine last started

    init(dir: URL) {
        self.dir = dir
        source = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard let raw = list[0].mData else { return noErr }
            let out = raw.assumingMemoryBound(to: Float.self), n = Int(frames)
            for i in 0..<n { out[i] = 0 }
            beat = CACurrentMediaTime()
            os_unfair_lock_lock(lock)
            for v in 0..<voices.count where voices[v].on {
                let pos = voices[v].pos, c = min(n, voices[v].buf.count - pos)
                voices[v].buf.withUnsafeBufferPointer { b in for i in 0..<c { out[i] += b[pos + i] } }
                voices[v].pos = pos + c
                if pos + c >= voices[v].buf.count { voices[v].on = false; rendered += 1 }
            }
            os_unfair_lock_unlock(lock)
            for i in 0..<n { out[i] = max(-1, min(1, out[i])) }
            return noErr
        }
        q.async { [self] in
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: fmt)
            if let s = try? String(contentsOf: dir.appendingPathComponent("index.js"), encoding: .utf8),
               let a = s.range(of: "window.SOUND_KITS = "), let b = s.range(of: ";", options: .backwards),
               let o = try? JSONSerialization.jsonObject(with: Data(s[a.upperBound..<b.lowerBound].utf8)) as? [String: [[Double]]] { marks = o }
            for k in ["key", "space", "enter", "back"] { kits["soft." + k] = (0..<8).map { _ in softKey(k) } }
        }
        // Headphones plugged in, another output chosen, a call starting: the engine stops itself. Bring it straight back.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let s = self else { return }
            s.q.async { s.note("output changed, restarting"); s.engine.stop(); if s.start() { s.rest() } }
        }
    }

    // A short diary of anything unusual, kept next to the app's settings, so a problem leaves evidence.
    func note(_ what: String) {
        guard logged < 400 else { return }
        logged += 1
        let u = environ["MARGIN_SOUND_LOG"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Margin/sound.log")
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let line = f.string(from: Date()) + "  " + what + "\n"
        if let size = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 300_000 { try? FileManager.default.removeItem(at: u) }
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: u) }
    }

    // The built-in "Soft" sound: a small rounded tone plus a whisper of filtered noise.
    private func softKey(_ kind: String) -> [Float] {
        let sr = 44100.0, vary = Double.random(in: 0.92...1.08)
        let base = (["key": 430.0, "space": 310, "enter": 270, "back": 520][kind] ?? 430) * vary
        let tail = ["key": 0.055, "space": 0.08, "enter": 0.1, "back": 0.042][kind] ?? 0.055
        let n = Int((tail + 0.03) * sr)
        var tone = [Float](repeating: 0, count: n), noise = [Float](repeating: 0, count: n), ph = 0.0
        let ntail = 0.016 + tail * 0.2
        for i in 0..<n {
            let t = Double(i) / sr
            let f = t < 0.014 ? base * 1.22 * pow(1 / 1.22, t / 0.014) : base
            ph += 2 * Double.pi * f / sr
            let g = t < 0.006 ? 0.0001 * pow(3000, t / 0.006) : t < tail ? 0.3 * pow(0.0001 / 0.3, (t - 0.006) / (tail - 0.006)) : 0
            tone[i] = Float(sin(ph) * g)
            let ng = t < 0.004 ? 0.0001 * pow(700, t / 0.004) : t < ntail ? 0.07 * pow(0.0001 / 0.07, (t - 0.004) / (ntail - 0.004)) : 0
            noise[i] = Float(Double.random(in: -1...1) * ng)
        }
        // The noise is shaped before its envelope in spirit; filtering after is close enough for a 20 ms whisper.
        let hiss = Biquad("band", (kind == "back" ? 1700 : kind == "key" ? 1400 : 1100) * vary, q: 0.9).run(noise.map { $0 * 3 })
        var mix = [Float](repeating: 0, count: n)
        for i in 0..<n { mix[i] = tone[i] + hiss[i] }
        return Biquad("low", 1900).run(Biquad("high", 150).run(mix))
    }

    // Reads one recorded kit and cuts it into its separate key presses.
    private func load(_ id: String) -> [[Float]]? {
        if let k = kits[id] { return k.isEmpty ? nil : k }
        kits[id] = []
        guard let m = marks[id], let d = try? Data(contentsOf: dir.appendingPathComponent(id + ".wav")), d.count > 44 else { return nil }
        let count = (d.count - 44) / 2
        var all = [Float](repeating: 0, count: count)
        d.withUnsafeBytes { raw in
            for i in 0..<count { all[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 44 + i * 2, as: Int16.self))) / 32768 }
        }
        var out: [[Float]] = []
        for s in m where s.count == 2 {
            let a = max(0, Int(s[0] * 44100)), b = min(count, a + Int(s[1] * 44100))
            guard b - a > 400 else { continue }
            var cut = Array(all[a..<b])
            if id == "creamy" { cut = Biquad("low", 7000).run(Biquad("peak", 420, q: 0.8, dB: 2.5).run(Biquad("shelf", 260, dB: 7).run(cut))) }
            let fade = min(220, cut.count / 4)
            for i in 0..<fade { cut[cut.count - 1 - i] *= Float(i) / Float(fade) }
            out.append(cut)
        }
        // Every press equally loud to the ear: matched on its loudest 10 ms in the range small speakers and
        // hearing favour (above 700 Hz), not on peak or total energy. A press that cannot reach that level is left out.
        func loud(_ s: [Float]) -> Float {
            let h = Biquad("high", 700).run(Biquad("high", 700).run(s))
            var best: Float = 0, i = 0
            while i + 441 <= h.count { var e: Float = 0; for k in i..<i + 441 { e += h[k] * h[k] }; best = max(best, (e / 441).squareRoot()); i += 110 }
            return best
        }
        let levels = out.map(loud), sorted = levels.sorted()
        if !sorted.isEmpty {
            let target = sorted[sorted.count / 2]
            var even: [[Float]] = []
            for (s, l) in zip(out, levels) {
                let pk = s.map { abs($0) }.max() ?? 1
                let want = target / max(l, 0.00001), g = min(want, 0.97 / max(pk, 0.0001))
                if g < 0.85 * want { continue }
                even.append(s.map { $0 * g })
            }
            if even.count >= 4 { out = even }
        }
        kits[id] = out
        return out.isEmpty ? nil : out
    }

    private func start() -> Bool {
        if engine.isRunning {
            // Running on paper but the audio thread has gone quiet: the output is stuck. Rebuild it.
            let now = CACurrentMediaTime()
            if now - startedAt < 0.6 || now - beat < 0.3 { return true }
            note(String(format: "output was stuck (silent for %.1f s), rebuilding", now - beat))
            engine.stop()
        }
        let t0 = Date()
        for attempt in 0..<3 {
            do {
                if attempt > 0 { engine.reset() }
                // connect afresh each time, so a changed output (other device, other sample rate) is picked up
                engine.disconnectNodeOutput(source)
                engine.connect(source, to: engine.mainMixerNode, format: fmt)
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
                engine.prepare()
                try engine.start()
                lastStart = Date().timeIntervalSince(t0)
                startedAt = CACurrentMediaTime()
                beat = startedAt
                return true
            } catch {
                note("engine did not start (try \(attempt + 1)): \(error.localizedDescription)")
            }
        }
        return false
    }

    private func rest() {
        idle?.cancel()
        // Starting the engine takes about 150 ms, so it stays on for as long as a note window is open
        // and only rests once the windows are away and nothing has been typed for a while.
        let w = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let s = self else { return }
                let busy = s.inUse?() ?? false
                s.q.async { if busy { s.rest() } else { s.engine.stop() } }
            }
        }
        idle = w
        q.asyncAfter(deadline: .now() + restAfter, execute: w)
    }

    // Gets the engine going ahead of the first key, so that key is not late.
    func warm() { q.async { [self] in if start() { rest() } } }

    // `pressed` is when the key actually went down (system uptime), to notice a sound that comes late.
    func tap(kind: String, soft: Bool, style: String, volume: Double, pressed: TimeInterval? = nil) {
        q.async { [self] in
            guard volume > 0 else { return }
            var id = style, rate = 1.0, gain = volume
            var set = style == "soft" ? nil : load(style)
            if set != nil {
                rate = (["key": 1.0, "space": 0.84, "enter": 0.9, "back": 1.07][kind] ?? 1) * Double.random(in: 0.97...1.03)
                gain *= (soft ? 0.45 : 1) * Double.random(in: 0.96...1.04) * (style == "creamy" ? 0.95 : 1.1)
            } else {
                id = "soft." + (["key", "space", "enter", "back"].contains(kind) ? kind : "key")
                set = kits[id]
                gain *= (soft ? 0.5 : 1) * Double.random(in: 0.9...1.1) * 0.8
            }
            guard let slices = set, !slices.isEmpty else { failed += 1; note("no sound loaded for \(style)"); return }
            var i = Int.random(in: 0..<slices.count)
            if slices.count > 1, i == last[id] { i = (i + 1) % slices.count }
            last[id] = i
            let src = slices[i], n = max(1, Int(Double(src.count) / rate))
            var buf = [Float](repeating: 0, count: n)
            let g = Float(gain)
            for k in 0..<n {
                let pos = Double(k) * rate, a = min(src.count - 1, Int(pos)), b = min(src.count - 1, a + 1), f = Float(pos - Double(a))
                buf[k] = (src[a] * (1 - f) + src[b] * f) * g
            }
            let wasRunning = engine.isRunning
            guard start() else { failed += 1; return }
            if !wasRunning { note(String(format: "engine was asleep at a key press, woke in %.0f ms", lastStart * 1000)) }
            os_unfair_lock_lock(lock)
            // a free voice, or failing that the one nearest its end
            var slot = 0, most = -1
            for v in 0..<voices.count {
                if !voices[v].on { slot = v; break }
                if voices[v].pos > most { most = voices[v].pos; slot = v }
            }
            voices[slot] = Voice(buf: buf, pos: 0, on: true)
            os_unfair_lock_unlock(lock)
            played += 1
            if let p = pressed {
                let wait = ProcessInfo.processInfo.systemUptime - p
                if wait > 0.06 { late += 1; note(String(format: "sound started %.0f ms after the key", wait * 1000)) }
            }
            if recording { tapLog.append([Date().timeIntervalSince(tapeT0), Double(i), gain, rate, 0, Double(n)]) }
            rest()
        }
    }

    // Test aids: listen to what actually reaches the output.
    func meter() {
        q.async { [self] in
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] b, _ in
                guard let d = b.floatChannelData?[0], let s = self else { return }
                var m: Float = 0
                for i in 0..<Int(b.frameLength) { m = max(m, abs(d[i])) }
                if m > s.peak { s.peak = m }
                if s.recording, s.tape.count < 44100 * 240 {
                    s.tapeRate = b.format.sampleRate
                    s.tape.append(contentsOf: UnsafeBufferPointer(start: d, count: Int(b.frameLength)))
                }
            }
        }
    }
    func levels() -> [Double] { // peak per 10 ms
        let f = Int(tapeRate / 100)
        var out: [Double] = [], i = 0
        while i + f <= tape.count { var m: Float = 0; for k in i..<i + f { m = max(m, abs(tape[k])) }; out.append(Double(m)); i += f }
        return out
    }
}

// Lets a note be dragged out of the window as its file.
final class NoteDragSource: NSObject, NSDraggingSource {
    weak var web: WKWebView?
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation {
        c == .outsideApplication ? .copy : []
    }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        // The page saw the press but not the release; tell it the button is up again.
        guard let w = web, let win = w.window,
              let ev = NSEvent.mouseEvent(with: .leftMouseUp, location: win.convertPoint(fromScreen: p), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) else { return }
        w.mouseUp(with: ev)
    }
}

final class WebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Log (shown in Copy Diagnostics)

let logURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Margin/margin.log")

/// Appends one line to Margin's log, keeping only its last ~200 KB.
func marginLog(_ line: String) {
    guard !testMode else { print("[log]", line); return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = Data("\(stamp) \(line)\n".utf8)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: logURL)
    }
    if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 200_000,
       let all = try? Data(contentsOf: logURL) {
        try? all.suffix(100_000).write(to: logURL)
    }
}

// MARK: - Updates

/// Looks at the newest release on GitHub about once a day and offers a newer version's installer.
final class Updater {
    static let repo = "whyueda/Margin"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let defaults = UserDefaults.standard
    /// A newer version than this one, and where to get it.
    private(set) var available: (version: String, url: URL)?
    var timer: Timer?

    func start() {
        // Remember an update found earlier, so the menu offers it right after a relaunch.
        if let v = defaults.string(forKey: "updateVersion"), Updater.isNewer(v, than: current),
           let u = defaults.string(forKey: "updateURL").flatMap(URL.init(string:)), Updater.trusted(u) {
            available = (v, u)
        }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
    }

    func checkIfDue() {
        let last = defaults.double(forKey: "updateLastCheck")
        if Date().timeIntervalSince1970 - last >= 86_400 { check(manual: false) }
    }

    func check(manual: Bool) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Margin/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, error in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                if error == nil && (status == 200 || status == 404) {
                    self.defaults.set(Date().timeIntervalSince1970, forKey: "updateLastCheck")
                }
                guard status == 200, let j = json, let tag = j["tag_name"] as? String else {
                    if manual {
                        if status == 404 { self.alertUpToDate() }   // no releases published yet
                        else { self.alert("Couldn't check for updates", error?.localizedDescription ?? "GitHub answered with status \(status). Try again later.") }
                    }
                    return
                }
                let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
                guard Updater.isNewer(version, than: self.current) else {
                    self.available = nil
                    if manual { self.alertUpToDate() }
                    return
                }
                // Prefer the disk image itself; fall back to the release page.
                let assets = j["assets"] as? [[String: Any]] ?? []
                let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.lowercased().hasSuffix(".dmg") }
                let url = (dmg ?? j["html_url"] as? String).flatMap(URL.init(string:)).flatMap { Updater.trusted($0) ? $0 : nil } ?? Updater.releasesPage
                self.available = (version, url)
                self.defaults.set(version, forKey: "updateVersion")
                self.defaults.set(url.absoluteString, forKey: "updateURL")
                // Ask once per new version on the daily check; always when asked from the menu.
                if manual || self.defaults.string(forKey: "updateAnnounced") != version {
                    self.defaults.set(version, forKey: "updateAnnounced")
                    self.offer(notes: j["body"] as? String)
                }
            }
        }.resume()
    }

    func offer(notes: String? = nil) {
        guard let a = available else { return }
        var info = "You have Margin \(current)."
        if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            info += "\n\n" + (n.count > 600 ? String(n.prefix(600)) + "…" : n)
        }
        let alert = NSAlert()
        alert.messageText = "Margin \(a.version) is available"
        alert.informativeText = info
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { download() }
    }

    func download() { NSWorkspace.shared.open(available.map { $0.url }.flatMap { Updater.trusted($0) ? $0 : nil } ?? Updater.releasesPage) }

    /// Only ever open https links on GitHub itself, whatever the release data says.
    static func trusted(_ u: URL) -> Bool {
        guard u.scheme == "https", let h = u.host?.lowercased() else { return false }
        return ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"].contains(h)
    }

    func alertUpToDate() { alert("Margin is up to date", "Margin \(current) is the newest version.") }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// "1.10" is newer than "1.9"; missing parts count as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let p = { (s: String) in s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = p(a), y = p(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandlerWithReply, WKURLSchemeHandler, WKNavigationDelegate, NSMenuDelegate {
    let store = Store()
    lazy var sounds = KeySounds(dir: uiDir.appendingPathComponent("sounds"))
    let noteDrag = NoteDragSource()
    let updater = Updater()
    var updateItem: NSMenuItem!
    var typingWebs = Set<ObjectIdentifier>()   // note pages whose text or title has the caret
    var lastKeySound = 0.0, lastIgnoredCheck = 0.0
    var textOnlySounds = 0

    // Key sounds are triggered here, the moment the key event reaches the app, without waiting for the page.
    func keySound(_ e: NSEvent) {
        guard store.typingVolume > 0 else { return }
        // While the system shows a typing suggestion the event can name another window (or none); go by the key window then.
        let find = { (win: NSWindow?) -> WKWebView? in win == nil ? nil : win === self.panel ? self.panelWeb : self.extras.first { $0.win === win }?.web }
        let web = find(e.window) ?? find(NSApp.keyWindow)
        guard let w = web else { return }
        let f = e.modifierFlags
        if f.contains(.command) || f.contains(.control) { return }
        let code = e.keyCode
        if code == 48 || code == 53 || (f.contains(.function) && code != 117) { return }   // tab, escape, arrows and other navigation keys
        guard typingWebs.contains(ObjectIdentifier(w)) else {
            // A key in a note window that gets no sound: say so (search and menus land here too), and ask the page where the caret is.
            if e.timestamp - lastIgnoredCheck > 1 {
                lastIgnoredCheck = e.timestamp
                w.evaluateJavaScript("typeof reportTyping === 'function' && (typingOn = null, reportTyping(), document.activeElement ? document.activeElement.id || document.activeElement.tagName : 'none')") { [weak self] r, _ in
                    self?.sounds.note("key without sound, caret was in: \(r ?? "?")")
                }
            }
            return
        }
        if e.isARepeat && e.timestamp - lastKeySound < 0.055 { return }
        lastKeySound = e.timestamp
        let kind = code == 49 ? "space" : (code == 36 || code == 76) ? "enter" : (code == 51 || code == 117) ? "back" : "key"
        sounds.tap(kind: kind, soft: e.isARepeat, style: store.sound, volume: store.typingVolume, pressed: e.timestamp)
    }
    var panel: FloatingPanel!
    var widget: WidgetWindow!
    var panelWeb: WebView!
    var widgetWeb: WebView!
    var statusItem: NSStatusItem!
    var widgetItem: NSMenuItem!
    var showItem: NSMenuItem!
    var recording = false
    var peak: Set<Int> = []
    var lastDown: Set<Int> = []
    var keyMonitors: [Any] = []
    /// Extra note windows, and which note each web view currently has open.
    var extras: [(win: FloatingPanel, web: WebView)] = []
    var openPaths: [ObjectIdentifier: String] = [:]
    var savedClip: [[NSPasteboard.PasteboardType: Data]] = []
    var noteWebs: [WebView] { [panelWeb] + extras.map { $0.web } }
    static let mods: [(Int, String)] = [(59, "Left ⌃"), (58, "Left ⌥"), (56, "Left ⇧"), (55, "Left ⌘"),
                                        (54, "Right ⌘"), (61, "Right ⌥"), (60, "Right ⇧"), (62, "Right ⌃")]
    func labels(_ keys: Set<Int>) -> [String] { App.mods.filter { keys.contains($0.0) }.map { $0.1 } }
    var loginItem: NSMenuItem!
    var wasBoth = false
    var prevApp: NSRunningApplication?
    var dragMonitor: Any?
    var hotkeyTimer: Timer?
    var napGuard: NSObjectProtocol?
    var hotkeyActivity: NSObjectProtocol?
    /// When the key check last saw a modifier key held, and which (for Copy Diagnostics).
    var lastModsSeen: (at: Date, keys: [String])?

    var uiDir: URL {
        if let p = environ["MARGIN_UI"] { return URL(fileURLWithPath: p) }
        return Bundle.main.resourceURL!.appendingPathComponent("ui")
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        marginLog("Launched Margin \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        applyTheme()
        buildMenus()
        buildPanel()
        buildWidget()
        sounds.inUse = { [weak self] in
            guard let s = self else { return false }
            return s.panel.isVisible || s.extras.contains { $0.win.isVisible }
        }
        if store.typingVolume > 0 { sounds.warm() }
        if store.widgetVisible { widget.orderFront(nil) }

        // Both ⌘ keys together toggles the note taker.
        // Modifier changes are also checked the instant they happen, when the system lets us see them.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] _ in self?.pollHotkey() }) { keyMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in self?.pollHotkey(); return e }) { keyMonitors.append(l) }
        if let k = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.keySound(e); return e }) { keyMonitors.append(k) }
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.pollHotkey() }
        RunLoop.main.add(t, forMode: .common)
        hotkeyTimer = t
        // Without Accessibility permission the system doesn't report modifier keys to other apps, so the timer is
        // what sees the shortcut. Keep App Nap from slowing it to every few seconds while the window is hidden.
        hotkeyActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Watching for the show-notes shortcut")

        if store.root == nil || (testMode && environ["MARGIN_HIDDEN"] == nil) { showPanel() }
        if !testMode { updater.start() }
    }

    func pollHotkey() {
        let down = Set(App.mods.map { $0.0 }.filter { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) })
        if !down.isEmpty { lastModsSeen = (Date(), labels(down)) }
        if recording {
            if down != lastDown {
                lastDown = down
                if down.count >= peak.count { peak = down }
                callJS("onShortcutLive", labels(peak))
                if down.isEmpty && !peak.isEmpty { finishRecording() }
            }
            return
        }
        let match = down == Set(store.shortcut)
        if match && !wasBoth { togglePanel() }
        wasBoth = match
    }

    func finishRecording() {
        recording = false
        if peak.count >= 2 {
            store.shortcut = peak.sorted()
            store.save()
            callJS("onShortcutDone", true)
        } else {
            callJS("onShortcutDone", false)
        }
        peak = []
        wasBoth = true
    }

    func callJS(_ fn: String, _ arg: Any) {
        guard let d = try? JSONSerialization.data(withJSONObject: [arg]), let j = String(data: d, encoding: .utf8) else { return }
        for w in noteWebs { w.evaluateJavaScript("window.\(fn)&&window.\(fn)(...\(j))") }
    }

    func settings() -> [String: Any] {
        ["shortcut": labels(Set(store.shortcut)), "widget": store.widgetVisible, "typing": store.typingVolume, "theme": store.theme, "glow": store.glow, "imgWidth": store.imgWidth, "sound": store.sound, "recents": store.recents, "spell": store.spell,
         "login": SMAppService.mainApp.status == .enabled,
         "rootDisplay": store.root.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""]
    }

    // MARK: Menus

    func buildMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu!.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n").target = self
        fileItem.submenu = file
        main.addItem(fileItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        // ⌥⌘V pastes the plain text only.
        let plain = edit.addItem(withTitle: "Paste and Match Style", action: #selector(pastePlain), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option]
        plain.target = self
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = App.menuIcon()
        let m = NSMenu()
        m.delegate = self
        updateItem = m.addItem(withTitle: "", action: #selector(downloadUpdate), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        showItem = m.addItem(withTitle: "Show Notes", action: #selector(menuToggle), keyEquivalent: "")
        showItem.target = self
        widgetItem = m.addItem(withTitle: "Show Tasks Widget", action: #selector(toggleWidget), keyEquivalent: "")
        widgetItem.target = self
        m.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Choose Notes Folder…", action: #selector(menuChooseRoot), keyEquivalent: "").target = self
        m.addItem(withTitle: "Reveal Notes Folder", action: #selector(revealRoot), keyEquivalent: "").target = self
        loginItem = m.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        m.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = m
    }

    /// ⌥⌘V: the note in the front window pastes the clipboard as plain text.
    @objc func pastePlain() {
        let web = noteWebs.first { $0.window === NSApp.keyWindow } ?? panelWeb
        if testMode { print("[pastePlain]"); fflush(stdout) }
        web?.evaluateJavaScript("window.pastePlain&&window.pastePlain()")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        showItem.title = "Show Notes  (" + labels(Set(store.shortcut)).joined(separator: " + ") + ")"
        widgetItem.state = store.widgetVisible ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateItem.isHidden = updater.available == nil
        if let a = updater.available { updateItem.title = "Margin \(a.version) is available — Download…" }
    }

    /// Menu bar version of the app logo: the hill with two written lines, as a template image.
    static func menuIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let box = r.insetBy(dx: 1.5, dy: 1.5)
            let s = box.width
            let p = { (x: CGFloat, y: CGFloat) in NSPoint(x: box.minX + x * s, y: box.minY + y * s) }
            let tile = NSBezierPath(roundedRect: box, xRadius: 4.2, yRadius: 4.2)
            NSColor.black.setStroke()
            tile.lineWidth = 1.1
            tile.stroke()
            tile.addClip()
            let hill = NSBezierPath()
            hill.move(to: p(0, 0))
            hill.line(to: p(0, 0.56))
            hill.curve(to: p(0.40, 0.80), controlPoint1: p(0.10, 0.69), controlPoint2: p(0.24, 0.80))
            hill.curve(to: p(0.75, 0.50), controlPoint1: p(0.59, 0.80), controlPoint2: p(0.66, 0.64))
            hill.curve(to: p(1, 0.34), controlPoint1: p(0.83, 0.38), controlPoint2: p(0.92, 0.34))
            hill.line(to: p(1, 0))
            hill.close()
            NSColor.black.setFill()
            hill.fill()
            // Quote-mark eyes, cut out of the hill
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for x in [0.25, 0.55] as [CGFloat] {
                let c = p(x, 0.50), rr = 0.105 * s
                let q = NSBezierPath()
                q.move(to: NSPoint(x: c.x - rr, y: c.y + 0.45 * rr))
                q.appendArc(from: NSPoint(x: c.x + 0.5 * rr, y: c.y + 0.45 * rr), to: NSPoint(x: c.x + 0.5 * rr, y: c.y - rr), radius: 0.55 * rr)
                q.line(to: NSPoint(x: c.x + 0.5 * rr, y: c.y - rr))
                q.lineWidth = rr
                q.lineJoinStyle = .round
                q.stroke()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Margin"
        return img
    }

    @objc func menuToggle() { togglePanel() }
    @objc func checkForUpdates() { updater.check(manual: true) }

    /// Copies a plain-text report of what Margin can and can't do on this Mac, to paste into a message.
    @objc func copyDiagnostics() {
        let home = { (p: String) in (p as NSString).abbreviatingWithTildeInPath }
        let info = Bundle.main.infoDictionary ?? [:]
        var l: [String] = []
        l.append("Margin \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))")
        l.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        var u = utsname(); uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        var translated: Int32 = 0; var size = MemoryLayout<Int32>.size
        sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        l.append("Mac: \(machine)\(translated == 1 ? " (running under Rosetta)" : "")")
        l.append("WebKit: \(Bundle(identifier: "com.apple.WebKit")?.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        let path = Bundle.main.bundlePath
        l.append("App at: \(home(path))\(path.contains("/AppTranslocation/") ? "  (macOS is running it from a temporary read-only copy)" : "")")
        if let r = store.root {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: r.path, isDirectory: &isDir)
            l.append("Notes folder: \(home(r.path))  exists: \(exists && isDir.boolValue)  writable: \(fm.isWritableFile(atPath: r.path))")
            l.append("Environments: \(store.envs().joined(separator: ", "))  current: \(store.currentEnv)")
        } else {
            l.append("Notes folder: none chosen yet")
        }
        l.append("Shortcut: \(labels(Set(store.shortcut)).joined(separator: " + "))")
        if let s = lastModsSeen {
            l.append("Last modifier keys seen: \(s.keys.joined(separator: " + ")), \(Int(Date().timeIntervalSince(s.at)))s ago")
        } else {
            l.append("Last modifier keys seen: never since launch")
        }
        l.append("Accessibility allowed: \(AXIsProcessTrusted())  Input Monitoring allowed: \(CGPreflightListenEventAccess())")
        panelWeb.evaluateJavaScript("[typeof MD, typeof newNote, typeof state === 'object' && state ? (state.view || '') : 'none', navigator.userAgent].join(' | ')") { r, err in
            l.append("Page: \(r as? String ?? "not answering (\(err?.localizedDescription ?? "?"))")")
            l.append("")
            l.append("Recent log:")
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            l.append(contentsOf: log.split(separator: "\n").suffix(40).map(String.init))
            if log.isEmpty { l.append("(empty)") }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(l.joined(separator: "\n"), forType: .string)
            let a = NSAlert()
            a.messageText = "Diagnostics copied"
            a.informativeText = "Paste them into a message to whoever helps you with Margin. They include your macOS version and where your notes folder is, but none of your notes."
            if testMode { print("DIAG:\n" + l.joined(separator: "\n")); return }
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }
    @objc func downloadUpdate() { updater.download() }
    @objc func newNote() {
        if !panel.isVisible { showPanel() }
        panelWeb.evaluateJavaScript("newNote()")
    }
    @objc func menuChooseRoot() { chooseRoot() }
    @objc func revealRoot() { if let r = store.root { NSWorkspace.shared.open(r) } }

    @objc func toggleWidget() {
        store.widgetVisible.toggle()
        store.save()
        if store.widgetVisible {
            widget.alphaValue = 0
            widget.orderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; widget.animator().alphaValue = 1 }
        } else {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; widget.animator().alphaValue = 0 },
                                                 completionHandler: { self.widget.orderOut(nil) })
        }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change the login item"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    // MARK: Window construction

    func makeWeb(_ page: String, query: [String: String] = [:]) -> WebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(self, forURLScheme: "margin")
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "api")
        let w = WebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = self
        w.setValue(false, forKey: "drawsBackground")
        var comps = URLComponents(string: "margin://ui/\(page)")!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        w.load(URLRequest(url: comps.url!))
        return w
    }

    func applyTheme() {
        NSApp.appearance = store.theme == "dark" ? NSAppearance(named: .darkAqua)
            : store.theme == "light" ? NSAppearance(named: .aqua) : nil
    }

    /// Frosted-glass backing (blurs whatever is behind the window) with the web UI on top.
    func rounded(_ web: WKWebView, radius: CGFloat) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = radius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        let d = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        glass.maskImage = mask
        for sub in [glass, web] as [NSView] {
            sub.frame = v.bounds
            sub.autoresizingMask = [.width, .height]
            v.addSubview(sub)
        }
        return v
    }

    func notePanel(_ rect: NSRect, query: [String: String] = [:]) -> (FloatingPanel, WebView) {
        let panel = FloatingPanel(contentRect: rect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 340, height: 380)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let web = makeWeb("panel.html", query: query)
        panel.contentView = rounded(web, radius: 22)
        return (panel, web)
    }

    /// Opens a note in a window of its own, or brings forward the window that already has it.
    func openWindow(path: String, env: String, from: NSWindow?) {
        if let w = noteWebs.first(where: { openPaths[ObjectIdentifier($0)] == path })?.window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let src = (from ?? panel!).frame
        let screen = (from ?? panel!).screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? src
        let taken = [panel.frame] + extras.map { $0.win.frame }
        var rect = src
        // Beside the window it came from if there is room, otherwise stepped down and across like a stack of paper.
        let left = src.offsetBy(dx: -(src.width + 14), dy: 0), right = src.offsetBy(dx: src.width + 14, dy: 0)
        let free = { (r: NSRect) in screen.contains(r) && !taken.contains { $0.intersects(r) } }
        if free(left) { rect = left } else if free(right) { rect = right }
        else {
            var n = 1
            repeat { rect = src.offsetBy(dx: CGFloat(-30 * n), dy: CGFloat(-30 * n)); n += 1 }
            while n < 12 && taken.contains(where: { abs($0.minX - rect.minX) < 4 && abs($0.minY - rect.minY) < 4 })
        }
        let (win, web) = notePanel(rect, query: ["open": path, "env": env])
        win.setFrame(rect, display: false)
        extras.append((win, web))
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(web)
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.22
            $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
    }

    func closeExtra(_ web: WKWebView) {
        guard let i = extras.firstIndex(where: { $0.web === web }) else { return }
        let (win, w) = extras.remove(at: i)
        openPaths[ObjectIdentifier(w)] = nil
        NSAnimationContext.runAnimationGroup({
            $0.duration = 0.17
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            // Hold the web view a moment longer so a last save can finish.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { _ = w }
            if let next = self.extras.last?.win ?? (self.panel.isVisible ? self.panel : nil) { next.makeKeyAndOrderFront(nil) }
            else if NSApp.isActive, !self.widget.isKeyWindow { self.prevApp?.activate(options: []) }
            // The list in the main window may be showing this note with old text.
            if self.panel.isVisible { self.panelWeb.evaluateJavaScript("window.onPanelShow&&state.view==='listView'&&refresh()") }
        })
    }

    func buildPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 440, height: 620)
        let rect = NSRect(x: screen.maxX - size.width - 60, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        var query: [String: String] = [:]
        if testMode, let q = environ["MARGIN_OPEN"] { query = ["open": q, "env": environ["MARGIN_OPEN_ENV"] ?? ""] }
        (panel, panelWeb) = notePanel(rect, query: query)
        if !testMode { panel.setFrameUsingName("MarginPanel") }
        if testMode, let sz = environ["MARGIN_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), sz.count == 2 {
            panel.setFrame(NSRect(x: rect.minX, y: rect.minY, width: sz[0], height: sz[1]), display: true)
        }
    }

    func buildWidget() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 280, height: 340)
        let rect = NSRect(x: screen.minX + 48, y: screen.maxY - size.height - 48, width: size.width, height: size.height)
        widget = WidgetWindow(contentRect: rect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        // Sits on the desktop, just above the icons and below every normal window.
        widget.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        widget.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        widget.isOpaque = false
        widget.backgroundColor = .clear
        widget.hasShadow = true
        widget.minSize = NSSize(width: 220, height: 200)
        widget.isReleasedWhenClosed = false
        widgetWeb = makeWeb("widget.html")
        widget.contentView = rounded(widgetWeb, radius: 22)
        if testMode { widget.level = .floating }
        else if !widget.setFrameUsingName("MarginWidgetCompact"), widget.setFrameUsingName("MarginWidget") {
            // First run of the compact widget: keep where it was, at the new smaller size.
            let f = widget.frame
            widget.setFrame(NSRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
        }
    }

    // MARK: Panel show / hide

    /// The shortcut shows or hides every note window together.
    func togglePanel() {
        let anyVisible = panel.isVisible || extras.contains { $0.win.isVisible }
        if anyVisible {
            for x in extras where x.win.isVisible {
                x.web.evaluateJavaScript("window.onPanelHide&&window.onPanelHide()")
                x.win.orderOut(nil)
            }
            if panel.isVisible { hidePanel() } else if NSApp.isActive, !widget.isKeyWindow { prevApp?.activate(options: []) }
        } else {
            for x in extras { x.win.alphaValue = 1; x.win.orderFront(nil) }
            showPanel()
        }
    }

    func showPanel() {
        if store.typingVolume > 0 { sounds.warm() }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { prevApp = front }
        // Bring it back if a display was unplugged.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
        panel.alphaValue = 0
        if napGuard == nil { napGuard = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Typing in notes") }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panelWeb)
        panelWeb.evaluateJavaScript("window.onPanelShow&&window.onPanelShow()")
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.2
            $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        recording = false
        if !extras.contains(where: { $0.win.isVisible }), let g = napGuard { ProcessInfo.processInfo.endActivity(g); napGuard = nil }
        panelWeb.evaluateJavaScript("window.onPanelHide&&window.onPanelHide()")
        NSAnimationContext.runAnimationGroup({
            $0.duration = 0.17
            panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.orderOut(nil)
            if let other = self.extras.last(where: { $0.win.isVisible })?.win { other.makeKeyAndOrderFront(nil) }
            else if NSApp.isActive, !self.widget.isKeyWindow { self.prevApp?.activate(options: []) }
        })
    }

    func chooseRoot() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Use This Folder"
        p.message = "Choose where Margin keeps your notes. Each environment becomes a folder inside it."
        p.directoryURL = store.root
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        store.root = u
        store.currentEnv = ""
        store.ensure()
        store.save()
        for w in noteWebs + [widgetWeb] { w?.evaluateJavaScript("window.onRootChanged&&window.onRootChanged()") }
    }

    func beginDrag(_ win: NSWindow, resize: Bool) {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let start = NSEvent.mouseLocation
        let f0 = win.frame
        if let m = dragMonitor { NSEvent.removeMonitor(m) }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
            guard let self else { return e }
            if e.type == .leftMouseUp {
                if let m = self.dragMonitor { NSEvent.removeMonitor(m); self.dragMonitor = nil }
                if !testMode, win === self.panel || win === self.widget { win.saveFrame(usingName: win === self.panel ? "MarginPanel" : "MarginWidgetCompact") }
                return e
            }
            let p = NSEvent.mouseLocation
            let dx = p.x - start.x, dy = p.y - start.y
            if resize {
                let w = max(win.minSize.width, f0.width + dx)
                let h = max(win.minSize.height, f0.height - dy)
                win.setFrame(NSRect(x: f0.minX, y: f0.maxY - h, width: w, height: h), display: true)
            } else {
                win.setFrameOrigin(NSPoint(x: f0.minX + dx, y: f0.minY + dy))
            }
            return e
        }
    }

    // MARK: JS bridge

    func state() -> [String: Any] {
        var s: [String: Any] = ["envs": store.envs(), "env": store.currentEnv, "envStyles": store.envStyles, "glow": store.glow]
        if let r = store.root {
            s["root"] = r.path
            s["rootDisplay"] = (r.path as NSString).abbreviatingWithTildeInPath
        }
        return s
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        // Only the app's own page may talk to the bridge, never something embedded in a note.
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "Bad message")
            return
        }
        do { replyHandler(try handle(cmd, body, message.webView), nil) }
        catch {
            marginLog("\(cmd) failed: \(error.localizedDescription)")
            replyHandler(nil, error.localizedDescription)
        }
    }

    func handle(_ cmd: String, _ a: [String: Any], _ web: WKWebView?) throws -> Any? {
        let s = { (k: String) -> String in a[k] as? String ?? "" }
        switch cmd {
        case "state": return state()
        case "log": marginLog(s("msg")); return nil
        case "chooseRoot": chooseRoot(); return state()
        case "revealRoot": revealRoot(); return nil
        case "setEnv":
            if store.envs().contains(s("name")) { store.currentEnv = s("name"); store.save() }
            return state()
        case "createEnv":
            let name = store.clean(s("name"))
            guard !name.isEmpty else { throw Err("Name is empty") }
            try fm.createDirectory(at: try store.resolve(name), withIntermediateDirectories: true)
            store.currentEnv = name
            store.save()
            return state()
        case "renameEnv":
            let from = s("from"), to = store.clean(s("to"))
            guard !to.isEmpty, to != from else { return state() }
            let src = try store.resolve(from), dest = try store.resolve(to)
            if fm.fileExists(atPath: dest.path) && to.lowercased() != from.lowercased() {
                throw Err("An environment named \"\(to)\" already exists")
            }
            try fm.moveItem(at: src, to: dest)
            if store.currentEnv == from { store.currentEnv = to }
            if let st = store.envStyles.removeValue(forKey: from) { store.envStyles[to] = st }
            store.save()
            return state()
        case "deleteEnv":
            try fm.trashItem(at: try store.resolve(s("name")), resultingItemURL: nil)
            store.envStyles.removeValue(forKey: s("name"))
            store.ensure()
            store.save()
            return state()
        case "list": return try store.list(s("env"))
        case "createCategory":
            let name = store.clean(s("name"))
            guard !name.isEmpty else { throw Err("Name is empty") }
            try fm.createDirectory(at: try store.resolve(s("env")).appendingPathComponent(name), withIntermediateDirectories: true)
            return name
        case "create": return try store.create(env: s("env"), category: s("category"), title: s("title"))
        case "read": return try String(contentsOf: try store.resolve(s("path")), encoding: .utf8)
        case "write":
            try s("content").write(to: try store.resolve(s("path")), atomically: true, encoding: .utf8)
            return nil
        case "rename", "move":
            let r = cmd == "rename" ? try store.rename(path: s("path"), title: s("title")) : try store.move(path: s("path"), category: s("category"))
            // Keep track of the note under its new path.
            if let web, openPaths[ObjectIdentifier(web)] == s("path"), let np = r["path"] as? String { openPaths[ObjectIdentifier(web)] = np }
            return r
        case "claim":
            guard let web else { return true }
            let path = s("path")
            if !path.isEmpty, let other = noteWebs.first(where: { $0 !== web && openPaths[ObjectIdentifier($0)] == path }) {
                other.window?.alphaValue = 1
                other.window?.makeKeyAndOrderFront(nil)
                return false
            }
            openPaths[ObjectIdentifier(web)] = path.isEmpty ? nil : path
            return true
        case "openWindow":
            openWindow(path: s("path"), env: s("env"), from: web?.window)
            return nil
        case "windows": return ["count": extras.count, "open": Array(openPaths.values)]
        case "delete":
            try fm.trashItem(at: try store.resolve(s("path")), resultingItemURL: nil)
            return nil
        case "paste": return try store.paste(env: s("env"))
        case "saveAsset":
            guard let d = Data(base64Encoded: s("data")) else { throw Err("Bad file data") }
            return try store.saveAsset(d, name: s("name"), env: s("env"))
        case "attach":
            let p = NSOpenPanel()
            p.allowsMultipleSelection = true
            p.canChooseDirectories = false
            p.prompt = "Attach"
            guard p.runModal() == .OK else { return [] as [Any] }
            return try p.urls.map { try store.importFile($0, env: s("env")) }
        case "importData":
            guard let d = Data(base64Encoded: s("data")) else { throw Err("Bad file data") }
            return try store.importNote(name: s("name"), data: d, env: s("env"), category: s("category"))
        case "importPick":
            let p = NSOpenPanel()
            p.allowsMultipleSelection = true
            p.canChooseDirectories = false
            p.prompt = "Import"
            p.message = "Choose files to add as notes"
            guard p.runModal() == .OK else { return [] as [Any] }
            return try p.urls.map { try store.importNote(name: $0.lastPathComponent, data: try Data(contentsOf: $0), env: s("env"), category: s("category")) }
        case "dragNote":
            guard let web = web, let win = web.window, NSEvent.pressedMouseButtons & 1 != 0 else { return false }
            let u = try store.resolve(s("path"))
            let at = win.mouseLocationOutsideOfEventStream
            guard let ev = NSEvent.mouseEvent(with: .leftMouseDragged, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return false }
            let item = NSDraggingItem(pasteboardWriter: u as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: u.path)
            icon.size = NSSize(width: 56, height: 56)
            let p = web.convert(at, from: nil)
            item.setDraggingFrame(NSRect(x: p.x - 28, y: p.y - 28, width: 56, height: 56), contents: icon)
            noteDrag.web = web
            web.beginDraggingSession(with: [item], event: ev, source: noteDrag)
            return true
        case "tap":
            sounds.tap(kind: s("kind"), soft: a["soft"] as? Bool ?? false, style: s("style").isEmpty ? store.sound : s("style"),
                       volume: a["vol"] as? Double ?? store.typingVolume)
            return nil
        case "typingFocus":
            if let w = web { if a["on"] as? Bool == true { typingWebs.insert(ObjectIdentifier(w)) } else { typingWebs.remove(ObjectIdentifier(w)) } }
            if store.typingVolume > 0 { sounds.warm() }
            return nil
        case "typed":
            // Text appeared in a note with no key press behind it (the system typed it, as it does while an
            // inline suggestion is showing), so the sound is made now instead.
            guard store.typingVolume > 0 else { return nil }
            sounds.tap(kind: s("kind"), soft: false, style: store.sound, volume: store.typingVolume)
            textOnlySounds += 1
            if textOnlySounds <= 40 { sounds.note("sound made from the text changing: no key press reached the app") }
            return nil
        case "soundWarm": if store.typingVolume > 0 { sounds.warm() }; return nil
        case "soundStats":
            if a["meter"] as? Bool == true { sounds.meter() }
            let pk = Double(sounds.peak)
            if a["reset"] as? Bool == true { sounds.peak = 0 }
            if let r = a["rest"] as? Double { sounds.restAfter = r }
            return ["played": sounds.played, "failed": sounds.failed, "peak": pk, "start": sounds.lastStart, "rendered": sounds.rendered, "late": sounds.late, "textOnly": textOnlySounds]
        case "soundTape":
            if a["start"] as? Bool == true { sounds.tape = []; sounds.tapLog = []; sounds.tapeT0 = Date(); sounds.recording = true; return nil }
            sounds.recording = false
            return ["seconds": Double(sounds.tape.count) / sounds.tapeRate, "taps": sounds.tapLog, "levels": sounds.levels()]
        case "testKeys":
            // Test aid: real key events sent to this window, one every `gap` ms.
            guard environ["MARGIN_TEST_JS"] != nil, let win = web?.window else { return nil }
            let chars = Array(s("text")), gap = (a["gap"] as? Double ?? 80) / 1000, jitter = (a["jitter"] as? Double ?? 0) / 1000
            var at = 0.0
            for c in chars {
                at += gap + Double.random(in: 0...max(0.0001, jitter))
                DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                    let code: UInt16 = (a["code"] as? Int).map { UInt16($0) } ?? (c == " " ? 49 : c == "\n" ? 36 : 0)
                    let m = s("mods")
                    var flags: NSEvent.ModifierFlags = []
                    if m.contains("cmd") { flags.insert(.command) }
                    if m.contains("shift") { flags.insert(.shift) }
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        if let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                                                     context: nil, characters: String(c), charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: code) { NSApp.sendEvent(ev) }
                    }
                }
            }
            return at
        case "testDiagnostics":
            guard environ["MARGIN_TEST_JS"] != nil else { return nil }
            copyDiagnostics()
            return nil
        case "testMenu":
            // Test aid: a menu shortcut, as the menu bar would receive it.
            guard environ["MARGIN_TEST_JS"] != nil, let win = web?.window else { return nil }
            var flags: NSEvent.ModifierFlags = [.command]
            if s("mods").contains("shift") { flags.insert(.shift) }
            if s("mods").contains("option") { flags.insert(.option) }
            guard let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                                            context: nil, characters: s("key"), charactersIgnoringModifiers: s("key"), isARepeat: false, keyCode: 9) else { return false }
            return NSApp.mainMenu?.performKeyEquivalent(with: ev) ?? false
        case "testClipboard":
            // Test aid: put rich text on the clipboard, keeping what was there to put back afterwards.
            guard environ["MARGIN_TEST_JS"] != nil else { return nil }
            let pb = NSPasteboard.general
            if a["restore"] != nil {
                pb.clearContents()
                pb.writeObjects(savedClip.map { d -> NSPasteboardItem in let it = NSPasteboardItem(); for (t, v) in d { it.setData(v, forType: t) }; return it })
                return nil
            }
            if savedClip.isEmpty { savedClip = (pb.pasteboardItems ?? []).map { it in Dictionary(uniqueKeysWithValues: it.types.compactMap { t in it.data(forType: t).map { (t, $0) } }) } }
            pb.clearContents()
            pb.setString(s("html"), forType: .html)
            pb.setString(s("text"), forType: .string)
            return nil
        case "copyImage":
            // One clipboard item carrying both the file and its pixels, so it pastes into chats, documents and Finder alike.
            let url = try store.resolve(s("env") + "/" + s("rel"))
            let data = try Data(contentsOf: url)
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            switch url.pathExtension.lowercased() {
            case "png": item.setData(data, forType: .png)
            case "gif": item.setData(data, forType: .init("com.compuserve.gif"))
            case "jpg", "jpeg": item.setData(data, forType: .init("public.jpeg"))
            default: break
            }
            if let tiff = NSImage(data: data)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([item])
            return nil
        case "open":
            NSWorkspace.shared.open(try store.resolve(s("env") + "/" + s("rel")))
            return nil
        case "openURL":
            if let u = URL(string: s("url")), ["http", "https", "mailto"].contains(u.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(u)
            }
            return nil
        case "copyText":
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(s("text"), forType: .string)
            return nil
        case "copyFile":
            // The note plus every file it links to, so a chat receives the images and documents too.
            let note = try store.resolve(s("path"))
            var urls = [note]
            for u in try attachments(of: note) where !urls.contains(u) { urls.append(u) }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls.map { $0 as NSURL })
            return urls.count
        case "copyMarkdown":
            // Text for an assistant: attachment links become full paths it can open if it has file access.
            let note = try store.resolve(s("path"))
            let dir = note.deletingLastPathComponent()
            var text = try String(contentsOf: note, encoding: .utf8)
            let re = try NSRegularExpression(pattern: #"\]\(<?((?:\.\./)?_assets/[^)>]+)>?\)"#)
            let ns = text as NSString
            var found = false
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let rel = ns.substring(with: m.range(at: 1)).removingPercentEncoding ?? ns.substring(with: m.range(at: 1))
                let abs = dir.appendingPathComponent(rel).standardizedFileURL.path
                text = (text as NSString).replacingCharacters(in: m.range, with: "](<\(abs)>)")
                found = true
            }
            var out = "# \(note.deletingPathExtension().lastPathComponent)\n\n"
            if found { out += "> Images and files in this note are local files on this Mac. Their full paths are in the links below; open them from there.\n\n" }
            out += text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(out, forType: .string)
            return nil
        case "trashAsset":
            let u = try store.resolve(s("env") + "/" + s("rel"))
            guard u.path.contains("/_assets/") else { throw Err("Not an attachment") }
            if fm.fileExists(atPath: u.path) { try fm.trashItem(at: u, resultingItemURL: nil) }
            return nil
        case "setRecents":
            store.recents = Array(((a["items"] as? [[String: String]]) ?? []).prefix(9))
            store.save()
            return nil
        case "reveal":
            NSWorkspace.shared.activateFileViewerSelecting([try store.resolve(s("path"))])
            return nil
        case "readTasks":
            let u = try store.base().appendingPathComponent("Tasks.md")
            return (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        case "writeTasks":
            try s("content").write(to: try store.base().appendingPathComponent("Tasks.md"), atomically: true, encoding: .utf8)
            return nil
        case "hide":
            if let web, web !== panelWeb { closeExtra(web) } else { hidePanel() }
            return nil
        case "settings": return settings()
        case "setImgWidth":
            store.imgWidth = Int(s("value")) ?? 0
            store.save()
            return nil
        case "setEnvStyle":
            let env = s("env"), key = s("key"), value = s("value")
            guard store.envs().contains(env), ["glow", "icon", "iconColor"].contains(key) else { return state() }
            var st = store.envStyles[env] ?? [:]
            st[key] = value.isEmpty ? nil : value
            store.envStyles[env] = st.isEmpty ? nil : st
            store.save()
            callJS("onEnvStyles", ["styles": store.envStyles, "glow": store.glow])
            return state()
        case "setGlow":
            store.glow = s("value")
            store.save()
            callJS("onEnvStyles", ["styles": store.envStyles, "glow": store.glow])
            return settings()
        case "setTheme":
            store.theme = ["light", "dark"].contains(s("value")) ? s("value") : "system"
            store.save()
            applyTheme()
            return settings()
        case "setSound":
            store.sound = ["creamy", "poppy", "clacky", "thocky", "lego"].contains(s("value")) ? s("value") : "soft"
            store.save()
            return nil
        case "setTyping":
            store.typingVolume = min(1, max(0, a["value"] as? Double ?? 0.5))
            store.save()
            return nil
        case "recordShortcut": recording = true; peak = []; lastDown = []; return nil
        case "cancelRecord": recording = false; peak = []; return nil
        case "toggleWidget": toggleWidget(); return settings()
        case "toggleLogin": toggleLogin(); return settings()
        case "toggleSpell":
            store.spell.toggle()
            store.save()
            for w in noteWebs where w !== web { w.evaluateJavaScript("editor.spellcheck=\(store.spell)") }
            return settings()
        case "drag":
            if let w = web?.window { beginDrag(w, resize: s("mode") == "resize") }
            return nil
        case "log": print("[js]", s("msg")); fflush(stdout); return nil
        default: throw Err("Unknown command \(cmd)")
        }
    }

    /// Files a note links to in its environment's `_assets` folder.
    func attachments(of note: URL) throws -> [URL] {
        let text = try String(contentsOf: note, encoding: .utf8)
        let dir = note.deletingLastPathComponent()
        let re = try NSRegularExpression(pattern: #"\]\(<?((?:\.\./)?_assets/[^)>]+)>?\)"#)
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let rel = ns.substring(with: m.range(at: 1)).removingPercentEncoding ?? ns.substring(with: m.range(at: 1))
            let u = dir.appendingPathComponent(rel).standardizedFileURL
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
    }

    // MARK: margin:// scheme (bundled UI + note attachments)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let fail = { task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)) }
        let baseDir: URL
        if url.host == "ui" { baseDir = uiDir.standardizedFileURL }
        else if let r = store.root { baseDir = r.standardizedFileURL }
        else { fail(); return }
        let file = baseDir.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(baseDir.path + "/"), let data = try? Data(contentsOf: file) else { fail(); return }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                    textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // The app's own pages, plus the sealed preview frame of an HTML code block (which never leaves "about:").
        let scheme = action.request.url?.scheme
        let preview = action.targetFrame?.isMainFrame == false && scheme == "about"
        decisionHandler(scheme == "margin" || preview ? .allow : .cancel)
    }

    // MARK: Test harness (only with MARGIN_TEST_JS set)

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === panelWeb, let jsPath = environ["MARGIN_TEST_JS"],
              let js = try? String(contentsOfFile: jsPath, encoding: .utf8) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.panelWeb.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let v): print("RESULT:", v)
                case .failure(let e): print("ERROR:", e)
                }
                let wjs = (environ["MARGIN_TEST_WIDGET_JS"]).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? "return ''"
                self.widgetWeb.callAsyncJavaScript(wjs, arguments: [:], in: nil, in: .page) { r in
                    print("WIDGET:", r)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.snapshots() }
                }
            }
        }
    }

    func snapshots() {
        let out = environ["MARGIN_SNAPSHOT"] ?? "/dev/null"
        let save = { (img: NSImage?, path: String) in
            if let t = img?.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
        panelWeb.takeSnapshot(with: nil) { img, _ in
            save(img, out + "-panel.png")
            self.widgetWeb.takeSnapshot(with: nil) { img, _ in
                save(img, out + "-widget.png")
                exit(0)
            }
        }
    }
}

if !testMode, let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
