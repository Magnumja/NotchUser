import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import QuickLookThumbnailing
import AVFoundation
import Combine
import CoreAudio
import Vision
import Carbon.HIToolbox
import os
import ScreenCaptureKit

// MARK: - Settings & language

final class Settings: ObservableObject {
    static let shared = Settings()
    static let screensChanged = Notification.Name("NotchUser.screensSettingChanged")

    enum Language: String, CaseIterable, Identifiable {
        case system, en, pt, es
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return L("langSystem")
            case .en: return "English"
            case .pt: return "Português"
            case .es: return "Español"
            }
        }
    }

    private let d = UserDefaults.standard
    @Published var language: Language { didSet { d.set(language.rawValue, forKey: "language") } }
    /// Open the notch for a moment when the song changes. Off by default: while listening, it
    /// opening at every song gets in the way (the closed notch still gives a small hop).
    @Published var peekOnTrackChange: Bool { didSet { d.set(peekOnTrackChange, forKey: "openOnTrackChange") } }
    /// Pill at the top of displays without a notch (external monitors).
    @Published var showOnAllScreens: Bool {
        didSet {
            d.set(showOnAllScreens, forKey: "showOnAllScreens")
            NotificationCenter.default.post(name: Self.screensChanged, object: nil)
        }
    }
    @Published var showFoco: Bool { didSet { d.set(showFoco, forKey: "showFoco") } }
    /// Keep the built-in mic as input so Bluetooth headphones never drop to call quality.
    @Published var keepHeadphonesHQ: Bool {
        didSet {
            d.set(keepHeadphonesHQ, forKey: "keepHeadphonesHQ")
            NotificationCenter.default.post(name: Self.audioChanged, object: nil)
        }
    }
    static let audioChanged = Notification.Name("NotchUser.audioSettingChanged")
    // Add-ons: the app ships with music and the shelf; these are off until turned on.
    /// Copy text from the screen (⌘⇧2).
    @Published var ocrEnabled: Bool {
        didSet {
            d.set(ocrEnabled, forKey: "ocrEnabled")
            NotificationCenter.default.post(name: Self.ocrChanged, object: nil)
        }
    }
    /// Camera mirror in the notch.
    @Published var mirrorEnabled: Bool { didSet { d.set(mirrorEnabled, forKey: "mirrorEnabled") } }
    static let ocrChanged = Notification.Name("NotchUser.ocrSettingChanged")

    /// How the notch looks: as plain as the hardware, lifted with depth, or see-through glass.
    enum Style: String, CaseIterable, Identifiable {
        case basic, elevated, glass
        var id: String { rawValue }
        var title: String { L("style." + rawValue) }
    }
    @Published var style: Style { didSet { d.set(style.rawValue, forKey: "style") } }
    /// Asking macOS is a round trip to a system service, too slow to do on every redraw of the
    /// notch (its menu is rebuilt each time), so it's read once and kept here.
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }

    private init() {
        language = Language(rawValue: d.string(forKey: "language") ?? "") ?? .system
        peekOnTrackChange = d.bool(forKey: "openOnTrackChange")
        showOnAllScreens = d.object(forKey: "showOnAllScreens") as? Bool ?? true
        showFoco = d.object(forKey: "showFoco") as? Bool ?? true
        keepHeadphonesHQ = d.bool(forKey: "keepHeadphonesHQ")
        ocrEnabled = d.bool(forKey: "ocrEnabled")
        mirrorEnabled = d.bool(forKey: "mirrorEnabled")
        style = Style(rawValue: d.string(forKey: "style") ?? "") ?? .basic
    }

    /// The language actually used: the chosen one, or the Mac's if it is one we have.
    var resolved: String {
        if language != .system { return language.rawValue }
        let mac = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return Strings.supported.contains(mac) ? mac : "en"
    }
}

/// Localized string for `key`, formatted with `args` (%ld for numbers, %@ for text).
func L(_ key: String, _ args: CVarArg...) -> String {
    let table = Strings.all[key]
    let s = table?[Settings.shared.resolved] ?? table?["en"] ?? key
    return args.isEmpty ? s : String(format: s, arguments: args)
}

enum Strings {
    static let supported = ["en", "pt", "es"]
    static let all: [String: [String: String]] = [
        // Notch
        "nothingPlaying": ["en": "Nothing playing", "pt": "Nada tocando", "es": "No suena nada"],
        "dragHint": ["en": "Drag files, links or text here", "pt": "Arraste arquivos, links ou texto até aqui", "es": "Arrastra archivos, enlaces o texto aquí"],
        "dropHere": ["en": "Drop here to keep it", "pt": "Solte aqui pra guardar", "es": "Suelta aquí para guardarlo"],
        "releaseNow": ["en": "Drop it", "pt": "Pode soltar", "es": "Suéltalo"],
        "alreadyOnShelf": ["en": "%ld already on the shelf", "pt": "%ld já na prateleira", "es": "%ld ya en el estante"],
        "clearShelf": ["en": "Clear shelf", "pt": "Limpar prateleira", "es": "Vaciar estante"],
        "removeSelected": ["en": "Remove the %ld selected", "pt": "Tirar os %ld selecionados", "es": "Quitar los %ld seleccionados"],
        "break": ["en": "Break", "pt": "Pausa", "es": "Descanso"],
        "focusCycle": ["en": "Focus · cycle %ld of %ld", "pt": "Foco · ciclo %ld de %ld", "es": "Enfoque · ciclo %ld de %ld"],
        "openFoco": ["en": "Open Foco", "pt": "Abrir o Foco", "es": "Abrir Foco"],
        "openApp": ["en": "Open %@", "pt": "Abrir %@", "es": "Abrir %@"],
        "showApp": ["en": "Show %@", "pt": "Mostrar %@", "es": "Mostrar %@"],
        "openToControl": ["en": "Open %@ to control it", "pt": "Abra %@ para controlar", "es": "Abre %@ para controlarlo"],
        // Shelf item menu
        "text": ["en": "Text", "pt": "Texto", "es": "Texto"],
        "open": ["en": "Open", "pt": "Abrir", "es": "Abrir"],
        "openN": ["en": "Open %ld items", "pt": "Abrir %ld itens", "es": "Abrir %ld elementos"],
        "copyText": ["en": "Copy text", "pt": "Copiar texto", "es": "Copiar texto"],
        "showInFinder": ["en": "Show in Finder", "pt": "Mostrar no Finder", "es": "Mostrar en Finder"],
        "copy": ["en": "Copy", "pt": "Copiar", "es": "Copiar"],
        "copyN": ["en": "Copy %ld items", "pt": "Copiar %ld itens", "es": "Copiar %ld elementos"],
        "airdrop": ["en": "AirDrop…", "pt": "AirDrop…", "es": "AirDrop…"],
        "selectAll": ["en": "Select all", "pt": "Selecionar tudo", "es": "Seleccionar todo"],
        "deselect": ["en": "Deselect", "pt": "Desmarcar", "es": "Deseleccionar"],
        "removeFromShelf": ["en": "Remove from shelf", "pt": "Tirar da prateleira", "es": "Quitar del estante"],
        "removeN": ["en": "Remove %ld from shelf", "pt": "Tirar %ld da prateleira", "es": "Quitar %ld del estante"],
        // Notch right-click menu
        "settings": ["en": "Settings…", "pt": "Ajustes…", "es": "Ajustes…"],
        "quit": ["en": "Quit NotchUser", "pt": "Sair do NotchUser", "es": "Salir de NotchUser"],
        "peekOnTrack": ["en": "Show when the song changes", "pt": "Mostrar ao trocar de música", "es": "Mostrar al cambiar de canción"],
        "otherScreens": ["en": "Show on other displays", "pt": "Mostrar em outras telas", "es": "Mostrar en otras pantallas"],
        "headphonesHQ": ["en": "Keep Bluetooth headphones in high quality", "pt": "Manter o fone Bluetooth em alta qualidade",
                         "es": "Mantener los auriculares Bluetooth en alta calidad"],
        "headphonesHQHint": ["en": "Uses the MacBook's mic, so headphones never drop to call quality. Turn off to talk through the headphones' mic.",
                             "pt": "Usa o microfone do MacBook, pra o fone não cair pra qualidade de ligação. Desligue se quiser falar pelo microfone do fone.",
                             "es": "Usa el micrófono del MacBook para que los auriculares no bajen a calidad de llamada. Desactívalo para hablar por el micrófono de los auriculares."],
        "showFoco": ["en": "Show the Foco timer", "pt": "Mostrar o timer do Foco", "es": "Mostrar el temporizador de Foco"],
        "launchAtLogin": ["en": "Open at login", "pt": "Abrir ao iniciar sessão", "es": "Abrir al iniciar sesión"],
        // Camera mirror
        "copyTextFromScreen": ["en": "Copy text from screen", "pt": "Copiar texto da tela", "es": "Copiar texto de la pantalla"],
        "textCopied": ["en": "Text copied", "pt": "Texto copiado", "es": "Texto copiado"],
        "noTextFound": ["en": "No text found", "pt": "Nenhum texto encontrado", "es": "No se encontró texto"],
        "noTextHint": ["en": "Try selecting a bigger or sharper area.", "pt": "Tente selecionar uma área maior ou mais nítida.",
                       "es": "Prueba a seleccionar un área más grande o más nítida."],
        "screenPermissionNeeded": ["en": "Allow Screen Recording for NotchUser", "pt": "Permita a Gravação de Tela pro NotchUser",
                                   "es": "Permite la Grabación de pantalla para NotchUser"],
        "screenPermissionHint": ["en": "Then quit and reopen NotchUser.", "pt": "Depois feche e abra o NotchUser de novo.",
                                 "es": "Luego cierra y vuelve a abrir NotchUser."],
        "screenRecording": ["en": "Screen Recording", "pt": "Gravação de Tela", "es": "Grabación de pantalla"],
        "screenRecordingHint": ["en": "Only to copy text from the screen; the image is deleted right after reading.",
                                "pt": "Só pra copiar texto da tela; a imagem é apagada logo depois da leitura.",
                                "es": "Solo para copiar texto de la pantalla; la imagen se borra justo después de leerla."],
        "addons": ["en": "Add-ons", "pt": "Complementos", "es": "Complementos"],
        "addonsSub": ["en": "Optional extras. Turn them on now or anytime in Settings or the notch menu.",
                      "pt": "Extras opcionais. Ligue agora ou quando quiser, nos Ajustes ou no menu do notch.",
                      "es": "Extras opcionales. Actívalos ahora o cuando quieras en Ajustes o en el menú del notch."],
        "addonOCR": ["en": "Copy text from the screen (⌘⇧2)", "pt": "Copiar texto da tela (⌘⇧2)", "es": "Copiar texto de la pantalla (⌘⇧2)"],
        "addonMirror": ["en": "Camera mirror", "pt": "Espelho de câmera", "es": "Espejo de cámara"],
        "cameraMirror": ["en": "Camera mirror", "pt": "Espelho de câmera", "es": "Espejo de cámara"],
        "camera": ["en": "Camera", "pt": "Câmera", "es": "Cámara"],
        "cameraDenied": ["en": "Allow camera access in System Settings to use the mirror.",
                         "pt": "Permita o acesso à câmera nos Ajustes do Sistema para usar o espelho.",
                         "es": "Permite el acceso a la cámara en Ajustes del Sistema para usar el espejo."],
        "noCamera": ["en": "No camera found", "pt": "Nenhuma câmera encontrada", "es": "No se encontró ninguna cámara"],
        "cameraHint": ["en": "The camera is only used by the notch mirror, and only while it's open.",
                       "pt": "A câmera só é usada pelo espelho do notch, e só enquanto ele está aberto.",
                       "es": "La cámara solo la usa el espejo del notch, y solo mientras está abierto."],
        // Settings window
        "welcomeTitle": ["en": "Welcome to NotchUser", "pt": "Bem-vindo ao NotchUser", "es": "Bienvenido a NotchUser"],
        "welcomeSub": ["en": "Your music, a file shelf, text from the screen and a mirror, right in the notch.",
                       "pt": "Sua música, uma prateleira, texto da tela e um espelho, direto no notch.",
                       "es": "Tu música, un estante, texto de la pantalla y un espejo, justo en el notch."],
        "settingsTitle": ["en": "NotchUser Settings", "pt": "Ajustes do NotchUser", "es": "Ajustes de NotchUser"],
        "language": ["en": "Language", "pt": "Idioma", "es": "Idioma"],
        "langSystem": ["en": "System", "pt": "Sistema", "es": "Sistema"],
        "permissions": ["en": "Permissions", "pt": "Permissões", "es": "Permisos"],
        "permHint": ["en": "Needed to show and control Spotify and Apple Music. Music in the browser works without it.",
                     "pt": "Necessário para mostrar e controlar o Spotify e o Apple Music. A música do navegador funciona sem isso.",
                     "es": "Necesario para mostrar y controlar Spotify y Apple Music. La música del navegador funciona sin esto."],
        "allowed": ["en": "Allowed", "pt": "Permitido", "es": "Permitido"],
        "allow": ["en": "Allow", "pt": "Permitir", "es": "Permitir"],
        "openSettings": ["en": "Open Settings", "pt": "Abrir Ajustes", "es": "Abrir Ajustes"],
        "notInstalled": ["en": "Not installed", "pt": "Não instalado", "es": "No instalado"],
        "behavior": ["en": "Behavior", "pt": "Comportamento", "es": "Comportamiento"],
        "general": ["en": "General", "pt": "Geral", "es": "General"],
        "tip": ["en": "Hover the notch to open it. Right-click it for options and Settings.",
                "pt": "Passe o mouse no notch pra abrir. Clique com o botão direito pra ver opções e Ajustes.",
                "es": "Pasa el ratón por el notch para abrirlo. Haz clic derecho para ver opciones y Ajustes."],
        "next": ["en": "Continue", "pt": "Continuar", "es": "Continuar"],
        "back": ["en": "Back", "pt": "Voltar", "es": "Atrás"],
        "featuresTitle": ["en": "What it does", "pt": "O que ele faz", "es": "Qué hace"],
        "featMusic": ["en": "Music in the notch", "pt": "Música no notch", "es": "Música en el notch"],
        "featMusicDesc": ["en": "Hover the notch: cover, progress and controls for Spotify, Apple Music and the browser.",
                          "pt": "Passe o mouse no notch: capa, progresso e controles do Spotify, Apple Music e navegador.",
                          "es": "Pasa el ratón por el notch: portada, progreso y controles de Spotify, Apple Music y el navegador."],
        "featShelf": ["en": "Shelf", "pt": "Prateleira", "es": "Estante"],
        "featShelfDesc": ["en": "Drag files, links or text to the notch and drop them anywhere later.",
                          "pt": "Arraste arquivos, links ou texto até o notch e solte onde quiser depois.",
                          "es": "Arrastra archivos, enlaces o texto al notch y suéltalos donde quieras después."],
        "featOCR": ["en": "Copy text from the screen", "pt": "Copiar texto da tela", "es": "Copiar texto de la pantalla"],
        "featOCRDesc": ["en": "Press ⌘⇧2, select an area and its text goes to the clipboard.",
                        "pt": "Aperte ⌘⇧2, selecione uma área e o texto vai pra área de transferência.",
                        "es": "Pulsa ⌘⇧2, selecciona un área y su texto va al portapapeles."],
        "featMirror": ["en": "Camera mirror", "pt": "Espelho de câmera", "es": "Espejo de cámara"],
        "featMirrorDesc": ["en": "Click the notch to check yourself before a call.",
                           "pt": "Clique no notch pra se conferir antes de uma chamada.",
                           "es": "Haz clic en el notch para verte antes de una llamada."],
        "permissionsSub": ["en": "Give them now and just use the app later. All optional — you can change them anytime in Settings.",
                           "pt": "Dê agora e depois é só usar. Tudo é opcional, e dá pra mudar quando quiser nos Ajustes.",
                           "es": "Dalos ahora y luego solo úsala. Todo es opcional y puedes cambiarlo cuando quieras en Ajustes."],
        "readyTitle": ["en": "You're all set!", "pt": "Tudo pronto!", "es": "¡Todo listo!"],
        "tipHover": ["en": "Hover the notch to open it", "pt": "Passe o mouse no notch pra abrir", "es": "Pasa el ratón por el notch para abrirlo"],
        "tipOCR": ["en": "⌘⇧2 copies text from anywhere on the screen", "pt": "⌘⇧2 copia texto de qualquer lugar da tela",
                   "es": "⌘⇧2 copia texto de cualquier lugar de la pantalla"],
        "tipMenu": ["en": "Right-click the notch for options and Settings", "pt": "Botão direito no notch: opções e Ajustes",
                    "es": "Clic derecho en el notch: opciones y Ajustes"],
        "relaunchNote": ["en": "NotchUser will reopen to turn on Screen Recording.",
                         "pt": "O NotchUser vai reabrir pra ativar a Gravação de Tela.",
                         "es": "NotchUser se volverá a abrir para activar la Grabación de pantalla."],
        "getStarted": ["en": "Get started", "pt": "Começar", "es": "Empezar"],
        "done": ["en": "Done", "pt": "Pronto", "es": "Listo"],
        // Appearance
        "appearance": ["en": "Appearance", "pt": "Aparência", "es": "Apariencia"],
        "style.basic": ["en": "Basic", "pt": "Básico", "es": "Básico"],
        "style.elevated": ["en": "Elevated", "pt": "Elevado", "es": "Elevado"],
        "style.glass": ["en": "Glass", "pt": "Vidro", "es": "Cristal"],
        "styleHint": ["en": "Elevated: depth, a glow under the notch and a cover that tilts toward the mouse. Glass: Liquid Glass with waves that follow the music.",
                      "pt": "Elevado: profundidade, um brilho sob o notch e a capa que inclina na direção do mouse. Vidro: Liquid Glass com ondas que seguem a música.",
                      "es": "Elevado: profundidad, un brillo bajo el notch y una portada que se inclina hacia el ratón. Cristal: Liquid Glass con ondas que siguen la música."],
    ]
}

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
// Looked up once per app: the open notch asks for them on every redraw.
private var appNames: [String: String] = [:]
private var appIcons: [String: NSImage?] = [:]

func appName(_ bundleID: String) -> String {
    if let n = appNames[bundleID] { return n }
    let n = lookUpAppName(bundleID)
    appNames[bundleID] = n
    return n
}
func appIcon(_ bundleID: String) -> NSImage? {
    if let i = appIcons[bundleID] { return i }
    let i = appURL(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    appIcons[bundleID] = i
    return i
}
private func lookUpAppName(_ bundleID: String) -> String {
    appURL(bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
}

final class NowPlaying: ObservableObject {
    @Published private(set) var sources: [String: Source] = [:]
    @Published private(set) var selectedID: String?
    private var pin: (id: String, at: Date)?
    /// Set by play/pause: players (browsers especially) take a moment to report the new state,
    /// and a late report of the old one would flip the button back and forth.
    private var expectPlaying: (id: String, value: Bool, until: Date)?
    /// Browsers often report "nothing" for an instant between two songs; that only counts if it lasts.
    private var pendingClear: DispatchWorkItem?
    private var mrCurrent: String?          // app the system Now Playing reports right now
    private var helperIn: FileHandle?
    private var helperFailures = 0
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
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.5
    }

    func currentPosition(at date: Date) -> Double {
        guard let c = current, c.duration > 0 else { return 0 }
        let p = c.playing ? c.position + date.timeIntervalSince(c.positionDate) : c.position
        return min(max(p, 0), c.duration)
    }

    // MARK: Sources

    private func upsert(_ id: String, title: String, artist: String, duration: Double, position: Double, playing reported: Bool) {
        let now = Date()
        var playing = reported
        if let e = expectPlaying, e.id == id {
            if now < e.until && reported != e.value { playing = e.value } else { expectPlaying = nil }
        }
        var s = sources[id] ?? Source(bundleID: id)
        let newTrack = s.title != title || s.artist != artist
        let hadTrack = !s.title.isEmpty
        // The views advance the position on their own, so the same state reported again is
        // skipped: every write to `sources` redraws the notch. Only a real jump (seek) counts.
        let predicted = s.playing ? s.position + now.timeIntervalSince(s.positionDate) : s.position
        let changed = sources[id] == nil || newTrack || s.playing != playing
            || abs(s.duration - duration) > 0.5 || abs(predicted - position) > 1.5
        guard changed else { return }
        if playing && !s.playing { s.startedAt = now }
        s.title = title
        s.artist = artist
        s.duration = duration
        s.position = position
        s.positionDate = now
        s.playing = playing
        s.lastSeen = now
        if newTrack { s.artRequested = "" }
        sources[id] = s
        if newTrack && s.player == .music { refreshFavorite() }
        if newTrack && hadTrack && id == selectedID { onTrackChange?() }
    }

    private func setArtwork(_ id: String, _ img: NSImage?) {
        guard let s = sources[id] else { return }
        guard let img else {
            // Players report a new song first and its cover a moment later. Clearing right away
            // would flash the placeholder and a white glow in between, so the old cover and color
            // stay a little longer, and only go if no cover arrives for this song.
            let track = s.title + "|" + s.artist
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let now = self.sources[id], now.title + "|" + now.artist == track,
                      now.artwork === s.artwork, now.artwork != nil else { return }
                self.sources[id]?.artwork = nil
            }
            return
        }
        sources[id]?.artwork = img
        sources[id]?.accent = averageColor(img)
    }

    private func remove(_ id: String) {
        if sources[id] != nil { sources[id] = nil }
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
        var next = old
        if let p = pin {
            next = p.id
        } else if let latest = sources.values.filter(\.playing).max(by: { $0.startedAt < $1.startedAt }) {
            next = latest.bundleID
        } else if old == nil || sources[old!] == nil {
            next = mrCurrent.flatMap { sources[$0] != nil ? $0 : nil } ?? switchable.first?.bundleID
        }
        if next != old { selectedID = next }  // assigning the same value would still redraw
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
                guard let self else { return }
                self.helperIn = nil
                self.lineBuffer.removeAll()
                // What it was reporting can't be updated any more.
                if let id = self.mrCurrent, self.sources[id]?.player == nil { self.remove(id) }
                self.mrCurrent = nil
                self.reselect()
                // It can stop (e.g. around sleep); start it again so browsers keep showing up.
                // Waits longer after each failure in a row, up to a minute.
                let delay = min(60, 3 * pow(2, Double(self.helperFailures)))
                self.helperFailures += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if self?.helperIn == nil { _ = self?.startHelper() }
                }
            }
        }
        do { try p.run() } catch { return false }
        helperIn = input.fileHandleForWriting
        return true
    }

    private func consume(_ d: Data) {
        helperFailures = 0
        lineBuffer.append(d)
        while let nl = lineBuffer.firstIndex(of: 10) {
            let line = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            if let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { applyHelper(o) }
        }
    }

    private func applyHelper(_ o: [String: Any]) {
        guard let t = o["title"] as? String else {
            guard pendingClear == nil else { return }
            let clear = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingClear = nil
                if let id = self.mrCurrent, self.sources[id]?.player == nil { self.remove(id) }
                self.mrCurrent = nil
                self.reselect()
            }
            pendingClear = clear
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: clear)
            return
        }
        pendingClear?.cancel()
        pendingClear = nil
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
          set art to ""
          try
            set art to (artwork url of t) as text
          end try
          return (name of t) & "||" & (artist of t) & "||" & (((duration of t) / 1000) as text) & "||" & ((player position) as text) & "||" & s & "||false||" & art
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
        // The app the system reports as Now Playing already comes from the helper.
        let covered = helperIn != nil ? mrCurrent : nil
        queue.async { [self] in
            var results: [(Player, [String]?)] = []
            // Checking first so AppleScript never launches a closed app.
            for p in Player.allCases where p.bundleID != covered
                && !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty {
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
            // While the system reports this app the helper already keeps it up to date.
            if id != mrCurrent {
                upsert(id, title: f[0], artist: f[1], duration: num(f[2]), position: num(f[3]), playing: f[4] == "playing")
            }
            let fav = f[5] == "true"
            if p == .music, sources[id]?.favorited != fav { sources[id]?.favorited = fav }
            let trackKey = f[0] + "|" + f[1]
            // Once per song (artRequested is reset when the song changes).
            if sources[id]?.artRequested != trackKey {
                sources[id]?.artRequested = trackKey
                loadArtwork(p, url: f[6], trackKey: trackKey)
            }
        }
        reselect()
    }

    private func refreshFavorite() {
        queue.async { [self] in
            let fav = run("tell application \"Music\" to get favorited of current track")?.booleanValue ?? false
            DispatchQueue.main.async {
                let id = Player.music.bundleID
                if self.sources[id] != nil, self.sources[id]?.favorited != fav { self.sources[id]?.favorited = fav }
            }
        }
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
        expectPlaying = (id, s.playing, Date().addingTimeInterval(1.5))
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
        // Without Foco installed there is nothing to follow; check rarely in case it gets installed.
        let interval: TimeInterval = appURL(Self.bundleID) != nil ? 2 : 60
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = interval * 0.25
    }

    func refresh() {
        let domain = Self.bundleID as CFString
        CFPreferencesAppSynchronize(domain)  // pick up what Foco wrote since the last read
        let data = CFPreferencesCopyAppValue("foco.activeSession" as CFString, domain) as? Data
        // A session left behind by a Foco that is no longer running is stale.
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
            && Settings.shared.showFoco
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
            return firstLine.flatMap { $0.isEmpty ? nil : $0 } ?? L("text")
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

// MARK: - Copy text from the screen (OCR)

/// Select part of the screen; the text in it goes to the clipboard. Uses the system's own
/// selection crosshair (screencapture -i) and on-device text recognition (Vision). The
/// captured image is deleted right after it's read.
final class ScreenText {
    static let shared = ScreenText()
    private let log = Logger(subsystem: "io.github.notchuser", category: "ocr")
    enum Result { case copied(String), nothing, needsPermission }
    var onResult: ((Result) -> Void)?
    private var busy = false

    func capture() {
        let preflight = CGPreflightScreenCaptureAccess()
        log.notice("capture requested (busy: \(self.busy, privacy: .public), preflight: \(preflight, privacy: .public))")
        guard !busy else { return }
        // The preflight check can say "no" even with access granted on recent macOS, so it
        // doesn't block the capture; it only explains an empty result (see recognize).
        // Ask whenever access is missing: macOS only shows its prompt (and adds the app to the
        // Screen Recording list) when the app isn't listed yet, e.g. after a permission reset.
        if !preflight { CGRequestScreenCaptureAccess() }
        busy = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notchuser-ocr-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", url.path]  // interactive selection, no shutter sound
        p.terminationHandler = { [weak self] _ in self?.recognize(url) }
        do {
            try p.run()
            log.notice("selection started")
        } catch {
            log.error("screencapture failed to start: \(error.localizedDescription, privacy: .public)")
            busy = false
        }
    }

    // Runs on the process's background thread.
    private func recognize(_ url: URL) {
        defer { try? FileManager.default.removeItem(at: url) }
        // No file means the selection was cancelled (Esc): nothing to say.
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            log.notice("selection cancelled")
            DispatchQueue.main.async { self.busy = false }
            return
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US", "es-ES"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let text = Self.readingOrder(request.results ?? [])
        log.notice("recognized \(text.count, privacy: .public) characters from a \(image.width, privacy: .public)x\(image.height, privacy: .public) image")
        DispatchQueue.main.async {
            self.busy = false
            if text.isEmpty {
                // Without access the capture only shows the wallpaper, so no text at all.
                if !CGPreflightScreenCaptureAccess() {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    self.onResult?(.needsPermission)
                } else {
                    self.onResult?(.nothing)
                }
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.onResult?(.copied(text))
            }
        }
    }

    /// Top to bottom, left to right; pieces on the same line are joined with a space.
    private static func readingOrder(_ observations: [VNRecognizedTextObservation]) -> String {
        let items = observations.compactMap { o in o.topCandidates(1).first.map { (box: o.boundingBox, text: $0.string) } }
            .sorted { $0.box.midY > $1.box.midY }
        var lines: [[(box: CGRect, text: String)]] = []
        for item in items {
            if let last = lines.last?.first, abs(last.box.midY - item.box.midY) < min(last.box.height, item.box.height) / 2 {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

/// A system-wide keyboard shortcut (Carbon hot keys need no Accessibility permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4E555352), id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        // Fails (e.g. eventHotKeyExistsErr) when another app already owns the same keys.
        Logger(subsystem: "io.github.notchuser", category: "ocr")
            .notice("hot key registered: \(status == noErr, privacy: .public) (status \(status, privacy: .public))")
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

// MARK: - Headphone quality

/// Bluetooth headphones drop to call quality (mono, muffled) whenever their own microphone is
/// in use. With the option on, whenever macOS picks a Bluetooth mic as input (it does so when
/// headphones connect), the built-in mic is put back.
final class AudioGuard {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listening = false
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.enforce() }

    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func update() {
        Settings.shared.keepHeadphonesHQ ? start() : stop()
    }

    private func start() {
        if !listening {
            for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
                var a = address(selector)
                AudioObjectAddPropertyListenerBlock(system, &a, .main, listener)
            }
            listening = true
        }
        enforce()
    }

    private func stop() {
        guard listening else { return }
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var a = address(selector)
            AudioObjectRemovePropertyListenerBlock(system, &a, .main, listener)
        }
        listening = false
    }

    private func enforce() {
        guard Settings.shared.keepHeadphonesHQ else { return }
        var input = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = address(kAudioHardwarePropertyDefaultInputDevice)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &input) == noErr,
              isBluetooth(input), let builtIn = builtInMic(), builtIn != input else { return }
        var newInput = builtIn
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &newInput)
    }

    private func transport(_ device: AudioObjectID) -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = address(kAudioDevicePropertyTransportType)
        AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value)
        return value
    }

    private func isBluetooth(_ device: AudioObjectID) -> Bool {
        [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport(device))
    }

    private func hasInput(_ device: AudioObjectID) -> Bool {
        var size: UInt32 = 0
        var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        return AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr && size > 0
    }

    private func builtInMic() -> AudioObjectID? {
        var size: UInt32 = 0
        var a = address(kAudioHardwarePropertyDevices)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &devices) == noErr else { return nil }
        return devices.first { transport($0) == kAudioDeviceTransportTypeBuiltIn && hasInput($0) }
    }
}

// MARK: - Camera mirror

/// The built-in camera, shown mirrored in the notch to check yourself before a call.
/// It only runs while the mirror is open; closing the notch turns it (and its light) off.
final class CameraMirror: ObservableObject {
    enum State { case off, starting, running, denied, unavailable }
    @Published private(set) var state: State = .off
    /// The macOS permission prompt is up; the notch stays open meanwhile.
    @Published private(set) var asking = false
    /// Called when the user has just granted access (to show the mirror right away).
    var onGranted: (() -> Void)?
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notch.camera")
    private var configured = false  // touched on `queue` only
    private let log = Logger(subsystem: "io.github.notchuser", category: "camera")
    lazy var previewView = CameraPreviewView(session: session)
    private var wanted = false

    func start() {
        log.notice("start (state \(String(describing: self.state), privacy: .public))")
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            state = .starting
            asking = true
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    self.asking = false
                    if !ok {
                        self.state = .denied
                    } else {
                        if self.wanted { self.run() } else { self.state = .off }
                        self.onGranted?()
                    }
                }
            }
        default:
            state = .denied
        }
    }

    private func run() {
        state = .starting
        queue.async { [self] in
            if !configured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                session.beginConfiguration()
                if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                session.addInput(input)
                session.commitConfiguration()
                configured = true
            }
            session.startRunning()
            log.notice("session running: \(self.session.isRunning, privacy: .public)")
            DispatchQueue.main.async {
                // Closed while the camera was warming up: turn it right back off.
                if self.wanted {
                    self.state = .running
                } else {
                    self.queue.async { self.session.stopRunning() }
                }
            }
        }
    }

    func stop() {
        log.notice("stop")
        wanted = false
        if state == .running || state == .starting { state = .off }
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Live camera view. The preview layer *is* the view's layer, so it always has the view's
/// size (a sublayer stayed at zero size, since SwiftUI resizes views without a layout pass).
final class CameraPreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer
    private var startObserver: NSObjectProtocol?

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = 18
        preview.cornerCurve = .continuous
        preview.masksToBounds = true
        layer = preview
        wantsLayer = true
        applyMirror()
        // The video connection only exists once the camera is wired in, so mirror again then.
        startObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
        ) { [weak self] _ in self?.applyMirror() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyMirror()
    }

    /// Flip it like a real mirror.
    private func applyMirror() {
        guard let c = preview.connection, c.isVideoMirroringSupported else { return }
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = true
    }
}

/// Hands SwiftUI the camera's single preview view. A fresh preview layer per opening could be
/// created while the previous one was still attached to the session, leaving it blank.
struct CameraPreview: NSViewRepresentable {
    let camera: CameraMirror
    func makeNSView(context: Context) -> CameraPreviewView { camera.previewView }
    func updateNSView(_ view: CameraPreviewView, context: Context) {}
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
    @Published var hovering = false      // the mouse is on the closed notch (it lifts, in the richer styles)
    @Published var mirrorOn = false      // the camera mirror replaces the usual sections
    /// A short message (e.g. "Text copied") shown on its own for a moment.
    struct Toast: Equatable {
        var icon: String
        var title: String
        var detail: String?
        var ok: Bool
    }
    @Published var toast: Toast?

    var notchW: CGFloat = 185
    var notchH: CGFloat = 32
    @Published var timerShown = false
    /// Width of each piece sticking out of the collapsed notch; the Foco countdown needs more room.
    var side: CGFloat { notchH + (timerShown ? 30 : 12) }
    // Expanded layout: sections stacked (Foco, music, shelf), split by hairlines.
    static let width: CGFloat = 470
    static let hPad: CGFloat = 24
    static let focusHeight: CGFloat = 44
    static let mediaHeight: CGFloat = 124
    static let shelfHeight: CGFloat = 78
    static let emptyHeight: CGFloat = 84
    static let mirrorHeight: CGFloat = 236
    static let toastHeight: CGFloat = 52
    static let separator: CGFloat = 13  // hairline plus the space around it
    static let itemW: CGFloat = 64
    static let itemGap: CGFloat = 4
    private let chrome: CGFloat = 14     // space below the notch plus bottom padding

    var isEmpty: Bool { !showFocus && !showMedia && !showShelf }

    var expandedSize: CGSize {
        if mirrorOn { return CGSize(width: Self.width, height: notchH + chrome + Self.mirrorHeight) }
        if toast != nil { return CGSize(width: Self.width, height: notchH + chrome + Self.toastHeight) }
        var sections: [CGFloat] = []
        if showFocus { sections.append(Self.focusHeight) }
        if showMedia { sections.append(Self.mediaHeight) }
        if showShelf { sections.append(Self.shelfHeight) }
        if sections.isEmpty { sections.append(Self.emptyHeight) }
        let h = notchH + chrome + sections.reduce(0, +) + Self.separator * CGFloat(sections.count - 1)
        return CGSize(width: Self.width, height: h)
    }
    var maxExpandedHeight: CGFloat {
        notchH + chrome + max(Self.mirrorHeight, Self.focusHeight + Self.mediaHeight + Self.shelfHeight + Self.separator * 2)
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

// MARK: Music animations
//
// The bars and waves run in Core Animation: the app hands the motion to macOS once, and the
// window server plays it. Drawn in SwiftUI they made the whole notch redraw 30 times a second.

/// A layer-hosting view for the animations below.
class AnimatedLayerView: NSView {
    let root = CALayer()
    private var laidOut = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        setScale(root, window?.backingScaleFactor ?? 2)
    }
    private func setScale(_ l: CALayer, _ scale: CGFloat) {
        l.contentsScale = scale
        l.sublayers?.forEach { setScale($0, scale) }
        if let m = l.mask { setScale(m, scale) }
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOut, bounds.width > 0, bounds.height > 0 else { return }
        laidOut = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuild()
        CATransaction.commit()
        setScale(root, window?.backingScaleFactor ?? 2)
    }

    /// Lays out the layers and starts the animations for the current size.
    func rebuild() {}

    /// Freezes every animation where it is, or lets it continue from there.
    func setRunning(_ on: Bool) {
        if on, root.speed == 0 {
            let pausedAt = root.timeOffset
            root.speed = 1
            root.timeOffset = 0
            root.beginTime = 0
            root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        } else if !on, root.speed != 0 {
            root.timeOffset = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
        }
    }

    /// Samples `f` over one loop, so the animation repeats without a seam.
    static func loop(_ keyPath: String, duration: Double, steps: Int, _ f: (Double) -> Any) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = (0...steps).map { f(Double($0) / Double(steps) * duration) }
        a.duration = duration
        a.repeatCount = .infinity
        a.calculationMode = .linear
        return a
    }
}

/// Four bars dancing to the music.
final class BarsLayerView: AnimatedLayerView {
    private let bars = (0..<4).map { _ in CALayer() }
    var playing = false { didSet { if playing != oldValue { animate() } } }
    var color = NSColor.white.cgColor {
        didSet { bars.forEach { $0.backgroundColor = color; $0.shadowColor = color } }
    }
    var glow = false { didSet { bars.forEach { $0.shadowOpacity = glow ? 0.7 : 0 } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for b in bars {
            b.cornerRadius = 1.25
            b.backgroundColor = color
            b.shadowRadius = 3
            b.shadowOffset = .zero
            root.addSublayer(b)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func rebuild() {
        let w: CGFloat = 2.5, gap: CGFloat = 2
        let x0 = (bounds.width - (w * 4 + gap * 3)) / 2
        for (i, b) in bars.enumerated() {
            b.frame = CGRect(x: x0 + CGFloat(i) * (w + gap), y: (bounds.height - 16) / 2, width: w, height: 16)
        }
        animate()
    }

    private func animate() {
        for (i, b) in bars.enumerated() {
            if playing {
                // |sin| at a different speed per bar, over whole cycles so it loops seamlessly.
                let speed = 3.1 + Double(i) * 1.7
                let cycles = max(1, (1.6 * speed / .pi).rounded())
                let duration = cycles * .pi / speed
                b.add(Self.loop("transform.scale.y", duration: duration, steps: Int(cycles) * 10) { t in
                    0.35 + 0.65 * abs(sin(t * speed + Double(i)))
                }, forKey: "dance")
                b.transform = CATransform3DIdentity
            } else {
                b.removeAnimation(forKey: "dance")
                b.transform = CATransform3DMakeScale(1, 0.2, 1)  // settles with the implicit fade
            }
        }
    }
}

/// For the Glass style: a small wave flowing through the pill, Siri-like.
final class WaveLayerView: AnimatedLayerView {
    private let lines = [CAShapeLayer(), CAShapeLayer()]
    var playing = false { didSet { if playing != oldValue { animate() } } }
    var color = NSColor.white.cgColor {
        didSet {
            lines[0].strokeColor = color
            lines[1].strokeColor = color.copy(alpha: 0.45)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (i, l) in lines.enumerated() {
            l.fillColor = nil
            l.lineCap = .round
            l.lineWidth = i == 0 ? 1.8 : 1.2
            root.addSublayer(l)
        }
        color = NSColor.white.cgColor
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func path(phase: Double, frequency: Double) -> CGPath {
        let p = CGMutablePath()
        let w = bounds.width, mid = bounds.height / 2
        for x in stride(from: CGFloat(0), through: w, by: 1) {
            let u = Double(x / w)
            let y = mid + CGFloat(sin(u * 2 * .pi * frequency - phase) * sin(.pi * u)) * mid * 0.85  // ends meet in the middle
            x == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }

    override func rebuild() {
        lines.forEach { $0.frame = bounds }
        animate()
    }

    private func animate() {
        guard bounds.width > 0 else { return }
        for (i, l) in lines.enumerated() {
            let k = Double(i), frequency = 1.6 + k * 0.5
            if playing {
                let speed = 5 + k * 2
                l.add(Self.loop("path", duration: 2 * .pi / speed, steps: 16) { t in self.path(phase: t * speed, frequency: frequency) },
                      forKey: "flow")
                // Louder and quieter moments, so it feels alive rather than a loop.
                let pulse = 1.3 + k * 0.7
                l.add(Self.loop("transform.scale.y", duration: .pi / pulse, steps: 12) { t in 0.55 + 0.45 * abs(sin(t * pulse + k)) },
                      forKey: "energy")
            } else {
                l.removeAllAnimations()
                l.path = path(phase: 0, frequency: frequency)
                l.transform = CATransform3DMakeScale(1, 0.14, 1)
            }
        }
    }
}

/// For the Glass style: soft waves in the album's color drifting along the bottom of the panel.
final class FlowLayerView: AnimatedLayerView {
    private let fills = (0..<3).map { _ in CAGradientLayer() }
    private let shapes = (0..<3).map { _ in CAShapeLayer() }
    var playing = true {
        didSet {
            setRunning(playing)
            root.opacity = playing ? 1 : 0.4
        }
    }
    var color = NSColor.white.cgColor {
        didSet {
            for (i, f) in fills.enumerated() {
                f.colors = [color.copy(alpha: 0.32 - 0.07 * CGFloat(i))!, color.copy(alpha: 0)!]
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (f, m) in zip(fills, shapes) {
            m.fillColor = NSColor.black.cgColor
            f.mask = m
            root.addSublayer(f)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func rebuild() {
        let w = bounds.width, h = bounds.height
        for (i, (f, m)) in zip(fills, shapes).enumerated() {
            let k = CGFloat(i)
            let amp = h * (0.13 + 0.05 * k)
            let crest = h * (0.42 + 0.14 * k)  // from the top
            let base = h - crest                // layers count from the bottom
            let length = w / (1 + 0.4 * k)
            f.frame = bounds
            f.startPoint = CGPoint(x: 0.5, y: min(1, (base + amp) / h))
            f.endPoint = CGPoint(x: 0.5, y: 0)

            // One wave a wavelength wider than the view, slid by exactly one wavelength: a seamless loop.
            let p = CGMutablePath()
            let width = w + length
            p.move(to: CGPoint(x: 0, y: -h * 3))
            for x in stride(from: CGFloat(0), through: width, by: 4) {
                p.addLine(to: CGPoint(x: x, y: amp * CGFloat(sin(Double(x / length) * 2 * .pi))))
            }
            p.addLine(to: CGPoint(x: width, y: -h * 3))
            p.closeSubpath()
            m.path = p
            m.bounds = CGRect(x: 0, y: -h * 3, width: width, height: h * 3)
            m.anchorPoint = CGPoint(x: 0.5, y: 1)  // the wave's middle line, so breathing keeps it in place
            let direction: CGFloat = i % 2 == 0 ? 1 : -1
            let from = width / 2 - (direction > 0 ? 0 : length)
            m.position = CGPoint(x: from, y: base)

            let speed = 0.9 + 0.45 * Double(i)
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = from
            slide.toValue = from - direction * length
            slide.duration = 2 * .pi / speed
            slide.repeatCount = .infinity
            m.add(slide, forKey: "slide")

            let breathe = CABasicAnimation(keyPath: "transform.scale.y")
            breathe.fromValue = 0.4
            breathe.toValue = 1.0
            breathe.duration = .pi / (0.8 + 0.3 * Double(i))
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            m.add(breathe, forKey: "breathe")
        }
    }
}

struct Waveform: View {
    var playing: Bool
    var color: Color
    var glow = false
    var body: some View { BarsRep(playing: playing, color: color, glow: glow).frame(width: 18, height: 16) }

    private struct BarsRep: NSViewRepresentable {
        var playing: Bool, color: Color, glow: Bool
        func makeNSView(context: Context) -> BarsLayerView { BarsLayerView(frame: .zero) }
        func updateNSView(_ v: BarsLayerView, context: Context) {
            v.color = NSColor(color).cgColor
            v.glow = glow
            v.playing = playing
        }
    }
}

struct MiniWave: View {
    var playing: Bool
    var color: Color
    var body: some View { WaveRep(playing: playing, color: color).frame(width: 26, height: 16) }

    private struct WaveRep: NSViewRepresentable {
        var playing: Bool, color: Color
        func makeNSView(context: Context) -> WaveLayerView { WaveLayerView(frame: .zero) }
        func updateNSView(_ v: WaveLayerView, context: Context) {
            v.color = NSColor(color).cgColor
            v.playing = playing
        }
    }
}

struct FlowingWaves: View {
    var playing: Bool
    var color: Color
    var body: some View { FlowRep(playing: playing, color: color).allowsHitTesting(false) }

    private struct FlowRep: NSViewRepresentable {
        var playing: Bool, color: Color
        func makeNSView(context: Context) -> FlowLayerView { FlowLayerView(frame: .zero) }
        func updateNSView(_ v: FlowLayerView, context: Context) {
            v.color = NSColor(color).cgColor
            v.playing = playing
        }
    }
}


/// A surface inside the panel (the shelf, the playback controls): a piece of Liquid Glass in the
/// Glass style, a soft lit pod when Elevated, the plain look otherwise (`fallback` = fill opacity).
struct Surface<S: Shape>: ViewModifier {
    var style: Settings.Style
    var shape: S
    var interactive = false
    var fallback: Double
    var elevated: Double

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(macOS 26.0, *) {
                content.glassEffect(Glass.clear.interactive(interactive), in: shape)
            } else {
                content.background(shape.fill(Color.white.opacity(0.08)))
            }
        case .elevated:
            content
                .background(shape.fill(LinearGradient(colors: [.white.opacity(elevated * 1.6), .white.opacity(elevated * 0.6)],
                                                      startPoint: .top, endPoint: .bottom)))
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.03)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        case .basic:
            content.background(shape.fill(Color.white.opacity(fallback)))
        }
    }
}

/// One line of text that slides sideways while hovered when it doesn't fit, instead of staying cut.
struct Marquee: View {
    var text: String
    var font: Font
    var color: Color
    var height: CGFloat
    @StateObject private var hover = Box<Bool>(false)
    @StateObject private var textWidth = Box<CGFloat>(0)

    var body: some View {
        GeometryReader { g in
            let overflow = max(0, textWidth.value - g.size.width)
            let rolling = hover.value && overflow > 0
            ZStack(alignment: .leading) {
                // Measures the full text once; never shown.
                Text(text).font(font).fixedSize().hidden()
                    .background(GeometryReader { t in Color.clear.preference(key: WidthKey.self, value: t.size.width) })
                if rolling {
                    Text(text).font(font).foregroundColor(color).fixedSize()
                        .modifier(Roll(distance: overflow))
                } else {
                    Text(text).font(font).foregroundColor(color).lineLimit(1).truncationMode(.tail)
                        .frame(width: g.size.width, alignment: .leading)
                }
            }
            .frame(width: g.size.width, height: height, alignment: .leading)
            .clipped()
            .onPreferenceChange(WidthKey.self) { textWidth.value = $0 }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onHover { hover.value = $0 }
    }

    private struct WidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    /// Slides to the end and back, at a calm reading speed, while it's on screen.
    private struct Roll: ViewModifier {
        var distance: CGFloat
        @StateObject private var moved = Box<Bool>(false)
        func body(content: Content) -> some View {
            content
                .offset(x: moved.value ? -distance : 0)
                .onAppear {
                    withAnimation(.easeInOut(duration: Double(distance) / 28 + 0.6).delay(0.5).repeatForever(autoreverses: true)) {
                        moved.value = true
                    }
                }
        }
    }
}

/// The panel's backdrop: Apple's Liquid Glass in the Glass style (macOS 26+), frosted otherwise.
struct PanelMaterial: View {
    var glass: Bool
    var tint: Color
    var body: some View {
        if glass { liquid } else { VisualEffect() }
    }
    @ViewBuilder private var liquid: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear.tint(tint.opacity(0.22)), in: NotchShape(topR: 12, botR: 32))
        } else {
            VisualEffect()
        }
    }
}

/// The cover leans toward the mouse, with a glint that follows it (Elevated and Glass).
struct Tilt: ViewModifier {
    var enabled: Bool
    var size: CGFloat
    @StateObject private var at = Box<CGPoint?>(nil)  // -1...1 from the center

    func body(content: Content) -> some View {
        let v = enabled ? at.value : nil
        content
            .overlay {
                if let v {
                    RadialGradient(colors: [.white.opacity(0.32), .clear],
                                   center: UnitPoint(x: 0.5 + v.x / 2, y: 0.5 + v.y / 2), startRadius: 0, endRadius: size * 0.75)
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.degrees(Double(v?.y ?? 0) * -16), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(Double(v?.x ?? 0) * 16), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(v == nil ? 1 : 1.07)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: v)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): at.value = CGPoint(x: min(max(p.x / size * 2 - 1, -1), 1), y: min(max(p.y / size * 2 - 1, -1), 1))
                case .ended: at.value = nil
                }
            }
    }
}

/// The open panel "materializes": out of a blur, slightly smaller and higher.
struct Materialize: ViewModifier {
    var amount: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: 10 * amount)
            .scaleEffect(1 - 0.08 * amount, anchor: .top)
            .offset(y: -8 * amount)
            .opacity(1 - amount)
    }
}

/// Three small notch previews to choose the style from.
struct StylePicker: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(Settings.Style.allCases) { style in
                    let on = settings.style == style
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { settings.style = style }
                    } label: {
                        VStack(spacing: 7) {
                            StylePreview(style: style).frame(height: 56)
                            Text(style.title).font(.system(size: 11.5, weight: on ? .semibold : .medium))
                                .foregroundColor(.white.opacity(on ? 1 : 0.7))
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(on ? 0.12 : 0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(on ? 0.95 : 0), lineWidth: 1.5))
                        .scaleEffect(on ? 1 : 0.97)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("styleHint"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StylePreview: View {
    var style: Settings.Style
    var body: some View {
        let shape = NotchShape(topR: 4, botR: 13)
        ZStack(alignment: .top) {
            // A colorful "wallpaper", so the glass has something to show through.
            LinearGradient(colors: [Color(red: 0.32, green: 0.24, blue: 0.62), Color(red: 0.93, green: 0.45, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.98, green: 0.78, blue: 0.35)).frame(width: 34).offset(x: 24, y: 22).blur(radius: 2)
            ZStack(alignment: .bottom) {
                switch style {
                case .basic:
                    shape.fill(Color.black.opacity(0.94))
                case .elevated:
                    shape.fill(Color.black.opacity(0.9))
                        .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.55), radius: 5, y: 4)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                case .glass:
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.1)], startPoint: .top, endPoint: .bottom)))
                        .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                    MiniWave(playing: true, color: .white).scaleEffect(0.8).padding(.bottom, 4)
                }
            }
            .frame(width: 74, height: 34)
            .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

/// Tells the notch when its menu opens and closes.
final class MenuWatcher: NSObject, NSMenuDelegate {
    var onChange: (Bool) -> Void = { _ in }
    func menuWillOpen(_ menu: NSMenu) { onChange(true) }
    func menuDidClose(_ menu: NSMenu) { onChange(false) }
}

/// The notch's right-click menu: native, with icons and sections, built when it opens.
enum NotchMenu {
    static func build(for c: NotchController, shelf: Shelf) -> NSMenu {
        let settings = Settings.shared
        let m = NSMenu()
        m.autoenablesItems = false
        c.menuWatcher.onChange = { [weak c] open in
            c?.menuOpen = open
            if !open { c?.leaveDelayFromNow() }
        }
        m.delegate = c.menuWatcher

        if settings.ocrEnabled {
            m.addItem(item(L("copyTextFromScreen"), "text.viewfinder", key: "2", modifiers: [.command, .shift]) {
                // Let the menu close before the selection crosshair appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ScreenText.shared.capture() }
            })
        }
        if settings.mirrorEnabled {
            m.addItem(item(L("cameraMirror"), "camera") { [weak c] in
                c?.mirrorHoldUntil = Date().addingTimeInterval(2)
                c?.ui.mirrorOn = true
            })
        }
        if settings.ocrEnabled || settings.mirrorEnabled { m.addItem(.separator()) }

        m.addItem(.sectionHeader(title: L("appearance")))
        let icons: [Settings.Style: String] = [.basic: "capsule.fill", .elevated: "square.stack.3d.up.fill", .glass: "drop.fill"]
        for style in Settings.Style.allCases {
            m.addItem(item(style.title, icons[style], on: settings.style == style) { settings.style = style })
        }
        m.addItem(.separator())

        m.addItem(.sectionHeader(title: L("behavior")))
        m.addItem(item(L("peekOnTrack"), "music.note", on: settings.peekOnTrackChange) { settings.peekOnTrackChange.toggle() })
        m.addItem(item(L("otherScreens"), "display.2", on: settings.showOnAllScreens) { settings.showOnAllScreens.toggle() })
        m.addItem(item(L("launchAtLogin"), "sunrise", on: settings.launchAtLogin) { settings.launchAtLogin.toggle() })
        let addons = item(L("addons"), "puzzlepiece.extension") {}
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(item(L("addonOCR"), "text.viewfinder", on: settings.ocrEnabled) { settings.ocrEnabled.toggle() })
        sub.addItem(item(L("addonMirror"), "camera", on: settings.mirrorEnabled) { settings.mirrorEnabled.toggle() })
        sub.addItem(item(L("headphonesHQ"), "headphones", on: settings.keepHeadphonesHQ) { settings.keepHeadphonesHQ.toggle() })
        addons.submenu = sub
        m.addItem(addons)
        m.addItem(.separator())

        if !shelf.isEmpty {
            m.addItem(item(L("clearShelf"), "trash") { withAnimation(.spring(response: 0.35)) { shelf.clear() } })
        }
        m.addItem(item(L("settings"), "gearshape", key: ",") { SettingsWindow.shared.show(welcome: false) })
        m.addItem(item(L("quit"), "power", key: "q") { NSApp.terminate(nil) })
        return m
    }

    private static func item(_ title: String, _ symbol: String?, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                             on: Bool? = nil, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = ClosureMenuItem(title, action)
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        if let on { i.state = on ? .on : .off }
        i.keyEquivalent = key
        if !key.isEmpty { i.keyEquivalentModifierMask = modifiers }
        return i
    }
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
                .help(L("removeFromShelf"))
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
        let openTitle = many ? L("openN", group.count) : entry.kind == .text ? L("copyText") : L("open")
        m.addItem(ClosureMenuItem(openTitle) { group.forEach(shelf.open) })
        if entry.kind == .file && !many {
            let url = URL(fileURLWithPath: entry.value)
            m.addItem(ClosureMenuItem(L("showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        m.addItem(ClosureMenuItem(many ? L("copyN", group.count) : L("copy")) { shelf.copy(group) })
        m.addItem(ClosureMenuItem(L("airdrop")) { shelf.airDrop(group) })
        m.addItem(.separator())
        if shelf.selection.count < shelf.items.count {
            m.addItem(ClosureMenuItem(L("selectAll")) { shelf.selection = Set(shelf.items.map(\.id)) })
        }
        if !shelf.selection.isEmpty {
            m.addItem(ClosureMenuItem(L("deselect")) { shelf.selection.removeAll() })
        }
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(many ? L("removeN", group.count) : L("removeFromShelf")) {
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
    @ObservedObject var camera: CameraMirror
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let hasMedia = np.hasMedia
        let extended = hasMedia || !shelf.isEmpty || foco.session != nil
        let size = ui.size(extended: extended)
        let shape = NotchShape(topR: ui.expanded ? 12 : 6, botR: ui.expanded ? 32 : 10)
        let total = ui.expandedSize.height
        let style = settings.style
        let glass = style == .glass
        let lifted = style != .basic
        let lift = lifted && ui.hovering && !ui.expanded

        ZStack(alignment: .top) {
            // Expanded: frosted glass tinted by the album art, fading into solid black
            // at the top so it still blends with the physical notch.
            if ui.expanded {
            ZStack(alignment: .top) {
                PanelMaterial(glass: glass, tint: ui.showMedia ? np.accent : .white)
                Color.black.opacity(glass ? 0.22 : 0.28)
                if ui.showMedia, let art = np.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: ui.expandedSize.width, height: total)
                        .blur(radius: 50)
                        .saturation(glass ? 1.5 : 1)
                        .opacity(glass ? 0.55 : 0.4)
                }
                if style == .elevated {
                    // Light falling on a raised surface: a little brighter at the top.
                    LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
                }
                if glass {
                    // A sheen from above, like light on a pane of glass.
                    LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
                    if ui.showMedia && !ui.mirrorOn {
                        FlowingWaves(playing: np.isPlaying, color: np.accent)
                            .frame(height: 100)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: ui.notchH / total),
                    .init(color: .black.opacity(0), location: (ui.notchH + 28) / total),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: ui.expandedSize.width, height: total)
            .transition(.opacity)
            }

            // Collapsed: pure black, it has to look like part of the hardware.
            Color.black.opacity(ui.expanded ? 0 : 1)

            if ui.expanded {
                expanded.transition(.asymmetric(
                    insertion: lifted
                        ? AnyTransition.modifier(active: Materialize(amount: 1), identity: Materialize(amount: 0))
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.04))
                        : AnyTransition.opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else if extended {
                collapsed.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        // Elevated and Glass: while playing, a soft light in the album's color under the closed notch.
        .background(alignment: .bottom) {
            Capsule()
                .fill(np.accent)
                .frame(width: size.width * 0.55, height: 3)
                .blur(radius: 4)
                .offset(y: 3)
                .opacity(lifted && np.isPlaying && !ui.expanded ? 0.75 : 0)
                .animation(.easeInOut(duration: 0.4), value: np.isPlaying)
                .allowsHitTesting(false)
        }

        .onDrop(of: Shelf.dropTypes, isTargeted: Binding(get: { ui.dropTargeted }, set: { ui.dropTargeted = $0 })) { providers in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { shelf.accept(providers) }
        }
        // Glass rim: a soft inner glow plus a hairline that brightens toward the bottom
        // (the top stays black so it still merges with the physical notch).
        .overlay(
            shape.stroke(Color.white.opacity(glass ? 0.16 : 0.10), lineWidth: 8)
                .blur(radius: ui.expanded ? 6 : 0)
                .clipShape(shape)
                .opacity(ui.expanded ? 1 : 0))
        .overlay(
            shape.stroke(LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(glass ? 0.16 : 0.10), location: 0.35),
                .init(color: .white.opacity(glass ? 0.45 : 0.28), location: 1),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .opacity(ui.expanded ? 1 : 0))
        .scaleEffect(x: ui.bump ? 1.07 : 1, y: ui.bump ? 1.16 : 1, anchor: .top)
        .animation(.spring(response: 0.22, dampingFraction: 0.32), value: ui.bump)
        // Elevated and Glass: the closed notch rises a little under the mouse before it opens.
        .scaleEffect(x: lift ? 1.04 : 1, y: lift ? 1.12 : 1, anchor: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: lift)
        // Halo in the album's color, then the drop shadow (two layers when elevated: close and ambient).
        .shadow(color: (ui.showMedia ? np.accent : .white).opacity(ui.expanded ? (glass ? 0.3 : lifted ? 0.22 : 0.18) : 0),
                radius: ui.expanded ? (lifted ? 32 : 24) : 0)
        .shadow(color: .black.opacity(ui.expanded || lift ? 0.45 : 0),
                radius: ui.expanded ? (lifted ? 10 : 18) : lift ? 6 : 0, y: ui.expanded ? (lifted ? 5 : 8) : lift ? 3 : 0)
        .shadow(color: .black.opacity(lifted && ui.expanded ? 0.35 : 0), radius: lifted && ui.expanded ? 36 : 0,
                y: lifted && ui.expanded ? 20 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.76), value: ui.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: extended)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: ui.expandedSize.height)
        .animation(.easeInOut(duration: 0.5), value: np.accent)
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
                musicIndicator
            } else {
                Text("\(shelf.items.count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 13)
        .frame(width: ui.notchW + ui.side * 2, height: ui.notchH)
    }

    /// Bars that dance with the music, or a flowing wave in the Glass style.
    @ViewBuilder private var musicIndicator: some View {
        if settings.style == .glass {
            MiniWave(playing: np.isPlaying, color: np.accent)
        } else {
            Waveform(playing: np.isPlaying, color: np.accent, glow: settings.style == .elevated)
        }
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
                .help(selected ? L("openApp", appName(s.bundleID)) : L("showApp", appName(s.bundleID)))
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
                        Text(s.isBreak ? L("break") : L("focusCycle", s.cycle, s.totalCycles))
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
        .help(L("openFoco"))
    }

    private var mediaSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Artwork(image: np.artwork, size: 56)
                    // Richer styles: the cover sits back a little while paused, like Apple Music.
                    .scaleEffect(settings.style != .basic && !np.isPlaying ? 0.9 : 1)
                    .shadow(color: np.accent.opacity(settings.style != .basic && np.isPlaying ? 0.5 : 0.35),
                            radius: settings.style != .basic && np.isPlaying ? 14 : 10, y: 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: np.isPlaying)
                    .modifier(Tilt(enabled: settings.style != .basic, size: 56))
                    .onTapGesture { np.openPlayer() }
                VStack(alignment: .leading, spacing: 2) {
                    Marquee(text: np.title, font: .system(size: 15, weight: .semibold), color: .white, height: 19)
                    Marquee(text: np.artist, font: .system(size: 13, weight: .medium), color: .white.opacity(0.65), height: 17)
                }
                // Glass lets the background through, so the text gets a soft shadow to stay readable.
                .shadow(color: .black.opacity(settings.style == .glass ? 0.45 : 0), radius: 2, y: 1)
                .id(np.title + np.artist)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                Spacer(minLength: 8)
                musicIndicator
            }
            .animation(.easeInOut(duration: 0.3), value: np.title + np.artist)
            // 20 updates a second while playing, so the bar glides instead of stepping.
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !np.isPlaying)) { ctx in
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
                HStack(spacing: 0) {
                    if settings.mirrorEnabled {
                        ControlButton(symbol: "camera", size: 15, color: .white.opacity(0.7)) { ui.mirrorOn = true }
                            .help(L("cameraMirror"))
                    }
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
                .padding(.horizontal, settings.style == .basic ? 0 : 6)
                .modifier(Surface(style: settings.style, shape: Capsule(), fallback: 0, elevated: 0.05))
                // The system only lets us control the app it is currently reporting.
                .disabled(!np.canControl)
                .opacity(np.canControl ? 1 : 0.35)
                .help(np.canControl ? "" : L("openToControl", appName(np.bundleID ?? "")))
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
                Text(on ? L("releaseNow") : L("dropHere")).font(.system(size: 13, weight: .semibold))
                if !shelf.isEmpty {
                    Text(L("alreadyOnShelf", shelf.items.count)).font(.system(size: 11)).opacity(0.6)
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
                    .help(shelf.selection.isEmpty ? L("clearShelf") : L("removeSelected", shelf.selection.count))
                }
                .padding(6)
                .modifier(Surface(style: settings.style, shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                  fallback: 0.05, elevated: 0.05))
            }
        }
        .frame(height: NotchState.shelfHeight)
    }

    /// Live camera, mirrored like a real mirror, to check yourself before a call.
    private var mirrorSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05))
            switch camera.state {
            case .running, .starting:
                CameraPreview(camera: camera)
                if camera.state == .starting { ProgressView().controlSize(.small) }
            case .denied:
                VStack(spacing: 8) {
                    Image(systemName: "video.slash").font(.system(size: 22)).foregroundColor(.white.opacity(0.6))
                    Text(L("cameraDenied"))
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button(L("openSettings")) { CameraMirror.openPrivacySettings() }.controlSize(.small)
                }
                .padding(16)
            case .unavailable:
                Label(L("noCamera"), systemImage: "video.slash")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            case .off:
                EmptyView()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
        .overlay(alignment: .topTrailing) {
            ControlButton(symbol: "xmark", size: 11, color: .white.opacity(0.9), box: 26) { ui.mirrorOn = false }
                .background(Circle().fill(Color.black.opacity(0.45)))
                .padding(8)
        }
        .frame(height: NotchState.mirrorHeight)
    }

    private func toastSection(_ t: NotchState.Toast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(t.ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(.white)
                if let detail = t.detail {
                    Text(detail).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.6)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchState.toastHeight)
        .transition(.opacity)
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            if ui.mirrorOn {
                mirrorSection
            } else if let toast = ui.toast {
                toastSection(toast)
            } else {
                regularSections
            }
        }
        .padding(.top, ui.notchH + 4)
        .padding(.horizontal, NotchState.hPad)
        .padding(.bottom, 10)
        .frame(width: ui.expandedSize.width, height: ui.expandedSize.height, alignment: .top)
        // Clicking the notch itself (the black band where the camera sits) toggles the mirror.
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: ui.notchH)
                .contentShape(Rectangle())
                .onTapGesture { ui.mirrorOn.toggle() }
                .help(L("cameraMirror"))
                .allowsHitTesting(settings.mirrorEnabled)
        }
    }

    @ViewBuilder private var regularSections: some View {
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
                    Label(L("nothingPlaying"), systemImage: "music.note")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.55))
                    Text(L("dragHint"))
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
                    if settings.mirrorEnabled {
                        Button { ui.mirrorOn = true } label: {
                            Label(L("cameraMirror"), systemImage: "camera")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 4)
                    }
                }
                .frame(height: NotchState.emptyHeight)
            }
    }
}

// MARK: - Settings window

/// Automation permission (Apple Events) for the players we script.
final class Permissions: ObservableObject {
    enum State { case notInstalled, granted, denied, ask }
    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var camera: State = .ask
    @Published private(set) var screen: State = .ask
    private let queue = DispatchQueue(label: "notch.permissions")
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private static func check(_ bundleID: String, ask: Bool) -> State {
        guard appURL(bundleID) != nil else { return .notInstalled }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .ask  // not decided yet, or the app isn't running so we can't tell
        }
    }

    func refresh() {
        queue.async {
            var s: [String: State] = [:]
            for p in Player.allCases { s[p.bundleID] = Self.check(p.bundleID, ask: false) }
            let cam: State
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: cam = .granted
            case .denied, .restricted: cam = .denied
            default: cam = .ask
            }
            DispatchQueue.main.async {
                self.states = s
                if self.camera != cam { self.camera = cam }
                let scr: State = CGPreflightScreenCaptureAccess() ? .granted : .ask
                if self.screen != scr { self.screen = scr }
            }
        }
    }

    /// macOS only asks while the target app is running, so open it quietly first if needed.
    func request(_ bundleID: String) {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        if !running, let url = appURL(bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        queue.asyncAfter(deadline: .now() + (running ? 0 : 2.5)) {
            _ = Self.check(bundleID, ask: true)
            self.refresh()
        }
    }

    func requestScreen() {
        // Only the first request shows a prompt; after that, go to the settings pane.
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { _ in self.refresh() }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Frosted group with a small caption, like the panes in System Settings.
func glassSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        if !title.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
        content()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
    }
}

/// Optional extras, shared by the walkthrough, Settings and the notch menu's submenu.
struct AddOnsList: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(L("addonOCR"), isOn: $settings.ocrEnabled)
            Toggle(L("addonMirror"), isOn: $settings.mirrorEnabled)
            Toggle(L("headphonesHQ"), isOn: $settings.keepHeadphonesHQ)
                .help(L("headphonesHQHint"))
            // Only for people who have the Foco study-timer app.
            if appURL(FocoTimer.bundleID) != nil {
                Toggle(L("showFoco"), isOn: $settings.showFoco)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row per permission (players, camera, screen), shared by the walkthrough and Settings.
struct PermissionsList: View {
    @ObservedObject var perms: Permissions
    @ObservedObject var settings = Settings.shared
    var onScreenRequest: () -> Void = {}

    // Camera and Screen Recording only show up when the add-on that needs them is on.
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Player.allCases, id: \.self) { p in
                if p != Player.allCases.first { Divider().opacity(0.5) }
                playerRow(p)
            }
            if settings.mirrorEnabled {
                Divider().opacity(0.5)
                cameraRow
            }
            if settings.ocrEnabled {
                Divider().opacity(0.5)
                screenRow
            }
        }
    }

    private var allowed: some View {
        Label(L("allowed"), systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.green)
    }

    private func row<Status: View>(icon: AnyView, title: String, hint: String?, @ViewBuilder status: () -> Status) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let hint {
                    Text(hint).font(.system(size: 10.5)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            status()
        }
    }

    private func symbol(_ name: String) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: 14)).foregroundColor(.white.opacity(0.85)))
    }

    private func playerRow(_ p: Player) -> some View {
        let icon: AnyView = appIcon(p.bundleID).map { AnyView(Image(nsImage: $0).resizable()) } ?? symbol("music.note")
        return row(icon: icon, title: p == .music ? "Apple Music" : "Spotify", hint: nil) {
            switch perms.states[p.bundleID] ?? .ask {
            case .notInstalled:
                Text(L("notInstalled")).font(.system(size: 12)).foregroundColor(.secondary)
            case .granted:
                allowed
            case .denied:
                Button(L("openSettings")) { perms.openSystemSettings() }.controlSize(.small)
            case .ask:
                Button(L("allow")) { perms.request(p.bundleID) }.controlSize(.small)
            }
        }
    }

    private var cameraRow: some View {
        row(icon: symbol("camera.fill"), title: L("camera"), hint: L("cameraHint")) {
            switch perms.camera {
            case .granted:
                allowed
            case .denied:
                Button(L("openSettings")) { CameraMirror.openPrivacySettings() }.controlSize(.small)
            default:
                Button(L("allow")) { perms.requestCamera() }.controlSize(.small)
            }
        }
    }

    private var screenRow: some View {
        row(icon: symbol("text.viewfinder"), title: L("screenRecording"), hint: L("screenRecordingHint")) {
            if perms.screen == .granted {
                allowed
            } else {
                Button(L("allow")) {
                    onScreenRequest()
                    perms.requestScreen()
                }
                .controlSize(.small)
            }
        }
    }
}

final class SettingsModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, addons, permissions
        var id: String { rawValue }
        var title: String { L(rawValue == "general" ? "general" : rawValue) }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .appearance: return "paintbrush.fill"
            case .addons: return "puzzlepiece.extension.fill"
            case .permissions: return "hand.raised.fill"
            }
        }
        var color: Color {
            switch self {
            case .general: return .gray
            case .appearance: return .purple
            case .addons: return .orange
            case .permissions: return .blue
            }
        }
    }
    @Published var pane: Pane = .general
}

/// Settings in landscape, like System Settings: sections on the left, their options on the right.
struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var perms: Permissions
    @StateObject private var model = SettingsModel()
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 214)
                .background(Color.black.opacity(0.18))
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            ZStack(alignment: .topLeading) {
                ScrollView {
                    content(model.pane)
                        .padding(.horizontal, 28)
                        .padding(.top, 30)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(model.pane)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 500)
        .background(VisualEffect(material: .hudWindow).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.pane)
        .animation(.easeInOut(duration: 0.2), value: settings.language)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NotchUser").font(.system(size: 15, weight: .bold))
                    Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 44)
            .padding(.bottom, 16)
            ForEach(SettingsModel.Pane.allCases) { pane in sidebarRow(pane) }
            Spacer()
            Text(L("tip"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private func sidebarRow(_ pane: SettingsModel.Pane) -> some View {
        let on = model.pane == pane
        return Button { model.pane = pane } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(pane.color.gradient)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: pane.icon).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white))
                    .scaleEffect(on ? 1.06 : 1)
                Text(pane.title).font(.system(size: 13, weight: on ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func content(_ pane: SettingsModel.Pane) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(pane.title).font(.system(size: 22, weight: .bold))
            switch pane {
            case .general:
                glassSection(L("language")) {
                    Picker("", selection: $settings.language) {
                        ForEach(Settings.Language.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                glassSection(L("behavior")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(L("peekOnTrack"), isOn: $settings.peekOnTrackChange)
                        Toggle(L("otherScreens"), isOn: $settings.showOnAllScreens)
                        LaunchAtLoginToggle(settings: settings)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .appearance:
                glassSection("") { StylePicker() }
            case .addons:
                glassSection("") { AddOnsList() }
                Text(L("addonsSub"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            case .permissions:
                glassSection("") {
                    VStack(spacing: 10) {
                        PermissionsList(perms: perms)
                        Text(L("permHint"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct LaunchAtLoginToggle: View {
    @ObservedObject var settings: Settings
    var body: some View {
        Toggle(L("launchAtLogin"), isOn: $settings.launchAtLogin)
    }
}

// MARK: - First-run walkthrough

final class OnboardingModel: ObservableObject {
    static let pages = 4
    @Published var page = 0
    /// Screen Recording only takes effect after a relaunch, so remember if it was asked for.
    var screenRequested = false
}

/// Shown once, the first time the app opens: welcome and language, what it does,
/// every permission in one place, and a few last options.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var perms: Permissions
    @ObservedObject var settings = Settings.shared
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Group {
                switch model.page {
                case 0: welcomePage
                case 1: featuresPage
                case 2: permissionsPage
                default: readyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(model.page)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)),
                                    removal: .opacity.combined(with: .offset(x: -40))))
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 500, height: 610)
        .background(VisualEffect(material: .hudWindow).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.page)
        .animation(.easeInOut(duration: 0.2), value: settings.language)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            Text(L("welcomeTitle")).font(.system(size: 26, weight: .bold))
            Text(L("welcomeSub"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 8)
            glassSection(L("language")) {
                Picker("", selection: $settings.language) {
                    ForEach(Settings.Language.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            glassSection(L("appearance")) {
                StylePicker()
            }
        }
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("featuresTitle"))
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            feature("music.note", .pink, L("featMusic"), L("featMusicDesc"))
            feature("tray.full.fill", .blue, L("featShelf"), L("featShelfDesc"))
            VStack(alignment: .leading, spacing: 6) {
                glassSection(L("addons")) { AddOnsList() }
                Text(L("addonsSub"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 6)
        }
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(color.gradient)
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 12) {
            Text(L("permissions")).font(.system(size: 22, weight: .bold))
            Text(L("permissionsSub"))
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            glassSection("") {
                PermissionsList(perms: perms, onScreenRequest: { model.screenRequested = true })
            }
        }
    }

    private var readyPage: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46))
                .foregroundStyle(.green)
            Text(L("readyTitle")).font(.system(size: 24, weight: .bold))
            glassSection(L("behavior")) {
                VStack(alignment: .leading, spacing: 9) {
                    LaunchAtLoginToggle(settings: settings)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(L("tipHover"), systemImage: "cursorarrow.motionlines")
                if settings.ocrEnabled {
                    Label(L("tipOCR"), systemImage: "text.viewfinder")
                }
                Label(L("tipMenu"), systemImage: "contextualmenu.and.cursorarrow")
            }
            .font(.system(size: 12.5))
            .foregroundColor(.white.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            if model.screenRequested {
                Text(L("relaunchNote"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        let last = model.page == OnboardingModel.pages - 1
        return HStack {
            Button(L("back")) { model.page -= 1 }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .opacity(model.page > 0 ? 1 : 0)
                .disabled(model.page == 0)
                .frame(width: 100, alignment: .leading)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<OnboardingModel.pages, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i == model.page ? 0.9 : 0.25))
                        .frame(width: i == model.page ? 18 : 7, height: 7)
                }
            }
            Spacer()
            Button {
                if last { onFinish() } else { model.page += 1 }
            } label: {
                Text(last ? L("getStarted") : L("next"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 84)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(width: 100, alignment: .trailing)
        }
    }
}

/// Centered, translucent window: the walkthrough on first launch, Settings afterwards.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let perms = Permissions()

    func show(welcome: Bool) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        guard let w = window else { return }
        if welcome {
            let model = OnboardingModel()
            let view = OnboardingView(model: model, perms: perms) { [weak self] in self?.finishOnboarding(model) }
            w.contentViewController = NSHostingController(rootView: view)
            w.setContentSize(NSSize(width: 500, height: 610))
        } else {
            let controller = NSHostingController(rootView: SettingsView(perms: perms))
            w.contentViewController = controller
            w.setContentSize(NSSize(width: 780, height: 500))
        }
        w.center()
        perms.start()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding(_ model: OnboardingModel) {
        Settings.shared.onboarded = true
        // macOS only applies Screen Recording access after the app restarts.
        if model.screenRequested {
            relaunch()
        } else {
            window?.close()
        }
    }

    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        perms.stop()
        Settings.shared.onboarded = true
    }
}

// MARK: - Window

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// The right-click menu, built fresh each time it opens.
    var menuProvider: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() ?? super.menu(for: event) }
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
    private let camera: CameraMirror
    private var mirrorWatch: AnyCancellable?
    let panel: NotchPanel
    let displayID: CGDirectDisplayID
    var peekUntil = Date.distantPast
    /// Keeps the notch open on the mirror for a moment, e.g. right after camera access was granted.
    var mirrorHoldUntil = Date.distantPast
    var toastUntil = Date.distantPast
    private var hoverSince: Date?
    private var leftSince: Date?
    /// Restarts the short grace period before the notch closes (e.g. once its menu is dismissed).
    func leaveDelayFromNow() { leftSince = Date() }

    init(screen: NSScreen, np: NowPlaying, shelf: Shelf, foco: FocoTimer, camera: CameraMirror) {
        displayID = screen.displayID
        self.camera = camera
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let host = HostingView(rootView: NotchView(np: np, ui: ui, shelf: shelf, foco: foco, camera: camera))
        host.menuProvider = { [weak self] in self.map { NotchMenu.build(for: $0, shelf: shelf) } }
        // The panel has a fixed frame; without this every redraw also recomputes window constraints.
        host.sizingOptions = []
        panel.contentView = host
        layout(screen)
        panel.orderFrontRegardless()
        // The camera follows the mirror: on when it opens, off as soon as it closes.
        mirrorWatch = ui.$mirrorOn.removeDuplicates().dropFirst().sink { [weak self] on in
            guard let self else { return }
            if on { self.camera.start() } else { self.camera.stop() }
        }
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

    /// Whether this notch needs the fast hover loop: it is open, peeking, or the mouse is close.
    func isHot(_ mouse: NSPoint) -> Bool {
        guard let s = screen else { return false }
        let zone = NSRect(x: s.frame.midX - 420, y: s.frame.maxY - 260, width: 840, height: 260)
        return ui.expanded || Date() < peekUntil || zone.contains(mouse)
    }

    /// While the right-click menu is open the notch holds still: the mouse is over the menu, not
    /// the notch, and closing it would also close the menu.
    var menuOpen = false
    let menuWatcher = MenuWatcher()

    func tick(fileDrag: Bool, np: NowPlaying, shelf: Shelf, foco: FocoTimer) {
        guard let s = screen, !menuOpen else { return }

        if fileDrag != ui.dragging { ui.dragging = fileDrag }
        // While something is carried in, the notch shows only the big drop zone.
        let showShelf = !shelf.isEmpty || fileDrag
        let showMedia = np.hasMedia && !fileDrag
        let showFocus = foco.session != nil && !fileDrag
        if ui.showMedia != showMedia { ui.showMedia = showMedia }
        if ui.showShelf != showShelf { ui.showShelf = showShelf }
        if ui.showFocus != showFocus { ui.showFocus = showFocus }
        let timerShown = foco.session != nil
        if ui.timerShown != timerShown { ui.timerShown = timerShown }

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
        // Stay open while macOS asks for camera permission (the mouse goes to that prompt).
        if ui.toast != nil && now >= toastUntil { ui.toast = nil }
        let want = hovering || dragNear || camera.asking || now < mirrorHoldUntil || now < toastUntil
            || (now < peekUntil && (np.hasMedia || foco.session != nil))
        // Dragging a file in needs the drop zone, not the mirror; nor is there one with the add-on off.
        if ui.mirrorOn && (fileDrag || !Settings.shared.mirrorEnabled) { ui.mirrorOn = false }

        if want != ui.expanded {
            // Closing the notch closes the mirror, which turns the camera off.
            if !want && ui.mirrorOn { ui.mirrorOn = false }
            ui.expanded = want
            if want {
                shelf.prune()
                if hovering || dragNear {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
        if inside { peekUntil = .distantPast }
        let lift = inside && !ui.expanded
        if ui.hovering != lift { ui.hovering = lift }
        let ignore = !(inside || dragNear)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let np = NowPlaying()
    let shelf = Shelf()
    let foco = FocoTimer()
    let camera = CameraMirror()
    let audioGuard = AudioGuard()
    private var ocrHotKey: HotKey?
    var controllers: [NotchController] = []
    var hoverTimer: Timer?
    private var hot = false
    private var idleDragCount = NSPasteboard(name: .drag).changeCount

    func applicationDidFinishLaunching(_ n: Notification) {
        rebuild()
        for name in [NSApplication.didChangeScreenParametersNotification, Settings.screensChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        }
        np.onTrackChange = { [weak self] in
            guard Settings.shared.peekOnTrackChange else {
                self?.controllers.forEach { $0.bump() }
                return
            }
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
        if !Settings.shared.onboarded { SettingsWindow.shared.show(welcome: true) }
        audioGuard.update()
        updateOCRHotKey()
        logScreenAccess()
        NotificationCenter.default.addObserver(forName: Settings.ocrChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateOCRHotKey()
        }
        ScreenText.shared.onResult = { [weak self] result in
            switch result {
            case .copied(let text):
                let preview = text.replacingOccurrences(of: "\n", with: " ")
                self?.showToast(.init(icon: "doc.on.clipboard.fill", title: L("textCopied"), detail: String(preview.prefix(90)), ok: true))
            case .nothing:
                self?.showToast(.init(icon: "text.viewfinder", title: L("noTextFound"), detail: L("noTextHint"), ok: false))
            case .needsPermission:
                self?.showToast(.init(icon: "lock.fill", title: L("screenPermissionNeeded"), detail: L("screenPermissionHint"), ok: false), seconds: 5)
            }
        }
        NotificationCenter.default.addObserver(forName: Settings.audioChanged, object: nil, queue: .main) { [weak self] _ in
            self?.audioGuard.update()
        }
        // Coming back from the permission prompt, show the mirror without another click.
        camera.onGranted = { [weak self] in
            guard let c = self?.controllers.first(where: { $0.screen?.hasNotch == true }) ?? self?.controllers.first else { return }
            c.mirrorHoldUntil = Date().addingTimeInterval(6)
            c.ui.mirrorOn = true
        }
        setTickRate(hot: true)
        // Mouse events wake the fast loop the moment the cursor heads for a notch
        // (mouse events need no Accessibility permission).
        let wake: (NSEvent) -> Void = { [weak self] _ in self?.wakeIfNear() }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged], handler: wake)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { e in wake(e); return e }
    }

    /// 30 checks a second near the notch, 4 a second otherwise.
    private func setTickRate(hot: Bool) {
        guard hot != self.hot || hoverTimer == nil else { return }
        self.hot = hot
        hoverTimer?.invalidate()
        let interval = hot ? 1.0 / 30 : 0.25
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func wakeIfNear() {
        guard !hot else { return }
        let mouse = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons & 1 != 0 || controllers.contains(where: { $0.isHot(mouse) }) {
            setTickRate(hot: true)
            tick()
        }
    }

    /// Keeps one controller per display that should show the notch.
    func rebuild() {
        let screens = NSScreen.screens.filter { $0.hasNotch || Settings.shared.showOnAllScreens }
        controllers.removeAll { c in
            guard !screens.contains(where: { $0.displayID == c.displayID }) else { return false }
            c.close()
            return true
        }
        for s in screens where !controllers.contains(where: { $0.displayID == s.displayID }) {
            controllers.append(NotchController(screen: s, np: np, shelf: shelf, foco: foco, camera: camera))
        }
        for c in controllers { if let s = c.screen { c.layout(s) } }
    }

    /// Logs what macOS reports about Screen Recording access, through two different APIs.
    private func logScreenAccess() {
        let log = Logger(subsystem: "io.github.notchuser", category: "ocr")
        log.notice("screen access at launch: preflight \(CGPreflightScreenCaptureAccess(), privacy: .public)")
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            log.notice("screen access at launch: ScreenCaptureKit \(error == nil && content != nil ? "ok" : "denied: \(error?.localizedDescription ?? "-")", privacy: .public)")
        }
    }

    private func updateOCRHotKey() {
        ocrHotKey = Settings.shared.ocrEnabled
            ? HotKey(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey) {
                Logger(subsystem: "io.github.notchuser", category: "ocr").notice("⌘⇧2 pressed")
                ScreenText.shared.capture()
            }
            : nil
    }

    /// Shows a short message in the notch (on the MacBook screen, or the first one).
    func showToast(_ toast: NotchState.Toast, seconds: TimeInterval = 2.8) {
        guard let c = controllers.first(where: { $0.screen?.hasNotch == true }) ?? controllers.first else { return }
        c.ui.toast = toast
        c.toastUntil = Date().addingTimeInterval(seconds)
        c.bump()
        setTickRate(hot: true)
    }

    func peek(_ seconds: TimeInterval) {
        for c in controllers {
            c.peekUntil = Date().addingTimeInterval(seconds)
            c.bump()
        }
        setTickRate(hot: true)
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
        // The type list is only fetched once a drag has really started (it's a round trip
        // to the pasteboard server).
        var fileDrag = false
        if mouseDown && !Shelf.draggingOut && dragPB.changeCount != idleDragCount {
            let types = dragPB.types ?? []
            fileDrag = types.contains(.fileURL) || types.contains(.URL) || types.contains(.string)
        }
        controllers.forEach { $0.tick(fileDrag: fileDrag, np: np, shelf: shelf, foco: foco) }
        let mouse = NSEvent.mouseLocation
        setTickRate(hot: mouseDown || controllers.contains(where: { $0.isHot(mouse) }))
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
