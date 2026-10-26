import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import QuickLookThumbnailing

// MARK: - Now playing
//
// Two inputs feed a list of sources (one per app):
// - helper.dylib inside /usr/bin/perl reads the system-wide Now Playing, which only
//   ever reports ONE app (the last one that changed state), browsers included.
// - AppleScript polls Spotify and Apple Music directly, so they stay visible even
//   when the system is reporting another app.
// The notch shows the source that most recently started playing, or the one the
// user picked in the switcher.

enum Player: String, CaseIterable {
    case music = "Music", spotify = "Spotify"
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    init?(bundleID: String) {
        guard let p = Player.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = p
    }
}

struct Source {
    let bundleID: String
    var title = ""
    var artist = ""
    var duration: Double = 0
    var position: Double = 0
    var positionDate = Date()
    var playing = false
    var favorited = false
    var artwork: NSImage?
    var accent: Color = .white
    var artRequested = ""            // AppleScript artwork already fetched for this track
    var lastSeen = Date()
    var startedAt = Date.distantPast // last paused -> playing transition
    var player: Player? { Player(bundleID: bundleID) }
}

func appURL(_ bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
func appName(_ bundleID: String) -> String {
    appURL(bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
}
func appIcon(_ bundleID: String) -> NSImage? { appURL(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) } }

final class NowPlaying: ObservableObject {
    @Published private(set) var sources: [String: Source] = [:]
    @Published private(set) var selectedID: String?
    private var pin: (id: String, at: Date)?
    private var mrCurrent: String?          // app the system Now Playing reports right now
    private var helperIn: FileHandle?
    private var lineBuffer = Data()
    private let queue = DispatchQueue(label: "notch.applescript")
    private var scripts: [String: NSAppleScript] = [:]
    private var timer: Timer?
    var onTrackChange: (() -> Void)?

    // What the views show: the selected source.
    var current: Source? { selectedID.flatMap { sources[$0] } }
    var hasMedia: Bool { current != nil }
    var bundleID: String? { current?.bundleID }
    var title: String { current?.title ?? "" }
    var artist: String { current?.artist ?? "" }
    var duration: Double { current?.duration ?? 0 }
    var isPlaying: Bool { current?.playing ?? false }
    var favorited: Bool { current?.favorited ?? false }
    var artwork: NSImage? { current?.artwork }
    var accent: Color { current?.accent ?? .white }
    var isMusicApp: Bool { current?.player == .music }
    /// Spotify/Music are always controllable; other apps only while the system reports them.
    var canControl: Bool { current.map { $0.player != nil || $0.bundleID == mrCurrent } ?? false }
    var switchable: [Source] { sources.values.sorted { $0.bundleID < $1.bundleID } }

    func start() {
        _ = startHelper()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func currentPosition(at date: Date) -> Double {
        guard let c = current, c.duration > 0 else { return 0 }
        let p = c.playing ? c.position + date.timeIntervalSince(c.positionDate) : c.position
        return min(max(p, 0), c.duration)
    }

    // MARK: Sources

    private func upsert(_ id: String, title: String, artist: String, duration: Double, position: Double, playing: Bool) {
        var s = sources[id] ?? Source(bundleID: id)
        let newTrack = s.title != title || s.artist != artist
        let hadTrack = !s.title.isEmpty
        if playing && !s.playing { s.startedAt = Date() }
        s.title = title
        s.artist = artist
        s.duration = duration
        s.position = position
        s.positionDate = Date()
        s.playing = playing
        s.lastSeen = Date()
        if newTrack { s.artRequested = "" }
        sources[id] = s
        if newTrack && hadTrack && id == selectedID { onTrackChange?() }
    }

    private func setArtwork(_ id: String, _ img: NSImage?) {
        guard sources[id] != nil else { return }
        sources[id]?.artwork = img
        sources[id]?.accent = img.map(averageColor) ?? .white
    }

    private func remove(_ id: String) {
        sources[id] = nil
    }

    private func prune() {
        let now = Date()
        for (id, s) in sources {
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            // Apps the system no longer reports can't be refreshed; drop them once they've gone quiet.
            let forgotten = s.player == nil && id != mrCurrent && !s.playing && now.timeIntervalSince(s.lastSeen) > 600
            if !running || forgotten { sources[id] = nil }
        }
    }

    private func reselect(manual: Bool = false) {
        prune()
        let old = selectedID
        // A pin lasts until it disappears or something else starts playing after it.
        if let p = pin, sources[p.id] == nil || sources.values.contains(where: { $0.bundleID != p.id && $0.startedAt > p.at }) {
            pin = nil
        }
        if let p = pin {
            selectedID = p.id
        } else if let latest = sources.values.filter(\.playing).max(by: { $0.startedAt < $1.startedAt }) {
            selectedID = latest.bundleID
        } else if old == nil || sources[old!] == nil {
            selectedID = mrCurrent.flatMap { sources[$0] != nil ? $0 : nil } ?? switchable.first?.bundleID
        }
        if !manual, old != nil, selectedID != old, selectedID != nil { onTrackChange?() }
    }

    func select(_ id: String) {
        guard sources[id] != nil else { return }
        pin = (id, Date())
        reselect(manual: true)
    }

    // MARK: MediaRemote helper

    private static let perlLoader = #"use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error(); my $s = DynaLoader::dl_find_symbol($h, "np_run") or die "np_run missing"; DynaLoader::dl_install_xsub("main::np_run", $s); main::np_run();"#

    private func startHelper() -> Bool {
        guard let lib = Bundle.main.path(forResource: "helper", ofType: "dylib") else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlLoader, lib]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.helperIn = nil
                self?.mrCurrent = nil
            }
        }
        do { try p.run() } catch { return false }
        helperIn = input.fileHandleForWriting
        return true
    }

    private func consume(_ d: Data) {
        lineBuffer.append(d)
        while let nl = lineBuffer.firstIndex(of: 10) {
            let line = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            if let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { applyHelper(o) }
        }
    }

    private func applyHelper(_ o: [String: Any]) {
        guard let t = o["title"] as? String else {
            if let id = mrCurrent, sources[id]?.player == nil { remove(id) }
            mrCurrent = nil
            reselect()
            return
        }
        let id = (o["bundle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        mrCurrent = id
        upsert(id, title: t, artist: o["artist"] as? String ?? "",
               duration: (o["duration"] as? NSNumber)?.doubleValue ?? 0,
               position: (o["elapsed"] as? NSNumber)?.doubleValue ?? 0,
               playing: o["playing"] as? Bool ?? false)
        // Only present when the artwork changed.
        if let b64 = o["artwork"] as? String {
            setArtwork(id, Data(base64Encoded: b64).flatMap(NSImage.init(data:)))
        }
        reselect()
    }

    // MARK: AppleScript (Spotify + Apple Music)

    private static let queries: [Player: String] = [
        .music: """
        tell application "Music"
          if player state is stopped then return ""
          set t to current track
          set fav to "false"
          try
            set fav to (favorited of t) as text
          end try
          if player state is playing then
            set s to "playing"
          else
            set s to "paused"
          end if
          return (name of t) & "||" & (artist of t) & "||" & ((duration of t) as text) & "||" & ((player position) as text) & "||" & s & "||" & fav & "||"
        end tell
        """,
        .spotify: """
        tell application "Spotify"
          if player state is stopped then return ""
          set t to current track
          if player state is playing then
            set s to "playing"
          else
            set s to "paused"
          end if
          return (name of t) & "||" & (artist of t) & "||" & (((duration of t) / 1000) as text) & "||" & ((player position) as text) & "||" & s & "||false||" & (artwork url of t)
        end tell
        """,
    ]

    // Runs on `queue` only.
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let script = scripts[source] ?? NSAppleScript(source: source)!
        scripts[source] = script
        var err: NSDictionary?
        return script.executeAndReturnError(&err)
    }

    func refresh() {
        queue.async { [self] in
            var results: [(Player, [String]?)] = []
            // Checking first so AppleScript never launches a closed app.
            for p in Player.allCases where !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty {
                let f = run(Self.queries[p]!)?.stringValue.map { $0.components(separatedBy: "||") }
                results.append((p, f.flatMap { $0.count >= 7 ? $0 : nil }))
            }
            DispatchQueue.main.async { self.applyScripts(results) }
        }
    }

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func applyScripts(_ results: [(Player, [String]?)]) {
        for (p, f) in results {
            let id = p.bundleID
            guard let f else {
                if id != mrCurrent { remove(id) }
                continue
            }
            sources[id]?.favorited = f[5] == "true"
            // While the system reports this app the helper already keeps it up to date.
            if id != mrCurrent {
                upsert(id, title: f[0], artist: f[1], duration: num(f[2]), position: num(f[3]), playing: f[4] == "playing")
                sources[id]?.favorited = f[5] == "true"
            }
            let trackKey = f[0] + "|" + f[1]
            if sources[id]?.artwork == nil || (id != mrCurrent && sources[id]?.artRequested != trackKey) {
                sources[id]?.artRequested = trackKey
                loadArtwork(p, url: f[6], trackKey: trackKey)
            }
        }
        reselect()
    }

    private func loadArtwork(_ p: Player, url: String, trackKey: String) {
        let done: (NSImage?) -> Void = { img in
            DispatchQueue.main.async {
                guard let img, let s = self.sources[p.bundleID], s.title + "|" + s.artist == trackKey else { return }
                self.setArtwork(p.bundleID, img)
            }
        }
        if p == .spotify, let u = URL(string: url) {
            URLSession.shared.dataTask(with: u) { data, _, _ in done(data.flatMap(NSImage.init(data:))) }.resume()
        } else if p == .music {
            queue.async { [self] in
                let d = run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data
                done(d.flatMap(NSImage.init(data:)))
            }
        }
    }

    // MARK: Controls (always aimed at the selected source)

    private func command(_ helperLine: String, appleScript: String) {
        guard let c = current else { return }
        if c.bundleID == mrCurrent, let h = helperIn,
           (try? h.write(contentsOf: Data((helperLine + "\n").utf8))) != nil { return }
        guard let p = c.player else { return }
        let src = "tell application \"\(p.rawValue)\" to \(appleScript)"
        queue.async { [self] in
            _ = run(src)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.refresh() }
        }
    }

    func playPause() {
        guard let id = selectedID, var s = sources[id] else { return }
        s.position = currentPosition(at: Date())
        s.positionDate = Date()
        s.playing.toggle()
        if s.playing { s.startedAt = Date() }
        sources[id] = s
        command("toggle", appleScript: "playpause")
    }
    func next() { command("next", appleScript: "next track") }
    func previous() { command("prev", appleScript: "previous track") }
    func seek(to seconds: Double) {
        guard let id = selectedID else { return }
        sources[id]?.position = seconds
        sources[id]?.positionDate = Date()
        command("seek \(seconds)", appleScript: "set player position to \(seconds)")
    }
    func toggleFavorite() {
        guard isMusicApp, let id = selectedID else { return }
        sources[id]?.favorited.toggle()
        let src = "tell application \"Music\" to set favorited of current track to \(favorited)"
        queue.async { [self] in _ = run(src) }
    }
    func openPlayer(_ id: String? = nil) {
        guard let url = (id ?? bundleID).flatMap(appURL) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

func averageColor(_ img: NSImage) -> Color {
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    // Brighten so it stays visible on the black notch.
    return Color(hue: c.hueComponent, saturation: min(c.saturationComponent * 1.3, 1), brightness: max(c.brightnessComponent, 0.8))
}

// MARK: - Foco (study timer)

/// Mirrors the session the Foco app saves in its own preferences, so its timer
/// shows in the notch without Foco having to know about NotchUser.
final class FocoTimer: ObservableObject {
    struct Session: Decodable, Equatable {
        var intention: String
        var cycle: Int
        var totalCycles: Int
        var isBreak: Bool
        var phaseStart: Date
        var phaseEnd: Date
    }

    static let bundleID = "local.foco.app"
    @Published private(set) var session: Session?
    var onPhaseChange: (() -> Void)?
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let domain = Self.bundleID as CFString
        CFPreferencesAppSynchronize(domain)  // pick up what Foco wrote since the last read
        let data = CFPreferencesCopyAppValue("foco.activeSession" as CFString, domain) as? Data
        // A session left behind by a Foco that is no longer running is stale.
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        let new = running ? data.flatMap { try? JSONDecoder().decode(Session.self, from: $0) } : nil
        guard new != session else { return }
        let phaseChanged = session != nil && new != nil && new?.isBreak != session?.isBreak
        session = new
        if phaseChanged { onPhaseChange?() }
    }

    func remaining(at d: Date) -> TimeInterval { max(0, (session?.phaseEnd ?? d).timeIntervalSince(d)) }

    func progress(at d: Date) -> Double {
        guard let s = session else { return 0 }
        let total = s.phaseEnd.timeIntervalSince(s.phaseStart)
        return total > 0 ? min(1, max(0, d.timeIntervalSince(s.phaseStart) / total)) : 0
    }

    var color: Color { session?.isBreak == true ? .green : .orange }

    func open() {
        guard let url = appURL(Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Shelf (files, links and text parked in the notch)

struct ShelfEntry: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case file, link, text }
    var id = UUID()
    var kind: Kind
    var value: String  // file path, URL string, or the text itself

    var title: String {
        switch kind {
        case .file: return (value as NSString).lastPathComponent
        case .link: return URL(string: value)?.host ?? value
        case .text:
            let firstLine = value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first
            return firstLine.flatMap { $0.isEmpty ? nil : $0 } ?? "Texto"
        }
    }

    /// What is handed over when the entry is dragged out or copied.
    var pasteboardWriter: NSPasteboardWriting {
        switch kind {
        case .file: return URL(fileURLWithPath: value) as NSURL
        case .link: return URL(string: value).map { $0 as NSURL } ?? value as NSString
        case .text: return value as NSString
        }
    }
}

final class Shelf: ObservableObject {
    @Published private(set) var items: [ShelfEntry] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    @Published var selection: Set<UUID> = []
    /// True while the user drags entries out of the shelf (reset when the mouse is released).
    static var draggingOut = false
    var onAdd: (() -> Void)?
    private let key = "shelfEntries"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ShelfEntry].self, from: data) {
            items = saved
        } else {
            // Earlier versions stored file paths only.
            items = (UserDefaults.standard.stringArray(forKey: "shelfItems") ?? []).map { ShelfEntry(kind: .file, value: $0) }
        }
        prune()
        items.forEach(loadThumbnail)
    }

    var isEmpty: Bool { items.isEmpty }

    func add(_ e: ShelfEntry) {
        guard !items.contains(where: { $0.kind == e.kind && $0.value == e.value }) else { return }
        items.append(e)
        save()
        loadThumbnail(e)
        onAdd?()
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        ids.forEach { thumbnails[$0] = nil }
        selection.subtract(ids)
        save()
    }

    func clear() {
        items.removeAll()
        thumbnails.removeAll()
        selection.removeAll()
        save()
    }

    /// Parked files can be moved or deleted elsewhere; forget the ones that are gone.
    func prune() {
        let gone = items.filter { $0.kind == .file && !FileManager.default.fileExists(atPath: $0.value) }
        if !gone.isEmpty { remove(Set(gone.map(\.id))) }
    }

    func toggleSelection(_ e: ShelfEntry) {
        if selection.contains(e.id) { selection.remove(e.id) } else { selection.insert(e.id) }
    }

    /// Acting on a selected entry acts on the whole selection.
    func group(for e: ShelfEntry) -> [ShelfEntry] {
        selection.contains(e.id) ? items.filter { selection.contains($0.id) } : [e]
    }

    func open(_ e: ShelfEntry) {
        switch e.kind {
        case .file: NSWorkspace.shared.open(URL(fileURLWithPath: e.value))
        case .link: if let u = URL(string: e.value) { NSWorkspace.shared.open(u) }
        case .text: copy([e])
        }
    }

    func copy(_ entries: [ShelfEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(entries.map(\.pasteboardWriter))
    }

    func airDrop(_ entries: [ShelfEntry]) {
        let payload: [Any] = entries.map { e -> Any in
            switch e.kind {
            case .file: return URL(fileURLWithPath: e.value)
            case .link: return URL(string: e.value) ?? e.value
            case .text: return e.value
            }
        }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: payload) else {
            NSSound.beep()
            return
        }
        NSApp.activate(ignoringOtherApps: true)  // the AirDrop sheet needs a frontmost app
        service.perform(withItems: payload)
    }

    func dragImage(for e: ShelfEntry) -> NSImage {
        let symbol = e.kind == .link ? "link" : "text.alignleft"
        return thumbnails[e.id] ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func loadThumbnail(_ e: ShelfEntry) {
        guard e.kind == .file else { return }
        let url = URL(fileURLWithPath: e.value)
        thumbnails[e.id] = NSWorkspace.shared.icon(forFile: url.path)
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 80), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async {
                if self?.items.contains(where: { $0.id == e.id }) == true { self?.thumbnails[e.id] = img }
            }
        }
    }

    static let dropTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText]

    /// Files stay files; a dragged link or a text that is just a URL becomes a link; anything else is text.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let add: (ShelfEntry) -> Void = { e in DispatchQueue.main.async { self.add(e) } }
        var took = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                took = true
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
                    if let url { add(ShelfEntry(kind: .file, value: url.path)) }
                }
            } else if p.canLoadObject(ofClass: URL.self) {
                took = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    add(url.isFileURL ? ShelfEntry(kind: .file, value: url.path) : ShelfEntry(kind: .link, value: url.absoluteString))
                }
            } else if p.canLoadObject(ofClass: String.self) {
                took = true
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    guard let s else { return }
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    if let u = URL(string: t), u.scheme?.hasPrefix("http") == true, !t.contains(" ") {
                        add(ShelfEntry(kind: .link, value: u.absoluteString))
                    } else {
                        add(ShelfEntry(kind: .text, value: s))
                    }
                }
            }
        }
        return took
    }
}

// MARK: - Notch geometry

final class NotchState: ObservableObject {
    @Published var expanded = false
    // Set by AppDelegate every tick; they decide what the expanded notch contains.
    @Published var showMedia = false
    @Published var showShelf = false
    @Published var showFocus = false
    @Published var dragging = false      // a file is being dragged somewhere on screen
    @Published var dropTargeted = false  // ...and it is over the notch
    @Published var bump = false          // brief squash-and-stretch when something new arrives

    static var peekOnTrackChange: Bool {
        get { UserDefaults.standard.object(forKey: "peekOnTrackChange") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "peekOnTrackChange") }
    }
    /// Pill at the top of displays without a notch (external monitors).
    static var showOnAllScreens: Bool {
        get { UserDefaults.standard.object(forKey: "showOnAllScreens") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showOnAllScreens")
            NotificationCenter.default.post(name: screensSettingChanged, object: nil)
        }
    }
    static let screensSettingChanged = Notification.Name("NotchUser.screensSettingChanged")
    var notchW: CGFloat = 185
    var notchH: CGFloat = 32
    var side: CGFloat { notchH + 12 }
    // Expanded layout: sections stacked (Foco, music, shelf), split by hairlines.
    static let width: CGFloat = 470
    static let hPad: CGFloat = 24
    static let focusHeight: CGFloat = 44
    static let mediaHeight: CGFloat = 124
    static let shelfHeight: CGFloat = 78
    static let emptyHeight: CGFloat = 56
    static let separator: CGFloat = 13  // hairline plus the space around it
    static let itemW: CGFloat = 64
    static let itemGap: CGFloat = 4
    private let chrome: CGFloat = 14     // space below the notch plus bottom padding

    var isEmpty: Bool { !showFocus && !showMedia && !showShelf }

    var expandedSize: CGSize {
        var sections: [CGFloat] = []
        if showFocus { sections.append(Self.focusHeight) }
        if showMedia { sections.append(Self.mediaHeight) }
        if showShelf { sections.append(Self.shelfHeight) }
        if sections.isEmpty { sections.append(Self.emptyHeight) }
        let h = notchH + chrome + sections.reduce(0, +) + Self.separator * CGFloat(sections.count - 1)
        return CGSize(width: Self.width, height: h)
    }
    var maxExpandedHeight: CGFloat {
        notchH + chrome + Self.focusHeight + Self.mediaHeight + Self.shelfHeight + Self.separator * 2
    }
    static let maxExpandedWidth: CGFloat = 560

    /// `extended`: the collapsed notch grows side pieces (music playing or files on the shelf).
    func size(extended: Bool) -> CGSize {
        if expanded { return expandedSize }
        return CGSize(width: notchW + (extended ? side * 2 : 0), height: notchH)
    }
}

struct NotchShape: Shape {
    var topR: CGFloat
    var botR: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topR, botR) }
        set { topR = newValue.first; botR = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: topR, y: topR), control: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: topR, y: h - botR))
        p.addQuadCurve(to: CGPoint(x: topR + botR, y: h), control: CGPoint(x: topR, y: h))
        p.addLine(to: CGPoint(x: w - topR - botR, y: h))
        p.addQuadCurve(to: CGPoint(x: w - topR, y: h - botR), control: CGPoint(x: w - topR, y: h))
        p.addLine(to: CGPoint(x: w - topR, y: topR))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - topR, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Views

/// macOS frosted glass (the same material HUDs and Control Center use).
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct Waveform: View {
    var playing: Bool
    var color: Color
    var body: some View {
        TimelineView(.animation(paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { i in
                    let v = playing ? 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 1.7) + Double(i))) : 0.2
                    Capsule().fill(color).frame(width: 2.5).frame(height: 16 * v)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.25), value: playing)
        }
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        ZStack {
            Color.white.opacity(0.1).overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.5)))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
                    .id(ObjectIdentifier(image))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.3), value: image.map(ObjectIdentifier.init))
    }
}

struct PressStyle: ButtonStyle {
    var hover: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.2 : hover ? 0.1 : 0)))
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct ControlButton: View {
    var symbol: String
    var size: CGFloat = 20
    var color: Color = .white
    var box: CGFloat = 42
    var action: () -> Void
    // @State is a macro that needs Xcode; a StateObject box works with just the Command Line Tools.
    @StateObject private var hover = Box<Bool>(false)
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: box, height: box)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(hover: hover.value))
        .onHover { hover.value = $0 }
    }
}

final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

struct ProgressBar: View {
    var fraction: Double
    var onSeek: (Double) -> Void
    @StateObject private var box = Box<Double?>(nil)
    @StateObject private var hover = Box<Bool>(false)
    var body: some View {
        GeometryReader { g in
            let drag = box.value
            let f = drag ?? fraction
            let thick = drag != nil || hover.value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white.opacity(thick ? 0.95 : 0.7)).frame(width: max(0, g.size.width * f))
            }
            .frame(height: thick ? 7 : 4)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: thick)
            .contentShape(Rectangle())
            .onHover { hover.value = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { box.value = min(max($0.location.x / g.size.width, 0), 1) }
                .onEnded { _ in if let d = box.value { onSeek(d) }; box.value = nil })
        }
        .frame(height: 14)
    }
}

func fmt(_ s: Double) -> String {
    let t = Int(s.rounded(.down))
    return "\(t / 60):" + String(format: "%02d", t % 60)
}

/// NSMenuItem that runs a closure, for menus built in code.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func run() { handler() }
}

/// Mouse handling for a shelf entry in AppKit: SwiftUI's onDrag can only carry one item,
/// this starts a real dragging session with every selected entry.
final class DragSourceView: NSView, NSDraggingSource {
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var dragItems: () -> [(NSPasteboardWriting, NSImage)] = { [] }
    var menuProvider: () -> NSMenu? = { nil }
    private var down: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { onHover(true) }
    override func mouseExited(with e: NSEvent) { onHover(false) }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { down = nil; onDoubleClick() } else { down = e }
    }
    override func mouseUp(with e: NSEvent) {
        if down != nil { onClick() }
        down = nil
    }
    override func mouseDragged(with e: NSEvent) {
        guard let d = down,
              hypot(e.locationInWindow.x - d.locationInWindow.x, e.locationInWindow.y - d.locationInWindow.y) > 4 else { return }
        down = nil
        let start = convert(d.locationInWindow, from: nil)
        let items = dragItems().enumerated().map { i, pair -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: pair.0)
            let o = CGFloat(i) * 5  // fan the stack out a little
            item.setDraggingFrame(NSRect(x: start.x - 20 + o, y: start.y - 20 - o, width: 40, height: 40), contents: pair.1)
            return item
        }
        guard !items.isEmpty else { return }
        Shelf.draggingOut = true
        beginDraggingSession(with: items, event: e, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy out to other apps; dropping back on the notch does nothing.
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }
}

struct DragSource: NSViewRepresentable {
    var onClick: () -> Void
    var onDoubleClick: () -> Void
    var onHover: (Bool) -> Void
    var dragItems: () -> [(NSPasteboardWriting, NSImage)]
    var menu: () -> NSMenu?

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ v: DragSourceView, context: Context) {
        v.onClick = onClick
        v.onDoubleClick = onDoubleClick
        v.onHover = onHover
        v.dragItems = dragItems
        v.menuProvider = menu
    }
}

/// One parked entry. Click selects (drag a selected one to carry them all), double-click opens.
struct ShelfItem: View {
    let entry: ShelfEntry
    @ObservedObject var shelf: Shelf
    @StateObject private var hover = Box<Bool>(false)

    private var selected: Bool { shelf.selection.contains(entry.id) }

    var body: some View {
        VStack(spacing: 3) {
            preview
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            Text(entry.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 2)
        }
        .frame(width: NotchState.itemW, height: 66)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(selected ? 0.18 : hover.value ? 0.1 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
        .overlay(DragSource(
            onClick: { withAnimation(.spring(response: 0.25)) { shelf.toggleSelection(entry) } },
            onDoubleClick: { shelf.open(entry) },
            onHover: { hover.value = $0 },
            dragItems: { shelf.group(for: entry).map { ($0.pasteboardWriter, shelf.dragImage(for: $0)) } },
            menu: menu))
        .overlay(alignment: .topLeading) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, Color.accentColor)
                    .offset(x: -2, y: -2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hover.value {
                Button { withAnimation(.spring(response: 0.3)) { shelf.remove([entry.id]) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .help("Tirar da prateleira")
            }
        }
        .help(entry.kind == .text ? entry.value : entry.title)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    @ViewBuilder private var preview: some View {
        switch entry.kind {
        case .file:
            if let img = shelf.thumbnails[entry.id] { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit) }
        case .link:
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 0.15, green: 0.35, blue: 0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "link").font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                .frame(width: 34, height: 34)
        case .text:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(alignment: .topLeading) {
                    Text(entry.value).font(.system(size: 5.5)).foregroundColor(.black.opacity(0.75)).padding(4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 32, height: 38)
        }
    }

    private func menu() -> NSMenu {
        let group = shelf.group(for: entry)
        let many = group.count > 1
        let m = NSMenu()
        let openTitle = many ? "Abrir \(group.count) itens" : entry.kind == .text ? "Copiar texto" : "Abrir"
        m.addItem(ClosureMenuItem(openTitle) { group.forEach(shelf.open) })
        if entry.kind == .file && !many {
            let url = URL(fileURLWithPath: entry.value)
            m.addItem(ClosureMenuItem("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        m.addItem(ClosureMenuItem(many ? "Copiar \(group.count) itens" : "Copiar") { shelf.copy(group) })
        m.addItem(ClosureMenuItem("AirDrop…") { shelf.airDrop(group) })
        m.addItem(.separator())
        if shelf.selection.count < shelf.items.count {
            m.addItem(ClosureMenuItem("Selecionar tudo") { shelf.selection = Set(shelf.items.map(\.id)) })
        }
        if !shelf.selection.isEmpty {
            m.addItem(ClosureMenuItem("Desmarcar") { shelf.selection.removeAll() })
        }
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(many ? "Tirar \(group.count) da prateleira" : "Tirar da prateleira") {
            withAnimation(.spring(response: 0.3)) { shelf.remove(Set(group.map(\.id))) }
        })
        return m
    }
}

struct NotchView: View {
    @ObservedObject var np: NowPlaying
    @ObservedObject var ui: NotchState
    @ObservedObject var shelf: Shelf
    @ObservedObject var foco: FocoTimer

    var body: some View {
        let hasMedia = np.hasMedia
        let extended = hasMedia || !shelf.isEmpty || foco.session != nil
        let size = ui.size(extended: extended)
        let shape = NotchShape(topR: ui.expanded ? 12 : 6, botR: ui.expanded ? 32 : 10)
        let total = ui.expandedSize.height

        ZStack(alignment: .top) {
            // Expanded: frosted glass tinted by the album art, fading into solid black
            // at the top so it still blends with the physical notch.
            ZStack(alignment: .top) {
                VisualEffect()
                Color.black.opacity(0.28)
                if ui.showMedia, let art = np.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: ui.expandedSize.width, height: total)
                        .blur(radius: 50)
                        .opacity(0.4)
                }
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: ui.notchH / total),
                    .init(color: .black.opacity(0), location: (ui.notchH + 28) / total),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: ui.expandedSize.width, height: total)
            .opacity(ui.expanded ? 1 : 0)

            // Collapsed: pure black, it has to look like part of the hardware.
            Color.black.opacity(ui.expanded ? 0 : 1)

            if ui.expanded {
                expanded.transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)).animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else if extended {
                collapsed.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .onDrop(of: Shelf.dropTypes, isTargeted: Binding(get: { ui.dropTargeted }, set: { ui.dropTargeted = $0 })) { providers in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { shelf.accept(providers) }
        }
        // Glass rim: a soft inner glow plus a hairline that brightens toward the bottom
        // (the top stays black so it still merges with the physical notch).
        .overlay(
            shape.stroke(Color.white.opacity(0.10), lineWidth: 8)
                .blur(radius: 6)
                .clipShape(shape)
                .opacity(ui.expanded ? 1 : 0))
        .overlay(
            shape.stroke(LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.10), location: 0.35),
                .init(color: .white.opacity(0.28), location: 1),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .opacity(ui.expanded ? 1 : 0))
        .scaleEffect(x: ui.bump ? 1.07 : 1, y: ui.bump ? 1.16 : 1, anchor: .top)
        .animation(.spring(response: 0.22, dampingFraction: 0.32), value: ui.bump)
        // Halo in the album's color, then the drop shadow.
        .shadow(color: (ui.showMedia ? np.accent : .white).opacity(ui.expanded ? 0.18 : 0), radius: 24)
        .shadow(color: .black.opacity(ui.expanded ? 0.45 : 0), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.76), value: ui.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: extended)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: ui.expandedSize.height)
        .contextMenu {
            if !shelf.isEmpty {
                Button("Limpar prateleira") { shelf.clear() }
                Divider()
            }
            Toggle("Mostrar ao trocar de música", isOn: Binding(
                get: { NotchState.peekOnTrackChange }, set: { NotchState.peekOnTrackChange = $0 }))
            Toggle("Mostrar em outras telas", isOn: Binding(
                get: { NotchState.showOnAllScreens }, set: { NotchState.showOnAllScreens = $0 }))
            Toggle("Abrir ao iniciar sessão", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
            Divider()
            Button("Sair") { NSApp.terminate(nil) }
        }
    }

    private var collapsed: some View {
        // Left: what's playing, else the Foco phase, else the shelf.
        // Right: the Foco countdown wins over the waveform, which wins over the shelf count.
        HStack {
            if np.hasMedia {
                Artwork(image: np.artwork, size: ui.notchH - 12)
            } else if let s = foco.session {
                Image(systemName: s.isBreak ? "cup.and.saucer.fill" : "scope")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(foco.color)
            } else {
                Image(systemName: "tray.full.fill").font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            if foco.session != nil {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(FocoTimer.clock(foco.remaining(at: ctx.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(foco.color)
                        .fixedSize()
                }
            } else if np.hasMedia {
                Waveform(playing: np.isPlaying, color: np.accent)
            } else {
                Text("\(shelf.items.count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 13)
        .frame(width: ui.notchW + ui.side * 2, height: ui.notchH)
    }

    /// App icons of every source; tap one to show it, tap the shown one to open the app.
    private var sourceSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(np.switchable, id: \.bundleID) { s in
                let selected = s.bundleID == np.bundleID
                Button {
                    selected ? np.openPlayer() : np.select(s.bundleID)
                } label: {
                    Group {
                        if let icon = appIcon(s.bundleID) { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "music.note") }
                    }
                    .frame(width: 18, height: 18)
                    .opacity(selected ? 1 : 0.4)
                    .grayscale(selected ? 0 : 0.8)
                    .overlay(alignment: .bottomTrailing) {
                        if s.playing && !selected {
                            Circle().fill(Color.green).frame(width: 5, height: 5).offset(x: 1, y: 1)
                        }
                    }
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(hover: false))
                .help(selected ? "Abrir \(appName(s.bundleID))" : "Mostrar \(appName(s.bundleID))")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: np.bundleID)
    }

    // MARK: Sections

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.14), .white.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.vertical, (NotchState.separator - 1) / 2)
    }

    private var focusSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let s = foco.session {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 3.5)
                        Circle().trim(from: 0, to: foco.progress(at: ctx.date))
                            .stroke(foco.color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: foco.color.opacity(0.5), radius: 3)
                        Image(systemName: s.isBreak ? "cup.and.saucer.fill" : "scope")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(foco.color)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.isBreak ? "Pausa" : "Foco · ciclo \(s.cycle) de \(s.totalCycles)")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        if !s.intention.isEmpty {
                            Text(s.intention).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(FocoTimer.clock(foco.remaining(at: ctx.date)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.easeOut(duration: 0.3), value: Int(foco.remaining(at: ctx.date)))
                }
            }
        }
        .frame(height: NotchState.focusHeight)
        .contentShape(Rectangle())
        .onTapGesture { foco.open() }
        .help("Abrir o Foco")
    }

    private var mediaSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Artwork(image: np.artwork, size: 56)
                    .shadow(color: np.accent.opacity(0.35), radius: 10, y: 3)
                    .onTapGesture { np.openPlayer() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text(np.artist).font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.6))
                }
                .lineLimit(1)
                .id(np.title + np.artist)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                Spacer(minLength: 8)
                Waveform(playing: np.isPlaying, color: np.accent)
            }
            .animation(.easeInOut(duration: 0.3), value: np.title + np.artist)
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let pos = np.currentPosition(at: ctx.date)
                HStack(spacing: 10) {
                    Text(fmt(pos)).frame(width: 34, alignment: .leading)
                    ProgressBar(fraction: np.duration > 0 ? pos / np.duration : 0) { np.seek(to: $0 * np.duration) }
                    Text("-" + fmt(max(np.duration - pos, 0))).frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.5))
            }
            HStack(spacing: 0) {
                Group {
                    if np.isMusicApp {
                        ControlButton(symbol: np.favorited ? "heart.fill" : "heart", size: 17,
                                      color: np.favorited ? .pink : .white.opacity(0.7)) { np.toggleFavorite() }
                    }
                }
                .frame(width: 96, alignment: .leading)
                Spacer()
                HStack(spacing: 0) {
                    ControlButton(symbol: "backward.fill", size: 19) { np.previous() }
                    ControlButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 26) { np.playPause() }
                        .padding(.horizontal, 10)
                    ControlButton(symbol: "forward.fill", size: 19) { np.next() }
                }
                // The system only lets us control the app it is currently reporting.
                .disabled(!np.canControl)
                .opacity(np.canControl ? 1 : 0.35)
                .help(np.canControl ? "" : "Abra \(appName(np.bundleID ?? "")) para controlar")
                Spacer()
                sourceSwitcher.frame(width: 96, alignment: .trailing)
            }
        }
        .frame(height: NotchState.mediaHeight)
    }

    /// Shown alone while a file is being carried in, so the target is big and obvious.
    private var dropZone: some View {
        let on = ui.dropTargeted
        return HStack(spacing: 10) {
            Image(systemName: on ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 20, weight: .semibold))
                .symbolEffect(.bounce, value: on)
            VStack(alignment: .leading, spacing: 1) {
                Text(on ? "Pode soltar" : "Solte aqui pra guardar").font(.system(size: 13, weight: .semibold))
                if !shelf.isEmpty {
                    Text("\(shelf.items.count) já na prateleira").font(.system(size: 11)).opacity(0.6)
                }
            }
        }
        .foregroundColor(.white.opacity(on ? 1 : 0.65))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(on ? 0.16 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(on ? 0.7 : 0.3), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5])))
        .scaleEffect(on ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }

    /// A wide, short strip: files sit side by side and scroll sideways.
    private var shelfSection: some View {
        Group {
            if ui.dragging {
                dropZone
            } else {
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NotchState.itemGap) {
                            ForEach(shelf.items) { entry in ShelfItem(entry: entry, shelf: shelf) }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shelf.items)
                    }
                    // With a selection the trash removes just that, otherwise everything.
                    ControlButton(symbol: "trash", size: 12, color: .white.opacity(0.45), box: 30) {
                        withAnimation(.spring(response: 0.35)) {
                            shelf.selection.isEmpty ? shelf.clear() : shelf.remove(shelf.selection)
                        }
                    }
                    .help(shelf.selection.isEmpty ? "Limpar prateleira" : "Tirar os \(shelf.selection.count) selecionados")
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            }
        }
        .frame(height: NotchState.shelfHeight)
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            if ui.showFocus { focusSection }
            if ui.showMedia {
                if ui.showFocus { hairline }
                mediaSection
            }
            if ui.showShelf {
                if ui.showFocus || ui.showMedia { hairline }
                shelfSection
            }
            if ui.isEmpty {
                VStack(spacing: 4) {
                    Label("Nada tocando", systemImage: "music.note")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.55))
                    Text("Arraste arquivos, links ou texto até aqui")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
                }
                .frame(height: NotchState.emptyHeight)
            }
        }
        .padding(.top, ui.notchH + 4)
        .padding(.horizontal, NotchState.hPad)
        .padding(.bottom, 10)
        .frame(width: ui.expandedSize.width, height: ui.expandedSize.height, alignment: .top)
    }
}

// MARK: - Window

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var hasNotch: Bool { safeAreaInsets.top > 0 }
}

/// One notch per display: the real notch on the MacBook screen, a pill at the top of the others.
final class NotchController {
    let ui = NotchState()
    let panel: NotchPanel
    let displayID: CGDirectDisplayID
    var peekUntil = Date.distantPast
    private var hoverSince: Date?
    private var leftSince: Date?

    init(screen: NSScreen, np: NowPlaying, shelf: Shelf, foco: FocoTimer) {
        displayID = screen.displayID
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = HostingView(rootView: NotchView(np: np, ui: ui, shelf: shelf, foco: foco))
        layout(screen)
        panel.orderFrontRegardless()
    }

    var screen: NSScreen? { NSScreen.screens.first { $0.displayID == displayID } }

    func layout(_ s: NSScreen) {
        if s.hasNotch, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            ui.notchW = s.frame.width - l.width - r.width
            ui.notchH = s.safeAreaInsets.top
        } else {
            // No notch: a small black pill hanging from the top edge, as tall as the menu bar.
            let bar = s.frame.maxY - s.visibleFrame.maxY
            ui.notchW = 130
            ui.notchH = bar > 0 ? bar : 28
        }
        let w = NotchState.maxExpandedWidth, h = ui.maxExpandedHeight + 40
        panel.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h), display: true)
    }

    func close() { panel.orderOut(nil) }

    /// Quick squash-and-stretch, like the island reacting to something new.
    func bump() {
        ui.bump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { self.ui.bump = false }
    }

    func tick(fileDrag: Bool, np: NowPlaying, shelf: Shelf, foco: FocoTimer) {
        guard let s = screen else { return }

        if fileDrag != ui.dragging { ui.dragging = fileDrag }
        // While something is carried in, the notch shows only the big drop zone.
        let showShelf = !shelf.isEmpty || fileDrag
        let showMedia = np.hasMedia && !fileDrag
        let showFocus = foco.session != nil && !fileDrag
        if ui.showMedia != showMedia { ui.showMedia = showMedia }
        if ui.showShelf != showShelf { ui.showShelf = showShelf }
        if ui.showFocus != showFocus { ui.showFocus = showFocus }

        let sz = ui.size(extended: np.hasMedia || !shelf.isEmpty || foco.session != nil)
        let rect = NSRect(x: s.frame.midX - sz.width / 2, y: s.frame.maxY - sz.height, width: sz.width, height: sz.height)
            .insetBy(dx: -2, dy: -2)
        let mouse = NSEvent.mouseLocation
        let inside = rect.contains(mouse)
        // While carrying something, a big area below the notch already opens it, so it can be
        // dropped well before the top edge (which would trigger Mission Control).
        let dragZone = NSRect(x: s.frame.midX - 320, y: s.frame.maxY - 220, width: 640, height: 220)
        let dragNear = fileDrag && (dragZone.contains(mouse) || rect.contains(mouse))
        let now = Date()

        // Small delays so passing the cursor through the menu bar doesn't pop it open,
        // and a brief exit doesn't snap it shut.
        if inside { hoverSince = hoverSince ?? now; leftSince = nil }
        else { leftSince = leftSince ?? now; hoverSince = nil }
        let hovering = ui.expanded
            ? (inside || now.timeIntervalSince(leftSince ?? now) < 0.25)
            : (inside && now.timeIntervalSince(hoverSince ?? now) >= 0.12)
        let want = hovering || dragNear || (now < peekUntil && (np.hasMedia || foco.session != nil))

        if want != ui.expanded {
            ui.expanded = want
            if want {
                shelf.prune()
                if hovering || dragNear {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
        if inside { peekUntil = .distantPast }
        panel.ignoresMouseEvents = !(inside || dragNear)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let np = NowPlaying()
    let shelf = Shelf()
    let foco = FocoTimer()
    var controllers: [NotchController] = []
    var hoverTimer: Timer?
    private var idleDragCount = NSPasteboard(name: .drag).changeCount

    func applicationDidFinishLaunching(_ n: Notification) {
        rebuild()
        for name in [NSApplication.didChangeScreenParametersNotification, NotchState.screensSettingChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        }
        np.onTrackChange = { [weak self] in
            guard NotchState.peekOnTrackChange else { return }
            self?.peek(3)
        }
        // Study <-> break switches peek open like a notification.
        foco.onPhaseChange = { [weak self] in self?.peek(4) }
        shelf.onAdd = { [weak self] in
            self?.controllers.forEach { $0.bump() }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        np.start()
        foco.start()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Keeps one controller per display that should show the notch.
    func rebuild() {
        let screens = NSScreen.screens.filter { $0.hasNotch || NotchState.showOnAllScreens }
        controllers.removeAll { c in
            guard !screens.contains(where: { $0.displayID == c.displayID }) else { return false }
            c.close()
            return true
        }
        for s in screens where !controllers.contains(where: { $0.displayID == s.displayID }) {
            controllers.append(NotchController(screen: s, np: np, shelf: shelf, foco: foco))
        }
        for c in controllers { if let s = c.screen { c.layout(s) } }
    }

    func peek(_ seconds: TimeInterval) {
        for c in controllers {
            c.peekUntil = Date().addingTimeInterval(seconds)
            c.bump()
        }
    }

    func tick() {
        // Something is being dragged when the button is down and the drag pasteboard changed
        // since the button was last up (no Accessibility permission needed).
        let dragPB = NSPasteboard(name: .drag)
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if !mouseDown {
            idleDragCount = dragPB.changeCount
            Shelf.draggingOut = false
        }
        // Entries dragged *out* of the shelf don't count: the layout must stay put under them.
        let types = dragPB.types ?? []
        let fileDrag = mouseDown && !Shelf.draggingOut && dragPB.changeCount != idleDragCount
            && (types.contains(.fileURL) || types.contains(.URL) || types.contains(.string))
        controllers.forEach { $0.tick(fileDrag: fileDrag, np: np, shelf: shelf, foco: foco) }
    }
}

@main
enum Main {
    static func main() {
        signal(SIGPIPE, SIG_IGN) // writing to a dead helper must not kill the app
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
