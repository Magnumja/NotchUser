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
import AudioToolbox
import IOKit.hid
import CoreImage
import ImageIO

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
    /// Builds, deploys and AI agents in the notch (also read by the command-line tool).
    @Published var activitiesEnabled: Bool {
        didSet {
            d.set(activitiesEnabled, forKey: "activitiesEnabled")
            NotificationCenter.default.post(name: Self.activitiesChanged, object: nil)
        }
    }
    static let activitiesChanged = Notification.Name("NotchUser.activitiesSettingChanged")
    static let ocrChanged = Notification.Name("NotchUser.ocrSettingChanged")

    /// How the notch looks: as plain as the hardware, lifted with depth, or see-through glass.
    enum Style: String, CaseIterable, Identifiable {
        case basic, elevated, glass
        var id: String { rawValue }
        var title: String { L("style." + rawValue) }
    }
    @Published var style: Style { didSet { d.set(style.rawValue, forKey: "style") } }

    /// How alive the notch feels: from plain fades to a jelly that oozes out of the bezel.
    enum Motion: String, CaseIterable, Identifiable {
        case minimal, calm, fluid, lively
        var id: String { rawValue }
        var title: String { L("motion." + rawValue) }
    }
    @Published var motion: Motion { didSet { d.set(motion.rawValue, forKey: "motion") } }
    /// 0.6 (slow) ... 1.6 (snappy).
    @Published var motionSpeed: Double { didSet { d.set(motionSpeed, forKey: "motionSpeed") } }
    /// The closed notch leans toward the cursor as it gets close.
    @Published var magnetism: Bool { didSet { d.set(magnetism, forKey: "magnetism") } }
    /// Size of the open notch, 0.85 ... 1.25 (the closed one always matches the hardware).
    @Published var notchScale: Double { didSet { d.set(notchScale, forKey: "notchScale") } }
    /// Width of the pieces that stick out of the closed notch, 0.7 ... 1.6.
    @Published var sideScale: Double { didSet { d.set(sideScale, forKey: "sideScale") } }

    // More add-ons, also off until turned on (haptics and the edge glow only react to events).
    /// Scroll on the notch for volume, swipe sideways to change the song.
    @Published var gesturesEnabled: Bool { didSet { d.set(gesturesEnabled, forKey: "gesturesEnabled") } }
    /// Show when the microphone is in use; ⌃⌥M mutes it everywhere.
    @Published var micEnabled: Bool {
        didSet {
            d.set(micEnabled, forKey: "micEnabled")
            NotificationCenter.default.post(name: Self.micChanged, object: nil)
        }
    }
    static let micChanged = Notification.Name("NotchUser.micSettingChanged")
    /// Pause the music (and mute the mic) when the lid is lowered.
    @Published var lidPauseEnabled: Bool {
        didSet {
            d.set(lidPauseEnabled, forKey: "lidPauseEnabled")
            NotificationCenter.default.post(name: Self.lidChanged, object: nil)
        }
    }
    @Published var lidThreshold: Double { didSet { d.set(lidThreshold, forKey: "lidThreshold") } }
    static let lidChanged = Notification.Name("NotchUser.lidSettingChanged")
    /// Pulses in the trackpad for things that happen (a command finished, a file arrived).
    @Published var hapticsEnabled: Bool { didSet { d.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    /// A soft light around the screen edges when a command finishes.
    @Published var edgeGlowEnabled: Bool { didSet { d.set(edgeGlowEnabled, forKey: "edgeGlowEnabled") } }
    /// Synced lyrics: the closed notch stretches to each line as it's sung.
    @Published var lyricsEnabled: Bool {
        didSet {
            d.set(lyricsEnabled, forKey: "lyricsEnabled")
            NotificationCenter.default.post(name: Self.lyricsChanged, object: nil)
        }
    }
    /// Also sing in the closed notch (off unless chosen; the player's lyrics button is enough for most).
    @Published var lyricsClosed: Bool {
        didSet {
            d.set(lyricsClosed, forKey: "lyricsClosed")
            NotificationCenter.default.post(name: Self.lyricsChanged, object: nil)
        }
    }
    static let lyricsChanged = Notification.Name("NotchUser.lyricsSettingChanged")
    /// When the open notch would get too tall, its sections become pages with dots.
    @Published var pagesEnabled: Bool { didSet { d.set(pagesEnabled, forKey: "pagesEnabled") } }

    /// Asks the notch to open for a moment, to try the animation settings.
    static let previewRequested = Notification.Name("NotchUser.previewRequested")

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
        activitiesEnabled = d.bool(forKey: "activitiesEnabled")
        style = Style(rawValue: d.string(forKey: "style") ?? "") ?? .basic
        motion = Motion(rawValue: d.string(forKey: "motion") ?? "") ?? .fluid
        motionSpeed = d.object(forKey: "motionSpeed") as? Double ?? 1
        magnetism = d.object(forKey: "magnetism") as? Bool ?? true
        notchScale = d.object(forKey: "notchScale") as? Double ?? 1
        sideScale = d.object(forKey: "sideScale") as? Double ?? 1
        gesturesEnabled = d.bool(forKey: "gesturesEnabled")
        micEnabled = d.bool(forKey: "micEnabled")
        lidPauseEnabled = d.bool(forKey: "lidPauseEnabled")
        lidThreshold = d.object(forKey: "lidThreshold") as? Double ?? 40
        hapticsEnabled = d.object(forKey: "hapticsEnabled") as? Bool ?? true
        edgeGlowEnabled = d.object(forKey: "edgeGlowEnabled") as? Bool ?? true
        lyricsEnabled = d.bool(forKey: "lyricsEnabled")
        lyricsClosed = d.bool(forKey: "lyricsClosed")
        pagesEnabled = d.object(forKey: "pagesEnabled") as? Bool ?? true
    }

    /// The motion actually used: Reduce Motion in Accessibility always wins.
    var effectiveMotion: Motion {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .minimal : motion
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
        // Lyrics
        "addonLyrics": ["en": "Synced lyrics", "pt": "Letras sincronizadas", "es": "Letras sincronizadas"],
        "addonLyricsHint": ["en": "A lyrics button in the player. Lyrics come from LRCLIB, a free database, only when you open them: just the song's title, artist and length are sent.",
                            "pt": "Um botão de letra no player. As letras vêm do LRCLIB, um banco gratuito, só quando você abre: apenas o nome da música, o artista e a duração são enviados.",
                            "es": "Un botón de letras en el reproductor. Las letras vienen de LRCLIB, una base gratuita, solo cuando las abres: se envían el título, el artista y la duración."],
        "lyricsClosed": ["en": "Also in the closed notch", "pt": "Também no notch fechado", "es": "También en el notch cerrado"],
        "lyrics": ["en": "Lyrics", "pt": "Letra", "es": "Letra"],
        "lyricsLoading": ["en": "Looking for the lyrics…", "pt": "Procurando a letra…", "es": "Buscando la letra…"],
        "pages": ["en": "Use pages when the notch gets full", "pt": "Usar páginas quando o notch encher", "es": "Usar páginas cuando el notch se llene"],
        "page.main": ["en": "Music", "pt": "Música", "es": "Música"],
        "page.shelf": ["en": "Shelf", "pt": "Prateleira", "es": "Estante"],
        "page.activities": ["en": "Activities", "pt": "Atividades", "es": "Actividades"],
        "volume": ["en": "Volume", "pt": "Volume", "es": "Volumen"],
        "lyricsPlain": ["en": "Not synced", "pt": "Sem sincronia", "es": "Sin sincronizar"],
        "lyricsMissing": ["en": "No synced lyrics for this song", "pt": "Sem letra sincronizada pra esta música", "es": "No hay letra sincronizada para esta canción"],
        // Live activities
        "addonActivities": ["en": "Live activities (builds, AI agents)", "pt": "Atividades ao vivo (builds, agentes de IA)",
                            "es": "Actividades en vivo (builds, agentes de IA)"],
        "activitiesHint": ["en": "Commands and agents show up in the notch while they run, ask for approval there and tell you when they finish.",
                           "pt": "Comandos e agentes aparecem no notch enquanto rodam, pedem aprovação por ali e avisam quando terminam.",
                           "es": "Los comandos y agentes aparecen en el notch mientras se ejecutan, piden aprobación ahí y avisan al terminar."],
        "agentHint.claude": ["en": "Working, waiting for your approval, finished. Approve right from the notch.",
                           "pt": "Trabalhando, esperando sua aprovação, terminou. Aprove direto pelo notch.",
                           "es": "Trabajando, esperando tu aprobación, terminado. Aprueba desde el notch."],
        "connect": ["en": "Connect", "pt": "Conectar", "es": "Conectar"],
        "disconnect": ["en": "Disconnect", "pt": "Desconectar", "es": "Desconectar"],
        "connected": ["en": "Connected", "pt": "Conectado", "es": "Conectado"],
        "claudeRestart": ["en": "Sessions already open pick it up after a restart.", "pt": "Sessões já abertas passam a usar depois de reiniciar.",
                          "es": "Las sesiones ya abiertas lo usan tras reiniciarlas."],
        "agentSettingsError": ["en": "Couldn't read %@. Fix the file and try again.",
                               "pt": "Não deu pra ler o %@. Corrija o arquivo e tente de novo.",
                               "es": "No se pudo leer %@. Corrige el archivo e inténtalo de nuevo."],
        "agentHint.codex": ["en": "The Codex app and CLI: working, waiting for your approval, finished.",
                            "pt": "O app e a CLI do Codex: trabalhando, esperando sua aprovação, terminou.",
                            "es": "La app y la CLI de Codex: trabajando, esperando tu aprobación, terminado."],
        "agentHint.copilot": ["en": "GitHub Copilot's agent in VS Code and the Copilot CLI: working and finished.",
                              "pt": "O agente do GitHub Copilot no VS Code e a CLI do Copilot: trabalhando e terminou.",
                              "es": "El agente de GitHub Copilot en VS Code y la CLI de Copilot: trabajando y terminado."],
        "codexTrust": ["en": "Codex asks to trust new hooks once: approve NotchUser's in /hooks.",
                       "pt": "O Codex pede pra confiar em hooks novos uma vez: aprove os do NotchUser em /hooks.",
                       "es": "Codex pide confiar en hooks nuevos una vez: aprueba los de NotchUser en /hooks."],
        "autoTasks": ["en": "Builds, tests, installs and deploys", "pt": "Builds, testes, instalações e deploys",
                      "es": "Builds, tests, instalaciones y deploys"],
        "autoTasksHint": ["en": "Show up on their own, wherever they were started: npm, Xcode, cargo, docker, brew, git push…",
                          "pt": "Aparecem sozinhos, de onde quer que tenham começado: npm, Xcode, cargo, docker, brew, git push…",
                          "es": "Aparecen solos, se inicien donde se inicien: npm, Xcode, cargo, docker, brew, git push…"],
        "connecting": ["en": "Connecting…", "pt": "Conectando…", "es": "Conectando…"],
        "disconnecting": ["en": "Disconnecting…", "pt": "Desconectando…", "es": "Desconectando…"],
        "deny": ["en": "Deny", "pt": "Negar", "es": "Denegar"],
        "inTerminal": ["en": "Answer in the terminal", "pt": "Responder no terminal", "es": "Responder en la terminal"],
        "send": ["en": "Send", "pt": "Enviar", "es": "Enviar"],
        "activityDone": ["en": "Done", "pt": "Terminou", "es": "Terminado"],
        "activityFailed": ["en": "Failed", "pt": "Falhou", "es": "Falló"],
        "activityWaiting": ["en": "Waiting for you", "pt": "Esperando você", "es": "Esperándote"],
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
        // Motion and size
        "motion": ["en": "Motion", "pt": "Movimento", "es": "Movimiento"],
        "motion.minimal": ["en": "Minimal", "pt": "Mínima", "es": "Mínima"],
        "motion.calm": ["en": "Calm", "pt": "Suave", "es": "Suave"],
        "motion.fluid": ["en": "Fluid", "pt": "Fluida", "es": "Fluida"],
        "motion.lively": ["en": "Lively", "pt": "Viva", "es": "Viva"],
        "motionHint": ["en": "Fluid: the notch spreads out of the bezel first and then drops down, and slips back in when it closes. Lively: the same with more bounce and a ripple when something arrives.",
                       "pt": "Fluida: o notch se espalha pra fora da borda primeiro e depois desce, e volta pra dentro quando fecha. Viva: o mesmo, com mais elasticidade e uma onda quando algo chega.",
                       "es": "Fluida: el notch se extiende fuera del borde primero y luego baja, y vuelve a entrar al cerrarse. Viva: lo mismo con más rebote y una onda cuando llega algo."],
        "motionSpeed": ["en": "Speed", "pt": "Velocidade", "es": "Velocidad"],
        "slower": ["en": "Slower", "pt": "Mais lento", "es": "Más lento"],
        "faster": ["en": "Faster", "pt": "Mais rápido", "es": "Más rápido"],
        "magnetism": ["en": "The notch leans toward the cursor as it gets close", "pt": "O notch se estica na direção do mouse quando ele chega perto",
                      "es": "El notch se estira hacia el ratón cuando se acerca"],
        "reduceMotionOn": ["en": "Reduce Motion is on in Accessibility, so the notch only fades.",
                           "pt": "A opção Reduzir Movimento está ligada na Acessibilidade, então o notch só aparece e some.",
                           "es": "Reducir movimiento está activado en Accesibilidad, así que el notch solo aparece y desaparece."],
        "size": ["en": "Size", "pt": "Tamanho", "es": "Tamaño"],
        "notchSize": ["en": "Open notch", "pt": "Notch aberto", "es": "Notch abierto"],
        "sideSize": ["en": "Side pieces of the closed notch", "pt": "Abas do notch fechado", "es": "Lados del notch cerrado"],
        "sizeHint": ["en": "The closed notch always matches the hardware; only what sticks out of it changes.",
                     "pt": "O notch fechado sempre acompanha o do hardware; só muda o que sai dele.",
                     "es": "El notch cerrado siempre coincide con el del hardware; solo cambia lo que sale de él."],
        "reset": ["en": "Reset", "pt": "Restaurar", "es": "Restablecer"],
        "tryIt": ["en": "Try it", "pt": "Testar", "es": "Probar"],
        // More add-ons
        "addonGestures": ["en": "Gestures on the notch (volume and songs)", "pt": "Gestos no notch (volume e músicas)",
                          "es": "Gestos en el notch (volumen y canciones)"],
        "addonGesturesHint": ["en": "Scroll up or down over the notch for volume, swipe sideways to change the song.",
                              "pt": "Role pra cima ou pra baixo sobre o notch pro volume, deslize de lado pra trocar de música.",
                              "es": "Desplaza arriba o abajo sobre el notch para el volumen, desliza de lado para cambiar de canción."],
        "addonMic": ["en": "Microphone indicator and mute (⌃⌥M)", "pt": "Indicador e mudo do microfone (⌃⌥M)",
                     "es": "Indicador y silencio del micrófono (⌃⌥M)"],
        "addonMicHint": ["en": "A dot in the notch shows when an app is using the mic; ⌃⌥M mutes it in every app.",
                         "pt": "Um ponto no notch mostra quando algum app está usando o microfone; ⌃⌥M silencia em todos os apps.",
                         "es": "Un punto en el notch muestra cuándo una app usa el micrófono; ⌃⌥M lo silencia en todas."],
        "addonLid": ["en": "Pause when the lid is lowered", "pt": "Pausar ao baixar a tampa", "es": "Pausar al bajar la tapa"],
        "addonLidHint": ["en": "Lower the lid past the angle below and the music pauses and the mic mutes; raise it to resume.",
                         "pt": "Baixe a tampa além do ângulo abaixo e a música pausa e o microfone silencia; levante pra voltar.",
                         "es": "Baja la tapa más allá del ángulo de abajo y la música se pausa y el micrófono se silencia; súbela para seguir."],
        "lidAngle": ["en": "Pause below %ld°", "pt": "Pausar abaixo de %ld°", "es": "Pausar por debajo de %ld°"],
        "lidNow": ["en": "Lid now: %ld°", "pt": "Tampa agora: %ld°", "es": "Tapa ahora: %ld°"],
        "lidUnavailable": ["en": "This Mac doesn't report the lid angle.", "pt": "Este Mac não informa o ângulo da tampa.",
                           "es": "Este Mac no informa el ángulo de la tapa."],
        "addonHaptics": ["en": "Haptic pulses in the trackpad", "pt": "Pulsos táteis no trackpad", "es": "Pulsos táctiles en el trackpad"],
        "addonHapticsHint": ["en": "Felt while a finger rests on the trackpad: one tap when a file arrives, two when a command works, three when it fails.",
                             "pt": "Sentidos com o dedo apoiado no trackpad: um toque quando chega um arquivo, dois quando um comando dá certo, três quando falha.",
                             "es": "Se sienten con un dedo en el trackpad: un toque al llegar un archivo, dos cuando un comando funciona, tres cuando falla."],
        "addonGlow": ["en": "Glow at the screen edges", "pt": "Brilho nas bordas da tela", "es": "Brillo en los bordes de la pantalla"],
        "addonGlowHint": ["en": "Green or red around the screen when a command run with notch finishes.",
                          "pt": "Verde ou vermelho em volta da tela quando um comando rodado com notch termina.",
                          "es": "Verde o rojo alrededor de la pantalla cuando termina un comando ejecutado con notch."],
        "terminalActivities": ["en": "Activities from the Terminal", "pt": "Atividades do Terminal", "es": "Actividades desde la Terminal"],
        "terminalHint": ["en": "Run any command as notch run <command> and follow it in the notch until it finishes. To install the notch command, paste this in the Terminal:",
                           "pt": "Rode qualquer comando como notch run <comando> e acompanhe no notch até terminar. Pra instalar o comando notch, cole isto no Terminal:",
                           "es": "Ejecuta cualquier comando como notch run <comando> y síguelo en el notch hasta que termine. Para instalar el comando notch, pega esto en la Terminal:"],
        "copyCommand": ["en": "Copy", "pt": "Copiar", "es": "Copiar"],
        "copied": ["en": "Copied", "pt": "Copiado", "es": "Copiado"],
        // Microphone, lid, activities
        "micMuted": ["en": "Microphone muted", "pt": "Microfone silenciado", "es": "Micrófono silenciado"],
        "micLive": ["en": "Microphone on", "pt": "Microfone ligado", "es": "Micrófono activado"],
        "micMutedHint": ["en": "In every app. ⌃⌥M turns it back on.", "pt": "Em todos os apps. ⌃⌥M liga de novo.",
                         "es": "En todas las apps. ⌃⌥M lo vuelve a activar."],
        "micMuteFailed": ["en": "This microphone can't be muted", "pt": "Não dá pra silenciar este microfone",
                          "es": "Este micrófono no se puede silenciar"],
        "muteMic": ["en": "Mute microphone", "pt": "Silenciar microfone", "es": "Silenciar micrófono"],
        "unmuteMic": ["en": "Turn microphone on", "pt": "Ligar microfone", "es": "Activar micrófono"],
        "lidPaused": ["en": "Lid lowered: paused", "pt": "Tampa abaixada: pausado", "es": "Tapa bajada: en pausa"],
        // Shelf quick actions
        "quickActions": ["en": "Quick actions", "pt": "Ações rápidas", "es": "Acciones rápidas"],
        "toJPEG": ["en": "Convert to JPEG", "pt": "Converter para JPEG", "es": "Convertir a JPEG"],
        "toPNG": ["en": "Convert to PNG", "pt": "Converter para PNG", "es": "Convertir a PNG"],
        "halfSize": ["en": "Make it half the size", "pt": "Reduzir pela metade", "es": "Reducir a la mitad"],
        "imageText": ["en": "Copy text from image", "pt": "Copiar texto da imagem", "es": "Copiar texto de la imagen"],
        "compressVideo": ["en": "Compress video (1080p)", "pt": "Comprimir vídeo (1080p)", "es": "Comprimir vídeo (1080p)"],
        "zip": ["en": "Compress to ZIP", "pt": "Compactar em ZIP", "es": "Comprimir en ZIP"],
        "zipN": ["en": "Compress %ld items to ZIP", "pt": "Compactar %ld itens em ZIP", "es": "Comprimir %ld elementos en ZIP"],
        "working": ["en": "Working on it…", "pt": "Trabalhando nisso…", "es": "Trabajando en ello…"],
        "actionDone": ["en": "Ready", "pt": "Pronto", "es": "Listo"],
        "actionDoneHint": ["en": "%@ is on the shelf.", "pt": "%@ está na prateleira.", "es": "%@ está en el estante."],
        "actionFailed": ["en": "Couldn't finish", "pt": "Não deu pra concluir", "es": "No se pudo completar"],
        "suffix.converted": ["en": "converted", "pt": "convertido", "es": "convertido"],
        "suffix.half": ["en": "half", "pt": "metade", "es": "mitad"],
        "suffix.compressed": ["en": "compressed", "pt": "comprimido", "es": "comprimido"],
        "archive": ["en": "Archive", "pt": "Arquivo", "es": "Archivo"],
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

// MARK: - Live activities (builds, deploys, AI agents)
//
// Anything can appear in the notch by leaving a small JSON file in the activities folder, so
// scripts, CI watchers and agents need no SDK. The app's own binary doubles as the command-line
// tool (`NotchUser run -- make`), and `NotchUser agent-hook` connects Claude Code, Codex and Copilot.

struct Activity: Codable, Equatable, Identifiable {
    enum State: String, Codable { case running, waiting, done, failed }
    var id = ""              // the file name, not stored inside it
    var title: String
    var detail: String?
    var state: State
    var progress: Double?    // 0...1; nil while it's unknown
    var question: String?    // what a waiting activity asks
    /// Multiple choice, when the agent asks you to pick (instead of allow/deny).
    struct Option: Codable, Equatable, Hashable { var label: String; var description: String? }
    var options: [Option]?
    var multi: Bool?         // several options can be picked
    var header: String?      // a short tag for the question
    var step: String?        // "1/2" when the agent asks several questions in a row
    var icon: String?        // SF Symbol
    var app: String?         // bundle ID brought forward on click
    var open: String?        // URL or path opened on click (wins over app)
    var pid: Int32?          // the activity goes away if this process dies
    var started: Date?
    var updated: Date?

    private enum CodingKeys: String, CodingKey {
        case title, detail, state, progress, question, options, multi, header, step, icon, app, open, pid, started, updated
    }

    /// A question to answer by picking one of its options.
    var isChoice: Bool { state == .waiting && !(options ?? []).isEmpty }

    var finished: Bool { state == .done || state == .failed }

    func elapsed(at now: Date) -> TimeInterval {
        let end = finished ? (updated ?? now) : now
        return max(0, end.timeIntervalSince(started ?? updated ?? now))
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return String(format: "%dh %02dm", s / 3600, s % 3600 / 60)
    }
}

/// The folder both sides share: tools write `<id>.json`, the notch answers in `<id>.reply`.
enum ActivityFiles {
    static let appID = "io.github.notchuser"
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NotchUser/Activities", isDirectory: true)
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()

    static func safe(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "-" }.prefix(80))
    }
    static func url(_ id: String, _ ext: String = "json") -> URL { dir.appendingPathComponent(safe(id) + "." + ext) }

    static func read(_ id: String) -> Activity? {
        guard let data = try? Data(contentsOf: url(id)), var a = try? decoder.decode(Activity.self, from: data) else { return nil }
        a.id = id
        return a
    }
    static func write(_ a: Activity) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var a = a
        a.updated = Date()
        try? encoder.encode(a).write(to: url(a.id), options: .atomic)
    }
    static func remove(_ id: String) {
        for ext in ["json", "reply"] { try? FileManager.default.removeItem(at: url(id, ext)) }
    }
}

func processAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

/// Follows the activities folder. Idle costs nothing: the kernel wakes it when a file changes.
final class Activities: ObservableObject {
    @Published private(set) var items: [Activity] = []
    var onAttention: (() -> Void)?  // something started waiting for an answer
    var onFinish: (([Activity]) -> Void)?  // what just finished
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var liveness: Timer?
    private var expiry: [String: DispatchWorkItem] = [:]
    private var seen: Set<String> = []
    /// Finished activities stay until the notch has shown them, then leave shortly after.
    private let keepUnseen: TimeInterval = 600, keepSeen: TimeInterval = 6

    private let devTasks = DevTasks()

    /// The folder is always followed (the kernel wakes us, so idle costs nothing): the notch
    /// command and notchuser:// work on their own. The add-on adds the agents and automatic detection.
    func update() {
        start()
        devTasks.update(Settings.shared.activitiesEnabled)
    }

    private func start() {
        guard source == nil else { return }
        try? FileManager.default.createDirectory(at: ActivityFiles.dir, withIntermediateDirectories: true)
        let fd = Darwin.open(ActivityFiles.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.scheduleReload() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        reload()
    }

    /// A tool often writes several times in a row; read once they settle.
    private func scheduleReload() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reload() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: w)
    }

    func reload() {
        guard source != nil else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: ActivityFiles.dir, includingPropertiesForKeys: nil)) ?? []
        let now = Date()
        var new: [Activity] = []
        for f in files where f.pathExtension == "json" {
            let id = f.deletingPathExtension().lastPathComponent
            guard let a = ActivityFiles.read(id) else { continue }
            // Left behind by a process that died, or by a tool that never said it was finished.
            let dead = a.pid.map { !processAlive($0) } ?? false
            if !a.finished && (dead || now.timeIntervalSince(a.updated ?? now) > 6 * 3600) {
                ActivityFiles.remove(id)
                continue
            }
            new.append(a)
        }
        func rank(_ a: Activity) -> Int { [.waiting: 0, .running: 1, .failed: 2, .done: 3][a.state] ?? 4 }
        new.sort { (rank($0), $0.started ?? .distantPast) < (rank($1), $1.started ?? .distantPast) }

        let old = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A new question counts too, also the next one of a series.
        let attention = new.contains { $0.state == .waiting && (old[$0.id]?.state != .waiting || old[$0.id]?.question != $0.question) }
        // Only fresh endings: a finished file found at launch isn't news.
        let finished = new.filter { $0.finished && old[$0.id]?.finished != true && now.timeIntervalSince($0.updated ?? .distantPast) < 30 }
        for a in new {
            if !a.finished { seen.remove(a.id); expiry.removeValue(forKey: a.id)?.cancel() }
            else if expiry[a.id] == nil {
                expire(a.id, after: keepUnseen - now.timeIntervalSince(a.updated ?? now))
            }
        }
        if new != items { items = new }

        // Processes can die without saying so; check on them while anything is attached to one.
        let watch = items.contains { $0.pid != nil && !$0.finished }
        if watch, liveness == nil {
            liveness = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reload() }
            liveness?.tolerance = 1
        } else if !watch {
            liveness?.invalidate()
            liveness = nil
        }
        if attention { onAttention?() } else if !finished.isEmpty { onFinish?(finished) }
    }

    private func expire(_ id: String, after seconds: TimeInterval) {
        expiry[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in
            ActivityFiles.remove(id)
            self?.expiry[id] = nil
            self?.seen.remove(id)
        }
        expiry[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds), execute: w)
    }

    /// The notch is open and showing them: finished ones can leave soon.
    func markSeen() {
        for a in items.prefix(NotchState.maxActivities) where a.finished && !seen.contains(a.id) {
            seen.insert(a.id)
            expire(a.id, after: keepSeen)
        }
    }

    var waiting: Bool { items.contains { $0.state == .waiting } }

    var onAnswered: (() -> Void)?

    /// "allow", "deny" or "ask" (answer in the terminal instead).
    func answer(_ a: Activity, _ reply: String) {
        try? reply.write(to: ActivityFiles.url(a.id, "reply"), atomically: true, encoding: .utf8)
        onAnswered?()
    }

    /// The picked option labels of a multiple-choice question.
    func choose(_ a: Activity, _ labels: [String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: labels), let text = String(data: data, encoding: .utf8) else { return }
        answer(a, text)
    }

    var question: Activity? { items.first { $0.isChoice } }

    func dismiss(_ a: Activity) {
        ActivityFiles.remove(a.id)
        withAnimation(.spring(response: 0.35)) { items.removeAll { $0.id == a.id } }
    }

    func activate(_ a: Activity) {
        if let o = a.open, let url = o.hasPrefix("/") ? URL(fileURLWithPath: o) : URL(string: o) {
            NSWorkspace.shared.open(url)
        } else if let b = a.app {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: b).first {
                running.activate()
            } else if let url = appURL(b) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
    }
}

/// `NotchUser <command>` from a terminal, a script or a hook. Runs without starting the app.
enum CLI {
    static let usage = """
    NotchUser live activities

      NotchUser run [--title T] [--] command args…   run a command and show it in the notch
      NotchUser set <id> --title T [--detail D] [--state running|waiting|done|failed]
                         [--progress 0-1] [--icon symbol] [--open url-or-path]
      NotchUser ask <id> --title T --question Q [--timeout seconds]
                         waits for Allow/Deny in the notch; prints allow, deny or nothing
                         (exit 0, 1 or 2)
      NotchUser clear <id>
      NotchUser connect | disconnect claude|codex|copilot
                                                     add or remove an agent's hooks
      NotchUser agent-hook claude|codex|copilot      for the agents' hooks (reads JSON on stdin)

    Turn on Live activities in NotchUser's add-ons first.

    """

    /// nil: not a command, so start the app.
    static func run(_ args: [String]) -> Int32? {
        guard let cmd = args.first else { return nil }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "run": return runCommand(rest)
        case "set": return set(rest)
        case "ask": return ask(rest)
        case "clear":
            guard let id = rest.first else { return fail() }
            ActivityFiles.remove(id)
            return 0
        case "claude-hook": return agentHook(.claude, event: nil)
        case "agent-hook":
            guard let agent = rest.first.flatMap(Agent.init(rawValue:)) else { return fail() }
            return agentHook(agent, event: rest.dropFirst().first)
        case "connect", "disconnect", "claude-connect", "claude-disconnect":
            let on = cmd.hasSuffix("connect") && !cmd.hasSuffix("disconnect")
            guard let agent = cmd.hasPrefix("claude") ? .claude : rest.first.flatMap(Agent.init(rawValue:)) else { return fail() }
            do {
                try AgentHooks.set(agent, on)
                print(on ? "Connected \(agent.name): \(AgentHooks.configURL(agent).path)" : "Disconnected \(agent.name)")
                return 0
            } catch {
                FileHandle.standardError.write("Couldn't read \(AgentHooks.configURL(agent).path)\n".data(using: .utf8)!)
                return 1
            }
        case "help", "-h", "--help":
            print(usage, terminator: "")
            return 0
        default: return nil
        }
    }

    private static func fail() -> Int32 {
        FileHandle.standardError.write(usage.data(using: .utf8)!)
        return 64
    }

    /// `--key value` pairs and positional arguments. With `command`, everything from the first
    /// positional on belongs to the command (`run make --jobs 4`); `--` also ends the options.
    private static func parse(_ args: [String], command: Bool = false) -> (opts: [String: String], rest: [String]) {
        var opts: [String: String] = [:], rest: [String] = []
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--" { rest += args[(i + 1)...]; break }
            if command && !rest.isEmpty { rest += args[i...]; break }
            if a.hasPrefix("--"), i + 1 < args.count {
                opts[String(a.dropFirst(2))] = args[i + 1]
                i += 2
            } else {
                rest.append(a)
                i += 1
            }
        }
        return (opts, rest)
    }

    /// The live-activities add-on is on and the app is there to show them.
    static var enabled: Bool {
        let id = ActivityFiles.appID as CFString
        CFPreferencesAppSynchronize(id)
        guard CFPreferencesCopyAppValue("activitiesEnabled" as CFString, id) as? Bool == true else { return false }
        return appRunning
    }

    private static var appRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: ActivityFiles.appID)
            .contains { $0.processIdentifier != getpid() }
    }

    /// The app this was started from (Terminal, iTerm, VS Code…), to bring forward on click.
    private static var hostApp: String? {
        let id = ProcessInfo.processInfo.environment["__CFBundleIdentifier"]
        return id == ActivityFiles.appID ? nil : id
    }

    private static func folderName(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    private static func runCommand(_ args: [String]) -> Int32 {
        let (opts, cmd) = parse(args, command: true)
        guard !cmd.isEmpty else { return fail() }
        let on = enabled
        var a = Activity(id: opts["id"] ?? "run-\(getpid())", title: opts["title"] ?? cmd.joined(separator: " "),
                         detail: opts["detail"] ?? folderName(FileManager.default.currentDirectoryPath),
                         state: .running, icon: opts["icon"] ?? "terminal.fill", app: hostApp, open: opts["open"],
                         pid: getpid(), started: Date())
        if on { ActivityFiles.write(a) }

        // Same process group as us, so Ctrl-C reaches the command; we stay to report how it ended.
        var child: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = cmd.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0)=\($1)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        let rc = posix_spawnp(&child, cmd[0], nil, nil, &argv, &envp)
        guard rc == 0 else {
            FileHandle.standardError.write("NotchUser: \(cmd[0]): \(String(cString: strerror(rc)))\n".data(using: .utf8)!)
            if on { a.state = .failed; a.detail = String(cString: strerror(rc)); a.pid = nil; ActivityFiles.write(a) }
            return 127
        }
        signal(SIGINT, SIG_IGN)
        signal(SIGQUIT, SIG_IGN)
        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
        let sig = status & 0x7f
        let code = sig == 0 ? (status >> 8) & 0xff : 128 + sig
        if on {
            a.state = code == 0 ? .done : .failed
            if code != 0 { a.detail = sig == 0 ? "exit \(code)" : String(cString: strsignal(sig)) }
            a.pid = nil
            ActivityFiles.write(a)
        }
        return code
    }

    private static func set(_ args: [String]) -> Int32 {
        let (opts, rest) = parse(args)
        guard let id = rest.first else { return fail() }
        var a = ActivityFiles.read(id) ?? Activity(id: id, title: opts["title"] ?? id, state: .running, app: hostApp, started: Date())
        a.id = id
        if let v = opts["title"] { a.title = v }
        if let v = opts["detail"] { a.detail = v }
        if let v = opts["state"] {
            guard let s = Activity.State(rawValue: v) else { return fail() }
            if a.finished && s == .running { a.started = Date() }
            a.state = s
        }
        if let v = opts["progress"] { a.progress = Double(v).map { min(1, max(0, $0)) } }
        if let v = opts["icon"] { a.icon = v }
        if let v = opts["open"] { a.open = v }
        ActivityFiles.write(a)
        return 0
    }

    private static func ask(_ args: [String]) -> Int32 {
        let (opts, rest) = parse(args)
        guard let id = rest.first, let question = opts["question"] else { return fail() }
        var a = ActivityFiles.read(id) ?? Activity(id: id, title: opts["title"] ?? id, state: .running, app: hostApp, started: Date())
        a.id = id
        if let v = opts["title"] { a.title = v }
        a.question = question
        a.icon = a.icon ?? "questionmark.bubble.fill"
        let answer = waitForAnswer(a, timeout: opts["timeout"].flatMap(Double.init) ?? 600)
        if let answer, answer != "ask" { print(answer) }
        return answer == "allow" ? 0 : answer == "deny" ? 1 : 2
    }

    private static var restoreOnSignal: Activity?
    private static var signalSources: [DispatchSourceSignal] = []

    /// Shows the question and waits for the notch's answer. Gives up (nil) when the time runs
    /// out or the app quits, and puts the activity back to running either way.
    private static func waitForAnswer(_ a: Activity, timeout: TimeInterval) -> String? {
        guard enabled else { return nil }
        let replyURL = ActivityFiles.url(a.id, "reply")
        try? FileManager.default.removeItem(at: replyURL)
        var waiting = a
        waiting.state = .waiting
        ActivityFiles.write(waiting)
        var after = a
        after.state = .running
        after.question = nil
        after.options = nil
        after.multi = nil
        after.header = nil
        after.step = nil
        // Cancelled (e.g. the question was answered elsewhere): don't leave it up in the notch.
        restoreOnSignal = after
        for s in [SIGTERM, SIGINT, SIGHUP] {
            signal(s, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: s, queue: .global())
            src.setEventHandler {
                if let r = restoreOnSignal { ActivityFiles.write(r) }
                exit(128 + s)
            }
            src.resume()
            signalSources.append(src)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var lastCheck = Date()
        var answer: String?
        while Date() < deadline {
            if let r = try? String(contentsOf: replyURL, encoding: .utf8) {
                try? FileManager.default.removeItem(at: replyURL)
                answer = r.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            if Date().timeIntervalSince(lastCheck) > 5 {
                lastCheck = Date()
                if !appRunning || ActivityFiles.read(a.id) == nil { break }  // quit, or dismissed
            }
            usleep(200_000)
        }
        ActivityFiles.write(after)
        return answer
    }

    /// One handler for every agent event we use; see AgentHooks for the wiring. Claude Code and
    /// Codex share a format; Copilot's is close, and names the event in the command.
    private static func agentHook(_ agent: Agent, event named: String?) -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard enabled, let j = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let event = (j["hook_event_name"] as? String) ?? named else { return 0 }
        let session = (j["session_id"] as? String) ?? (j["sessionId"] as? String) ?? "session"
        let id = agent.rawValue + "-" + ActivityFiles.safe(String(session.prefix(12)))
        let folder = folderName(j["cwd"] as? String ?? "")
        let existing = ActivityFiles.read(id)
        var a = existing ?? Activity(id: id, title: "", state: .running, started: Date())
        a.id = id
        a.title = folder.isEmpty || folder == "/" ? agent.name : "\(agent.name) · \(folder)"
        a.icon = agent.icon
        a.app = a.app ?? hostApp ?? agent.app

        switch event {
        case "UserPromptSubmit", "userPromptSubmitted":
            a.state = .running
            a.question = nil
            a.started = Date()
            let prompt = (j["prompt"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
            a.detail = String(prompt.prefix(90))
            ActivityFiles.write(a)
        case "PermissionRequest", "permissionRequest":
            if existing == nil || a.finished { a.started = Date() }
            let tool = (j["tool_name"] as? String) ?? (j["toolName"] as? String) ?? ""
            var args = (j["tool_input"] as? [String: Any]) ?? (j["toolArgs"] as? [String: Any]) ?? [:]
            if args.isEmpty, let text = j["toolArgs"] as? String,
               let parsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] { args = parsed }
            a.question = describe(tool: tool, input: args)
            // The agent waits up to the hook's timeout (600 s); answer a little before that.
            guard let reply = waitForAnswer(a, timeout: 590), reply == "allow" || reply == "deny" else { return 0 }
            var decision: [String: Any] = ["behavior": reply]
            if reply == "deny" { decision["message"] = "The user denied this from the notch (NotchUser)." }
            let out: [String: Any] = agent == .copilot
                ? decision
                : ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
            if let data = try? JSONSerialization.data(withJSONObject: out) { FileHandle.standardOutput.write(data) }
        case "PreToolUse" where (j["tool_name"] as? String) == "AskUserQuestion":
            return answerQuestions(a, input: j["tool_input"] as? [String: Any] ?? [:])
        case "Stop", "agentStop":
            // Codex reads a Stop hook's output as JSON, so say "nothing to add" in JSON.
            if agent == .codex { FileHandle.standardOutput.write(Data("{}".utf8)) }
            guard existing != nil else { return 0 }
            a.state = .done
            a.question = nil
            ActivityFiles.write(a)
        case "SessionEnd", "sessionEnd":
            ActivityFiles.remove(id)
        default:
            break
        }
        return 0
    }

    /// Claude Code's multiple-choice questions, answered in the notch one after another. Any
    /// question left unanswered (time, "answer in the terminal") hands all of them back to the terminal.
    private static func answerQuestions(_ a: Activity, input: [String: Any]) -> Int32 {
        guard let questions = input["questions"] as? [[String: Any]], !questions.isEmpty else { return 0 }
        let deadline = Date().addingTimeInterval(590)  // the hook's timeout is 600 s
        var answers: [String: String] = [:]
        for (n, q) in questions.enumerated() {
            guard let text = q["question"] as? String else { return 0 }
            var ask = a
            ask.question = text
            ask.options = (q["options"] as? [[String: Any]] ?? []).compactMap { o in
                (o["label"] as? String).map { Activity.Option(label: $0, description: o["description"] as? String) }
            }
            ask.multi = q["multiSelect"] as? Bool
            ask.header = q["header"] as? String
            ask.step = questions.count > 1 ? "\(n + 1)/\(questions.count)" : nil
            guard ask.options?.isEmpty == false,
                  let reply = waitForAnswer(ask, timeout: deadline.timeIntervalSinceNow),
                  let labels = (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String], !labels.isEmpty
            else { return 0 }
            answers[text] = labels.joined(separator: ", ")  // how Claude Code expects multi-select answers
        }
        var updated = input
        updated["answers"] = answers
        let out: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated,
        ]]
        if let data = try? JSONSerialization.data(withJSONObject: out) { FileHandle.standardOutput.write(data) }
        return 0
    }

    /// "Bash: npm test", "Edit: main.swift"…
    private static func describe(tool: String, input: [String: Any]) -> String {
        let subject: String? = (input["command"] as? String)
            ?? (input["file_path"] as? String).map(folderName)
            ?? (input["url"] as? String) ?? (input["pattern"] as? String) ?? (input["description"] as? String)
        let line = subject.map { "\(tool): \($0)" } ?? tool
        return String(line.replacingOccurrences(of: "\n", with: " ").prefix(140))
    }
}

/// Builds, tests, installs and deploys started anywhere (a terminal, an editor, an agent) show up
/// on their own: every few seconds the process list is checked for well-known dev tools.
/// Nothing to set up, and nothing runs while the add-on is off.
final class DevTasks {
    private struct Task { var activity: Activity; var start: Int }
    private var timer: Timer?
    private var tracked: [pid_t: Task] = [:]
    private let queue = DispatchQueue(label: "notch.devtasks", qos: .utility)

    /// Commands that are worth watching, and which of their subcommands count (empty: all of them).
    private static let tools: [String: Set<String>] = [
        "xcodebuild": [], "swift-build": [], "swift-test": [], "make": [], "ninja": [], "fastlane": [],
        "cargo": ["build", "b", "test", "t", "check", "clippy", "install", "bench"],
        "go": ["build", "test", "install", "generate", "vet"],
        "cmake": ["--build"], "bazel": ["build", "test"], "bazelisk": ["build", "test"],
        "npm": ["install", "i", "ci", "test", "t", "run", "run-script", "publish", "update"],
        "pnpm": ["install", "i", "add", "test", "t", "run", "build", "publish", "update"],
        "yarn": ["install", "add", "test", "run", "build", "publish"],
        "bun": ["install", "i", "add", "test", "run", "build"],
        "pip": ["install"], "pip3": ["install"], "uv": ["sync", "pip"], "pytest": [], "poetry": ["install", "build"],
        "brew": ["install", "upgrade", "reinstall", "update"], "pod": ["install", "update"],
        "docker": ["build", "compose", "push", "pull"], "gradle": [], "gradlew": [], "mvn": [], "mvnw": [],
        "vercel": [], "netlify": ["deploy", "build"], "firebase": ["deploy"], "fly": ["deploy"], "flyctl": ["deploy"],
        "eas": ["build", "submit", "update"], "terraform": ["apply", "plan", "init"], "gh": ["run"],
        "git": ["clone", "push", "pull", "fetch"], "rsync": [], "scp": [],
    ]
    /// Scripts run through these, so the tool is the script's name (`node …/npm-cli.js run build`).
    private static let interpreters: Set<String> = ["node", "python", "python3", "ruby", "bash", "sh", "zsh", "java"]
    /// `npm run dev` and friends serve forever; only one-shot scripts are activities.
    private static let scriptWords = ["build", "test", "lint", "check", "deploy", "release", "bundle", "compile", "e2e", "export"]

    func update(_ on: Bool) {
        guard on != (timer != nil) else { return }
        // Whatever an earlier run (or this one, now being turned off) left behind is stale.
        queue.async {
            self.tracked.removeAll()
            Self.removeLeftovers()
        }
        if on {
            queue.async { self.scan() }
            let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.queue.async { self?.scan() } }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func removeLeftovers() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: ActivityFiles.dir.path)) ?? []
        for f in files where f.hasPrefix("auto-") && f.hasSuffix(".json") { ActivityFiles.remove(String(f.dropLast(5))) }
    }

    private func scan() {
        let now = Date()
        var found: [pid_t: (args: [String], start: Int, ppid: pid_t)] = [:]
        // Cheapest check first: one call for the name, the rest only for the few that could match.
        for pid in Self.pids() {
            let name = Self.name(pid)
            // (Apple's make calls itself gnumake; the arguments say "make".)
            guard Self.tools[name] != nil || Self.interpreters.contains(name) || name == "gnumake",
                  let info = Self.bsdInfo(pid), let args = Self.arguments(pid), Self.match(args) != nil else { continue }
            found[pid] = (args, info.start, info.ppid)
        }
        // A tool started by another one (make → make, brew.sh → ruby brew.rb) is the same task,
        // and so is anything NotchUser itself runs (`NotchUser run …` reports on its own).
        for (pid, p) in found {
            let parent = p.ppid
            if found[parent] != nil || Self.name(parent) == "NotchUser" { found[pid] = nil }
        }
        for (pid, p) in found where tracked[pid]?.start != p.start {
            // Quick ones aren't worth a flash in the notch.
            guard now.timeIntervalSince1970 - Double(p.start) >= 3, let (title, icon) = Self.match(p.args) else { continue }
            let a = Activity(id: "auto-\(pid)", title: title, detail: Self.folder(pid), state: .running, icon: icon,
                             started: Date(timeIntervalSince1970: Double(p.start)))
            ActivityFiles.write(a)
            tracked[pid] = Task(activity: a, start: p.start)
        }
        for (pid, t) in tracked where found[pid]?.start != t.start {
            // Not our child, so how it ended is unknown: it's simply finished.
            var a = t.activity
            a.state = .done
            if ActivityFiles.read(a.id) != nil { ActivityFiles.write(a) }
            tracked[pid] = nil
        }
    }

    /// The task's title and icon, or nil when it isn't one we follow.
    private static func match(_ args: [String]) -> (String, String)? {
        // npm and others rename their process to the whole command ("npm run build").
        var args = args.filter { !$0.isEmpty }
        if let first = args.first, first.contains(" "), !first.hasPrefix("/") {
            args = first.split(separator: " ").map(String.init) + args.dropFirst()
        }
        guard var i = args.indices.first else { return nil }
        var tool = base(args[i])
        if interpreters.contains(tool) {
            // The script: the first argument that isn't a flag.
            guard let s = args.indices.dropFirst().first(where: { !args[$0].hasPrefix("-") }) else { return nil }
            i = s
            tool = base(args[i])
        }
        guard let sub = tools[tool] else { return nil }
        var rest: [String] = []
        var j = i + 1
        while j < args.count {
            let a = args[j]
            if ["-C", "-c", "-f", "--file", "--prefix", "--project-directory"].contains(a) { j += 2; continue }  // an option and its value
            if !a.hasPrefix("-") || a == "--build" { rest.append(a) }
            j += 1
        }
        if !sub.isEmpty {
            guard let first = rest.first, sub.contains(first) else { return nil }
            if ["run", "run-script"].contains(first) {
                guard let script = rest.dropFirst().first, scriptWords.contains(where: script.lowercased().contains) else { return nil }
            }
            if tool == "docker", first == "compose", !rest.contains("build") { return nil }
            if tool == "gh", rest.dropFirst().first != "watch" { return nil }
        }
        let words = ([tool] + rest.prefix(2)).map { $0.count > 40 ? base($0) : $0 }
        let all = rest.joined(separator: " ")
        let icon: String
        if all.contains("test") || tool == "pytest" { icon = "testtube.2" }
        else if ["install", "i", "ci", "add", "update", "upgrade", "sync", "pull", "clone", "fetch"].contains(rest.first ?? "") { icon = "shippingbox.fill" }
        else if all.contains("deploy") || all.contains("push") || all.contains("publish") || ["vercel", "eas", "terraform"].contains(tool) { icon = "icloud.and.arrow.up.fill" }
        else { icon = "hammer.fill" }
        return (words.joined(separator: " "), icon)
    }

    /// "…/npm-cli.js" → "npm", "brew.sh" → "brew".
    private static func base(_ path: String) -> String {
        var b = (path as NSString).lastPathComponent
        for suffix in ["-cli.js", ".cjs", ".mjs", ".js", ".sh", ".rb", ".py"] where b.hasSuffix(suffix) {
            b = String(b.dropLast(suffix.count))
            break
        }
        return b
    }

    // MARK: Process list (libproc; own processes need no permission)

    /// Only the user's own processes: system daemons never run builds.
    private static func pids() -> [pid_t] {
        let uid = UInt32(getuid())
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard bytes > 0 else { return [] }
        var list = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 64)
        let got = proc_listpids(UInt32(PROC_UID_ONLY), uid, &list, Int32(list.count * MemoryLayout<pid_t>.size))
        return Array(list.prefix(Int(max(0, got)) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    private static func name(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    private static func bsdInfo(_ pid: pid_t) -> (ppid: pid_t, start: Int)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return (pid_t(info.pbi_ppid), Int(info.pbi_start_tvsec))
    }

    private static func folder(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// argv of a process: KERN_PROCARGS2 is argc, the executable path, then the arguments.
    private static func arguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size, buf[i] != 0 { i += 1 }  // executable path
        while i < size, buf[i] == 0 { i += 1 }  // padding
        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}

/// The coding agents NotchUser plugs into, each through its own hooks.
enum Agent: String, CaseIterable, Identifiable {
    case claude, codex, copilot
    var id: String { rawValue }
    var name: String { [.claude: "Claude Code", .codex: "Codex", .copilot: "Copilot"][self]! }
    var settingsName: String { self == .copilot ? "VS Code · Copilot" : name }
    var icon: String { [.claude: "sparkle", .codex: "chevron.left.forwardslash.chevron.right", .copilot: "curlybraces"][self]! }
    var color: Color { [.claude: Color.orange, .codex: Color(white: 0.85), .copilot: Color(red: 0.25, green: 0.6, blue: 1)][self]! }
    /// Brought forward on click when the hook can't tell which app ran it.
    var app: String? { [.codex: "com.openai.chat", .copilot: "com.microsoft.VSCode"][self] }
}

/// Adds (or removes) NotchUser's hooks in each agent's settings, leaving everything else alone.
enum AgentHooks {
    private typealias Event = (name: String, timeout: Int?, matcher: String?)
    private static func events(_ agent: Agent) -> [Event] {
        var list: [Event] = [("UserPromptSubmit", nil, nil), ("PermissionRequest", 600, nil), ("Stop", nil, nil), ("SessionEnd", nil, nil)]
        // Claude Code lets a hook answer its multiple-choice questions.
        if agent == .claude { list.append(("PreToolUse", 600, "AskUserQuestion")) }
        return list
    }
    private static var binary: String { Bundle.main.executablePath ?? "/Applications/NotchUser.app/Contents/MacOS/NotchUser" }

    /// Each agent's own variable for moving its settings folder is followed.
    static func configURL(_ agent: Agent) -> URL {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        func dir(_ variable: String, _ fallback: String) -> URL {
            env[variable].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(fallback)
        }
        switch agent {
        case .claude: return dir("CLAUDE_CONFIG_DIR", ".claude").appendingPathComponent("settings.json")
        case .codex: return dir("CODEX_HOME", ".codex").appendingPathComponent("hooks.json")
        case .copilot: return dir("COPILOT_HOME", ".copilot").appendingPathComponent("hooks/notchuser.json")
        }
    }

    private static func command(_ agent: Agent, _ event: String) -> String {
        switch agent {
        case .claude: return "\"\(binary)\" claude-hook"  // what earlier versions installed
        case .codex: return "\"\(binary)\" agent-hook codex"
        case .copilot: return "\"\(binary)\" agent-hook copilot \(event)"
        }
    }

    private static func isOurs(_ handler: Any) -> Bool {
        let h = handler as? [String: Any] ?? [:]
        let cmd = (h["command"] as? String) ?? (h["bash"] as? String) ?? ""
        return cmd.contains("NotchUser") && (cmd.hasSuffix("claude-hook") || cmd.contains(" agent-hook "))
    }

    struct Unreadable: Error {}

    private static func load(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }  // no file yet
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Unreadable() }
        return root
    }

    static func installed(_ agent: Agent) -> Bool {
        let url = configURL(agent)
        if agent == .copilot { return FileManager.default.fileExists(atPath: url.path) }
        guard let hooks = (try? load(url))?["hooks"] as? [String: Any] else { return false }
        return events(agent).allSatisfy { e in
            ((hooks[e.name] as? [[String: Any]]) ?? []).contains { (($0["hooks"] as? [Any]) ?? []).contains(where: isOurs) }
        }
    }

    /// Connected by an earlier version, which had fewer hooks: bring it up to date.
    static func upgrade() {
        for agent in Agent.allCases where agent != .copilot && !installed(agent) {
            guard let hooks = (try? load(configURL(agent)))?["hooks"] as? [String: Any] else { continue }
            let ours = hooks.values.contains { groups in
                ((groups as? [[String: Any]]) ?? []).contains { (($0["hooks"] as? [Any]) ?? []).contains(where: isOurs) }
            }
            if ours { try? set(agent, true) }
        }
    }

    static var anyInstalled: Bool { Agent.allCases.contains(where: installed) }

    static func set(_ agent: Agent, _ on: Bool) throws {
        let url = configURL(agent)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if agent == .copilot {
            // Copilot reads every file in its hooks folder, so NotchUser simply has its own.
            guard on else { try? fm.removeItem(at: url); return }
            var hooks: [String: Any] = [:]
            for e in events(agent) {
                hooks[e.name] = [["type": "command", "bash": command(agent, e.name), "timeoutSec": e.timeout ?? 10]]
            }
            try write(["version": 1, "hooks": hooks], to: url)
            return
        }
        var root = try load(url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for e in events(agent) {
            // Our old entries go first (an earlier install path, or turning it off).
            var groups: [[String: Any]] = ((hooks[e.name] as? [[String: Any]]) ?? []).compactMap { g in
                let handlers = (g["hooks"] as? [Any]) ?? []
                let kept = handlers.filter { !isOurs($0) }
                if kept.isEmpty && !handlers.isEmpty { return nil }
                var g = g
                g["hooks"] = kept
                return g
            }
            if on {
                var h: [String: Any] = ["type": "command", "command": command(agent, e.name)]
                if let t = e.timeout { h["timeout"] = t }
                var group: [String: Any] = ["hooks": [h]]
                if let m = e.matcher { group["matcher"] = m }
                groups.append(group)
            }
            hooks[e.name] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        let backup = url.appendingPathExtension("notchuser-backup")
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) {
            try? fm.copyItem(at: url, to: backup)
        }
        try write(root, to: url)
    }

    private static func write(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try data.write(to: url, options: .atomic)
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
    static func readingOrder(_ observations: [VNRecognizedTextObservation]) -> String {
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
    /// Each shortcut has its own ID: every handler sees every press and only answers its own.
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.id == me.id else { return OSStatus(eventNotHandledErr) }
            me.action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4E555352), id: id),
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

// MARK: - Haptics

/// Pulses in the Force Touch trackpad. macOS only plays them while a finger rests on it,
/// which makes them a quiet way to say "done": no sound, no window.
enum Haptics {
    enum Pattern { case tap, success, failure }

    static func play(_ p: Pattern) {
        guard Settings.shared.hapticsEnabled else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        let beats: [(delay: Double, pattern: NSHapticFeedbackManager.FeedbackPattern)]
        switch p {
        case .tap: beats = [(0, .generic)]
        case .success: beats = [(0, .levelChange), (0.14, .levelChange)]
        case .failure: beats = [(0, .generic), (0.11, .generic), (0.22, .generic)]
        }
        for b in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + b.delay) { performer.perform(b.pattern, performanceTime: .now) }
        }
    }
}

// MARK: - Edge glow

/// A soft light around the edges of the screen for a moment, e.g. when a command finishes.
/// One transparent window that ignores the mouse; Core Animation plays the flash.
final class EdgeGlow {
    static let shared = EdgeGlow()
    private var window: NSWindow?
    private let border = CAShapeLayer()

    func flash(_ color: NSColor, on screen: NSScreen? = nil) {
        guard Settings.shared.edgeGlowEnabled,
              let s = screen ?? NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main else { return }
        let w = window ?? makeWindow()
        window = w
        w.setFrame(s.frame, display: false)
        let bounds = CGRect(origin: .zero, size: s.frame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerWidth: 12, cornerHeight: 12, transform: nil)
        border.strokeColor = color.cgColor
        border.shadowColor = color.cgColor
        border.opacity = 0
        CATransaction.commit()
        w.orderFrontRegardless()
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0.0, 1.0, 0.7, 1.0, 0.0]
        a.keyTimes = [0, 0.15, 0.4, 0.55, 1]
        a.duration = 1.8
        border.add(a, forKey: "flash")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
            // A newer flash may still be playing.
            if self?.border.animation(forKey: "flash") == nil { self?.window?.orderOut(nil) }
        }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let v = NSView()
        v.wantsLayer = true
        border.fillColor = nil
        border.lineWidth = 5
        border.shadowRadius = 18
        border.shadowOpacity = 1
        border.shadowOffset = .zero
        border.opacity = 0
        v.layer?.addSublayer(border)
        w.contentView = v
        return w
    }
}

// MARK: - System volume

/// The volume of the current output (speakers, headphones), as the volume keys change it.
enum SystemVolume {
    private static func outputDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    /// The virtual main volume covers devices that only have a volume per channel.
    private static var volumeSelector: AudioObjectPropertySelector {
        AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    }

    static func get() -> Float? {
        guard let d = outputDevice() else { return nil }
        var a = address(volumeSelector)
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr else { return nil }
        return isMuted(d) ? 0 : v
    }

    /// Returns the volume that was set, nil when this output has no volume (e.g. HDMI).
    @discardableResult
    static func set(_ value: Float) -> Float? {
        guard let d = outputDevice() else { return nil }
        var a = address(volumeSelector)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(d, &a, &settable) == noErr, settable.boolValue else { return nil }
        var v = Float32(min(max(value, 0), 1))
        guard AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr else { return nil }
        setMuted(d, v == 0)
        return v
    }

    private static func isMuted(_ d: AudioObjectID) -> Bool {
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(d, &a) else { return false }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(d, &a, 0, nil, &size, &m)
        return m != 0
    }

    private static func setMuted(_ d: AudioObjectID, _ muted: Bool) {
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(d, &a), isMuted(d) != muted else { return }
        var m: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }

    static func icon(_ v: Float) -> String {
        v <= 0 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

// MARK: - Microphone

/// Whether any app is using the microphone (shown as a dot, like the system's privacy light),
/// and a mute that works in every app at once.
final class MicMonitor: ObservableObject {
    @Published private(set) var inUse = false
    @Published private(set) var muted = false
    private var timer: Timer?
    /// For inputs without a mute switch: the volume to put back when unmuting.
    private var savedVolume: Float32?

    var shown: Bool { Settings.shared.micEnabled && (inUse || muted) }

    func update() {
        timer?.invalidate()
        timer = nil
        guard Settings.shared.micEnabled else {
            if inUse { inUse = false }
            return
        }
        refresh()
        // Once a second is plenty for a status light, and costs nothing measurable.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func inputDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = address(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private func refresh() {
        guard let d = inputDevice() else { return }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = address(kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(d, &a, 0, nil, &size, &running)
        let use = running != 0
        if use != inUse { inUse = use }
        let m = isMuted(d)
        if m != muted { muted = m }
    }

    private func isMuted(_ d: AudioObjectID) -> Bool {
        if savedVolume != nil { return true }
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(d, &a) else { return false }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(d, &a, 0, nil, &size, &m)
        return m != 0
    }

    /// Mutes or unmutes the current input for every app. Returns the new state, nil if this input can't.
    func toggle() -> Bool? {
        guard let d = inputDevice() else { return nil }
        let target = !isMuted(d)
        var settable: DarwinBoolean = false
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        if savedVolume == nil, AudioObjectHasProperty(d, &a),
           AudioObjectIsPropertySettable(d, &a, &settable) == noErr, settable.boolValue {
            var v: UInt32 = target ? 1 : 0
            guard AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr else { return nil }
        } else {
            // No mute switch: the input volume goes all the way down, and back up afterwards.
            var va = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput)
            guard AudioObjectHasProperty(d, &va), AudioObjectIsPropertySettable(d, &va, &settable) == noErr,
                  settable.boolValue else { return nil }
            var size = UInt32(MemoryLayout<Float32>.size)
            if target {
                var current = Float32(1)
                AudioObjectGetPropertyData(d, &va, 0, nil, &size, &current)
                var zero = Float32(0)
                guard AudioObjectSetPropertyData(d, &va, 0, nil, size, &zero) == noErr else { return nil }
                savedVolume = current
            } else {
                var back = savedVolume ?? 1
                savedVolume = nil
                AudioObjectSetPropertyData(d, &va, 0, nil, size, &back)
            }
        }
        muted = target
        return target
    }
}

// MARK: - Lid angle

/// The hinge sensor in recent MacBooks: an HID device Apple doesn't document, which reports
/// the lid angle in degrees. Read twice a second, only while something needs it.
final class LidSensor: ObservableObject {
    @Published private(set) var angle: Double?
    @Published private(set) var available = true
    var onLowered: (() -> Void)?
    var onRaised: (() -> Void)?
    /// Settings shows the live angle while its pane is open.
    var watching = false { didSet { update() } }
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var missing = false
    private var timer: Timer?
    private var lowered = false

    func update() {
        let wanted = (Settings.shared.lidPauseEnabled || watching) && !missing
        if wanted && timer == nil {
            tick()
            guard !missing else { return }
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.15
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !wanted, let t = timer {
            t.invalidate()
            timer = nil
            lowered = false
        }
    }

    private func open() -> IOHIDDevice? {
        if let device { return device }
        guard !missing else { return nil }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104,
                                    kIOHIDPrimaryUsagePageKey: 0x0020, kIOHIDPrimaryUsageKey: 0x008A]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, let d = devices.first,
              IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            // Not on this Mac: stop looking.
            missing = true
            available = false
            return nil
        }
        manager = m
        device = d
        return d
    }

    private func read() -> Double? {
        guard let d = open() else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        guard IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess, length >= 3 else { return nil }
        return Double(UInt16(report[2]) << 8 | UInt16(report[1]))
    }

    private func tick() {
        let a = read()
        if a != angle { angle = a }
        if missing, let t = timer { t.invalidate(); timer = nil }
        guard let a, Settings.shared.lidPauseEnabled else { return }
        let limit = Settings.shared.lidThreshold
        // A few degrees of slack, so holding the lid near the line doesn't flip it back and forth.
        if !lowered && a < limit {
            lowered = true
            onLowered?()
        } else if lowered && a > limit + 8 {
            lowered = false
            onRaised?()
        }
    }
}

// MARK: - Shelf quick actions

/// Small jobs on a parked file. The result is saved next to the original (or in Downloads)
/// and parked on the shelf too, ready to be dragged out.
enum QuickAction {
    case jpeg, png, half, imageText, compressVideo

    var title: String {
        switch self {
        case .jpeg: return L("toJPEG")
        case .png: return L("toPNG")
        case .half: return L("halfSize")
        case .imageText: return L("imageText")
        case .compressVideo: return L("compressVideo")
        }
    }

    var symbol: String {
        switch self {
        case .jpeg, .png: return "arrow.triangle.2.circlepath"
        case .half: return "arrow.down.right.and.arrow.up.left"
        case .imageText: return "text.viewfinder"
        case .compressVideo: return "film"
        }
    }

    static func available(for e: ShelfEntry) -> [QuickAction] {
        guard e.kind == .file, let type = UTType(filenameExtension: (e.value as NSString).pathExtension) else { return [] }
        if type.conforms(to: .image) {
            var list: [QuickAction] = []
            if !type.conforms(to: .jpeg) { list.append(.jpeg) }
            if !type.conforms(to: .png) { list.append(.png) }
            return list + [.half, .imageText]
        }
        if type.conforms(to: .movie) { return [.compressVideo] }
        return []
    }
}

enum QuickActions {
    /// How a job ended, shown in the notch.
    static var onResult: ((NotchState.Toast) -> Void)?
    private static let queue = DispatchQueue(label: "notch.quickactions", qos: .userInitiated)

    private enum Outcome { case file(URL), text(String), failed(String?) }

    static func run(_ action: QuickAction, on entry: ShelfEntry, shelf: Shelf) {
        let src = URL(fileURLWithPath: entry.value)
        let finish = completion(shelf)
        // Localized here, on the main thread.
        let converted = L("suffix.converted"), halfName = L("suffix.half")
        let compressed = L("suffix.compressed"), noText = L("noTextFound")
        if action == .compressVideo {
            onResult?(.init(icon: "film", title: L("working"), detail: src.lastPathComponent, ok: true))
            compressVideo(src, suffix: compressed, finish)
            return
        }
        queue.async {
            switch action {
            case .jpeg: finish(convert(src, to: .jpeg, suffix: converted))
            case .png: finish(convert(src, to: .png, suffix: converted))
            case .half: finish(half(src, suffix: halfName))
            case .imageText: finish(imageText(src, none: noText))
            case .compressVideo: break
            }
        }
    }

    /// One ZIP with every file given, next to the first one.
    static func zip(_ entries: [ShelfEntry], shelf: Shelf) {
        let urls = entries.filter { $0.kind == .file }.map { URL(fileURLWithPath: $0.value) }
        guard let first = urls.first else { return }
        let finish = completion(shelf)
        let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : L("archive")
        let out = output(base: name, in: first.deletingLastPathComponent(), ext: "zip")
        queue.async {
            let p = Process()
            if urls.count == 1 {
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path]
            } else {
                let parent = first.deletingLastPathComponent()
                let sameFolder = urls.allSatisfy { $0.deletingLastPathComponent().path == parent.path }
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                p.currentDirectoryURL = parent
                // Same folder: keep the names (and folders) as they are; otherwise just the files.
                p.arguments = sameFolder
                    ? ["-q", "-r", out.path] + urls.map { "./" + $0.lastPathComponent }
                    : ["-q", "-r", "-j", out.path] + urls.map(\.path)
            }
            do {
                try p.run()
                p.waitUntilExit()
                finish(p.terminationStatus == 0 ? .file(out) : .failed(nil))
            } catch {
                finish(.failed(error.localizedDescription))
            }
        }
    }

    private static func completion(_ shelf: Shelf) -> (Outcome) -> Void {
        { outcome in
            DispatchQueue.main.async {
                switch outcome {
                case .file(let url):
                    shelf.add(ShelfEntry(kind: .file, value: url.path))
                    onResult?(.init(icon: "checkmark.circle.fill", title: L("actionDone"),
                                    detail: L("actionDoneHint", url.lastPathComponent), ok: true))
                case .text(let text):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    onResult?(.init(icon: "doc.on.clipboard.fill", title: L("textCopied"),
                                    detail: String(text.replacingOccurrences(of: "\n", with: " ").prefix(90)), ok: true))
                case .failed(let why):
                    onResult?(.init(icon: "exclamationmark.triangle.fill", title: L("actionFailed"), detail: why, ok: false))
                }
            }
        }
    }

    /// "photo (half).jpg" next to the original, or in Downloads when that folder can't be written to.
    private static func output(base: String, in folder: URL, ext: String) -> URL {
        let fm = FileManager.default
        var dir = folder
        if !fm.isWritableFile(atPath: dir.path) {
            dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        }
        var url = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    private static func output(for src: URL, suffix: String, ext: String) -> URL {
        output(base: src.deletingPathExtension().lastPathComponent + " (\(suffix))", in: src.deletingLastPathComponent(), ext: ext)
    }

    /// The full-size image, turned upright (photos store their rotation separately).
    private static func upright(_ src: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max(w, h)]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    private static func write(_ image: CGImage, to out: URL, type: UTType, properties: [CFString: Any] = [:]) -> Outcome {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { return .failed(nil) }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        return CGImageDestinationFinalize(dest) ? .file(out) : .failed(nil)
    }

    private static func convert(_ src: URL, to type: UTType, suffix: String) -> Outcome {
        guard var image = upright(src) else { return .failed(nil) }
        // JPEG has no transparency: put see-through images on white instead of black.
        if type == .jpeg, hasAlpha(image), let flat = flatten(image) { image = flat }
        return write(image, to: output(for: src, suffix: suffix, ext: type.preferredFilenameExtension ?? "img"), type: type,
                     properties: [kCGImageDestinationLossyCompressionQuality: 0.88])
    }

    private static func half(_ src: URL, suffix: String) -> Outcome {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return .failed(nil) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max(1, max(w, h) / 2)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return .failed(nil) }
        // Same format when macOS can write it (not WebP, for one), PNG otherwise.
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        let sourceType = CGImageSourceGetType(source).map { $0 as String }
        let keep = sourceType.map { writable.contains($0) } ?? false
        let type = keep ? (sourceType.flatMap { UTType($0) } ?? .png) : .png
        let ext = keep && !src.pathExtension.isEmpty ? src.pathExtension : (type.preferredFilenameExtension ?? "png")
        return write(image, to: output(for: src, suffix: suffix, ext: ext), type: type,
                     properties: [kCGImageDestinationLossyCompressionQuality: 0.88])
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func flatten(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(r)
        ctx.draw(image, in: r)
        return ctx.makeImage()
    }

    private static func imageText(_ src: URL, none: String) -> Outcome {
        guard let image = upright(src) else { return .failed(nil) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US", "es-ES"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let text = ScreenText.readingOrder(request.results ?? [])
        return text.isEmpty ? .failed(none) : .text(text)
    }

    private static func compressVideo(_ src: URL, suffix: String, _ finish: @escaping (Outcome) -> Void) {
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: src), presetName: AVAssetExportPreset1920x1080) else {
            finish(.failed(nil))
            return
        }
        let out = output(for: src, suffix: suffix, ext: "mp4")
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            finish(export.status == .completed ? .file(out) : .failed(export.error?.localizedDescription))
        }
    }
}

// MARK: - Synced lyrics

/// Lyrics timed to the song, from LRCLIB (a free, open lyrics database). Each line is shown when
/// it's sung: one timer set for the next line, not a clock ticking all the time.
final class Lyrics: ObservableObject {
    static let shared = Lyrics()
    struct Line: Codable, Equatable { var time: Double; var text: String }

    /// `plain`: lyrics without times, spread over the song so they still scroll along.
    enum Status { case idle, loading, missing, ready, plain }
    /// What's being sung right now; nil between verses, in instrumentals, or without lyrics.
    @Published private(set) var line: String?
    @Published private(set) var index: Int?
    @Published private(set) var lines: [Line] = []
    @Published private(set) var status = Status.idle
    /// Something is showing lyrics (the player's lyrics view): only then are they fetched.
    var viewing = false { didSet { if viewing != oldValue { sync() } } }
    var onChange: (() -> Void)?
    private weak var np: NowPlaying?
    private var key = ""
    private var watch: AnyCancellable?
    private var timer: Timer?
    private var fetching: Task<Void, Never>?
    /// What LRCLIB had for a song: timed lines, or plain ones (`synced` false); none at all is [].
    struct Found: Codable { var synced: Bool; var lines: [Line] }
    /// Songs already asked about this session.
    private var memory: [String: Found] = [:]
    private static let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchUser/lyrics", isDirectory: true)

    func attach(_ np: NowPlaying) {
        self.np = np
        // Every play, pause, seek or song change shows up as a change in NowPlaying.
        watch = np.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.sync() }
        NotificationCenter.default.addObserver(forName: Settings.lyricsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }
        sync()
    }

    func sync() {
        let wanted = Settings.shared.lyricsEnabled && (viewing || Settings.shared.lyricsClosed)
        guard wanted, let np, np.hasMedia, !np.title.isEmpty else {
            timer?.invalidate()
            timer = nil
            set(nil, at: nil)
            return
        }
        let k = np.title + "\n" + np.artist
        if k != key {
            key = k
            lines = []
            set(nil, at: nil)
            load(title: np.title, artist: np.artist, duration: np.duration, key: k)
        }
        schedule()
    }

    /// Shows the line for the current position and sets a timer for the next one.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard let np, !lines.isEmpty else { set(nil, at: nil); return }
        let pos = np.currentPosition(at: Date()) + 0.12  // a hair early reads as on time
        let i = lines.lastIndex { $0.time <= pos }
        set(i.map { lines[$0].text }.flatMap { $0.isEmpty ? nil : $0 }, at: i)
        guard np.isPlaying else { return }
        let next = i.map { $0 + 1 } ?? 0
        guard next < lines.count else { return }
        let t = Timer(timeInterval: max(0.05, lines[next].time - pos), repeats: false) { [weak self] _ in self?.schedule() }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func set(_ s: String?, at i: Int?) {
        if index != i { index = i }
        guard line != s else { return }
        line = s
        onChange?()
    }

    // MARK: Fetching

    private func load(title: String, artist: String, duration: Double, key k: String) {
        fetching?.cancel()
        if let known = memory[k] ?? Self.readCache(k) {
            memory[k] = known
            use(known, duration: duration)
            return
        }
        status = .loading
        let (t, a) = Self.clean(title: title, artist: artist)
        fetching = Task {
            let (found, failed) = await Self.fetch(title: t, artist: a, duration: duration)
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async {
                if failed { Lyrics.shared.retry(k) } else { Lyrics.shared.store(found, for: k) }
            }
        }
    }

    private var retries: [String: Int] = [:]

    /// The server was busy or the Mac offline: try again in a while (a few times), for the same song only.
    private func retry(_ k: String) {
        guard key == k else { return }
        let n = retries[k, default: 0] + 1
        retries[k] = n
        guard n <= 3 else { status = .missing; return }
        status = .loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 20 * Double(n)) { [weak self] in
            guard let self, self.key == k, self.lines.isEmpty, let np = self.np else { return }
            self.load(title: np.title, artist: np.artist, duration: np.duration, key: k)
        }
    }

    private func store(_ found: Found?, for k: String) {
        let f = found ?? Found(synced: true, lines: [])
        memory[k] = f
        if found != nil { Self.writeCache(k, f) }
        guard key == k else { return }
        use(f, duration: np?.duration ?? 0)
        schedule()
    }

    /// Plain lyrics get times spread over the song (after a short intro), so they scroll along
    /// with it; the view says they aren't synced.
    private func use(_ f: Found, duration: Double) {
        if f.synced || f.lines.isEmpty || duration <= 0 {
            lines = f.synced ? f.lines : []
            status = lines.isEmpty ? .missing : .ready
            return
        }
        let start = min(12, duration * 0.08), span = max(1, duration * 0.92 - start)
        lines = f.lines.enumerated().map { i, l in
            Line(time: start + span * Double(i) / Double(f.lines.count), text: l.text)
        }
        status = .plain
    }

    /// The JSON answer; `failed` when the server couldn't answer (as opposed to "not found").
    private static func request(_ path: String, _ items: [URLQueryItem]) async -> (json: Any?, failed: Bool) {
        var c = URLComponents(string: "https://lrclib.net/api/" + path)!
        c.queryItems = items
        guard let url = c.url else { return (nil, false) }
        var r = URLRequest(url: url, timeoutInterval: 8)
        // LRCLIB asks apps to say who they are.
        r.setValue("NotchUser (https://github.com/Magnumja/NotchUser)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: r) else { return (nil, true) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { return (nil, code >= 500 || code == 429) }
        return (try? JSONSerialization.jsonObject(with: data), false)
    }

    /// The exact match first; then a search, taking the closest length.
    private static func fetch(title: String, artist: String, duration: Double) async -> (Found?, Bool) {
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if duration > 0 {
            let exact = items + [URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
            let exactAnswer = await request("get", exact)
            if exactAnswer.failed { return (nil, true) }
            if let j = exactAnswer.json as? [String: Any], let found = found(in: j) { return (found, false) }
        }
        let searched = await request("search", items)
        guard let results = searched.json as? [[String: Any]] else { return (nil, searched.failed) }
        func distance(_ r: [String: Any]) -> Double { abs(((r["duration"] as? Double) ?? 0) - duration) }
        let close = results.filter { duration <= 0 || distance($0) <= 5 }.sorted { distance($0) < distance($1) }
        // Timed lyrics from any close match win over plain ones.
        let synced = close.lazy.compactMap { r -> Found? in
            guard let lrc = r["syncedLyrics"] as? String, !lrc.isEmpty else { return nil }
            return found(in: r)
        }.first
        return (synced ?? close.lazy.compactMap { found(in: $0) }.first, false)
    }

    private static func found(in r: [String: Any]) -> Found? {
        if let lrc = r["syncedLyrics"] as? String {
            let timed = parse(lrc)
            if !timed.isEmpty { return Found(synced: true, lines: timed) }
        }
        guard let plain = r["plainLyrics"] as? String else { return nil }
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : Found(synced: false, lines: lines.map { Line(time: 0, text: $0) })
    }

    /// "[01:23.45] words" (a line can carry several times).
    static func parse(_ lrc: String) -> [Line] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var out: [Line] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(raw)
            let ns = s as NSString
            let matches = stamp.matches(in: s, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                out.append(Line(time: min * 60 + sec, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Videos and streams dress titles up: "Artist - Song (Official Video)", "Artist - Topic".
    static func clean(title: String, artist: String) -> (String, String) {
        var t = title, a = artist
        if a.hasSuffix(" - Topic") { a = String(a.dropLast(8)) }
        let noise = try! NSRegularExpression(
            pattern: #"\s*[\(\[][^\)\]]*(official|video|lyric|letra|audio|visualizer|clipe|hd|4k|remaster)[^\)\]]*[\)\]]"#,
            options: .caseInsensitive)
        t = noise.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        if let dash = t.range(of: " - ") {
            let left = String(t[..<dash.lowerBound]), right = String(t[dash.upperBound...])
            let channel = a.lowercased().replacingOccurrences(of: "vevo", with: "").trimmingCharacters(in: .whitespaces)
            if a.isEmpty || left.lowercased().contains(channel) || channel.contains(left.lowercased()) {
                // A browser tab: "Artist - Song", with the channel as the artist.
                a = left
                t = right
            } else if right.range(of: #"remaster|live|version|edit|mix|mono|stereo"#, options: [.regularExpression, .caseInsensitive]) != nil {
                // Spotify's "Song - Remastered 2011": the song is the part before.
                t = left
            }
        }
        return (t.trimmingCharacters(in: .whitespaces), a.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Disk cache (so a song is only asked about once)

    private static func file(_ key: String) -> URL {
        var h: UInt64 = 1469598103934665603  // FNV-1a: a stable name for the song
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return cache.appendingPathComponent(String(h, radix: 16) + ".json")
    }

    private static func readCache(_ key: String) -> Found? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        if let f = try? JSONDecoder().decode(Found.self, from: data) { return f }
        // Saved by the first version: timed lines only.
        return (try? JSONDecoder().decode([Line].self, from: data)).map { Found(synced: true, lines: $0) }
    }

    private static func writeCache(_ key: String, _ found: Found) {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try? JSONEncoder().encode(found).write(to: file(key), options: .atomic)
    }

    /// Width the line needs in the closed notch.
    static func width(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)]).width)
    }
}

// MARK: - Notch geometry

final class NotchState: ObservableObject {
    @Published var expanded = false
    // Set by AppDelegate every tick; they decide what the expanded notch contains.
    @Published var showMedia = false
    @Published var showShelf = false
    @Published var showFocus = false
    @Published var activityRows = 0      // live activities listed at the top
    @Published var question: Activity?   // an agent's multiple-choice question takes over the notch
    /// The player shows the lyrics beside a smaller player (stays chosen until turned off).
    @Published var lyricsMode = false
    /// The lyric line under the closed notch, and the width it needs.
    @Published var lyric: String?
    var lyricWidth: CGFloat = 0
    static let lyricHeight: CGFloat = 22
    @Published var dragging = false      // a file is being dragged somewhere on screen
    @Published var dropTargeted = false  // ...and it is over the notch
    @Published var bump = false          // brief squash-and-stretch when something new arrives
    @Published var hovering = false      // the mouse is on the closed notch (it lifts, in the richer styles)
    @Published var mirrorOn = false      // the camera mirror replaces the usual sections
    @Published var proximity: CGFloat = 0  // 0 far ... 1 on the closed notch (magnetism)
    @Published var pulse = 0             // each increment sends a ripple out of the notch
    var pulseColor: Color = .white
    /// Volume (or a skipped song) shown next to the camera while it changes.
    struct Level: Equatable {
        var icon: String
        var value: Double?
    }
    @Published var level: Level?
    /// Size of the open notch (from Settings); the closed one always matches the hardware.
    var scale: CGFloat = 1
    static let maxScale: CGFloat = 1.25
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
    var side: CGFloat { (notchH + (timerShown ? 30 : 12)) * CGFloat(Settings.shared.sideScale) }
    // Expanded layout: sections stacked (Foco, music, shelf), split by hairlines.
    static let width: CGFloat = 470
    static let hPad: CGFloat = 24
    static let focusHeight: CGFloat = 44
    static let activityHeight: CGFloat = 46
    static let optionHeight: CGFloat = 42
    static let miniPlayerHeight: CGFloat = 44
    /// Laid out to fit the question: its text, one card per option, and the music still playing.
    static func questionHeight(_ q: Activity, media: Bool) -> CGFloat {
        let lines: CGFloat = (q.question ?? "").count > 52 ? 2 : 1
        let n = CGFloat(min(q.options?.count ?? 0, 4))
        return 18 + 8 + lines * 19 + 12 + n * optionHeight + max(0, n - 1) * 6 + 10 + 22 + (media ? miniPlayerHeight : 0)
    }
    static let maxActivities = 3
    static let mediaHeight: CGFloat = 124
    static let shelfHeight: CGFloat = 78
    static let emptyHeight: CGFloat = 84
    static let mirrorHeight: CGFloat = 236
    static let toastHeight: CGFloat = 52
    static let separator: CGFloat = 13  // hairline plus the space around it
    static let itemW: CGFloat = 64
    static let itemGap: CGFloat = 4
    private let chrome: CGFloat = 14     // space below the notch plus bottom padding

    var isEmpty: Bool { activityRows == 0 && !showFocus && !showMedia && !showShelf }

    /// Whether the closed notch grows side pieces: something to show beside the camera.
    static func isExtended(np: NowPlaying, shelf: Shelf, foco: FocoTimer, activities: Activities, mic: MicMonitor) -> Bool {
        np.hasMedia || !shelf.isEmpty || foco.session != nil || !activities.items.isEmpty || mic.shown
    }

    /// From the top of the open notch to where the shelf starts (sideways swipes there scroll the shelf).
    var shelfTop: CGFloat {
        var y = notchH + 4
        if paged { return currentPage == .shelf ? y : .greatestFiniteMagnitude }
        if activityRows > 0 { y += Self.activityHeight * CGFloat(activityRows) + Self.separator }
        if showFocus { y += Self.focusHeight + Self.separator }
        if showMedia { y += Self.mediaHeight + Self.separator }
        return y
    }

    // Pages: music (with Foco), shelf, activities, one at a time, when stacking them gets too tall.
    enum Page: String { case main, shelf, activities }
    @Published var page = Page.main
    /// Which way the last page change went, so the new page slides in from that side.
    var pageForward = true
    static let dotsHeight: CGFloat = 20
    static let pageLimit: CGFloat = 250

    var pages: [Page] {
        var p: [Page] = []
        if showFocus || showMedia { p.append(.main) }
        if showShelf { p.append(.shelf) }
        if activityRows > 0 { p.append(.activities) }
        return p
    }
    var paged: Bool {
        guard Settings.shared.pagesEnabled, !dragging, pages.count > 1 else { return false }
        return stackedHeight > Self.pageLimit
    }
    var currentPage: Page { pages.contains(page) ? page : (pages.first ?? .main) }

    func pageHeight(_ p: Page) -> CGFloat {
        switch p {
        case .main:
            return (showFocus ? Self.focusHeight : 0) + (showMedia ? Self.mediaHeight : 0) + (showFocus && showMedia ? Self.separator : 0)
        case .shelf: return Self.shelfHeight
        case .activities: return Self.activityHeight * CGFloat(activityRows)
        }
    }

    /// Pages share the tallest one's height: switching never moves the dots out from under the mouse.
    var pagedHeight: CGFloat { pages.map(pageHeight).max() ?? 0 }

    func go(to p: Page) {
        guard p != currentPage, let from = pages.firstIndex(of: currentPage), let to = pages.firstIndex(of: p) else { return }
        pageForward = to > from
        page = p
    }

    private var stackedHeight: CGFloat {
        let s = stackedSections
        return s.reduce(0, +) + Self.separator * CGFloat(max(0, s.count - 1))
    }
    private var stackedSections: [CGFloat] {
        var sections: [CGFloat] = []
        if activityRows > 0 { sections.append(Self.activityHeight * CGFloat(activityRows)) }
        if showFocus { sections.append(Self.focusHeight) }
        if showMedia { sections.append(Self.mediaHeight) }
        if showShelf { sections.append(Self.shelfHeight) }
        return sections
    }

    var expandedSize: CGSize {
        if mirrorOn { return CGSize(width: Self.width, height: notchH + chrome + Self.mirrorHeight) }
        if toast != nil { return CGSize(width: Self.width, height: notchH + chrome + Self.toastHeight) }
        if let q = question { return CGSize(width: Self.width, height: notchH + chrome + Self.questionHeight(q, media: showMedia)) }
        if paged { return CGSize(width: Self.width, height: notchH + chrome + pagedHeight + Self.dotsHeight) }
        var sections: [CGFloat] = []
        if activityRows > 0 { sections.append(Self.activityHeight * CGFloat(activityRows)) }
        if showFocus { sections.append(Self.focusHeight) }
        if showMedia { sections.append(Self.mediaHeight) }
        if showShelf { sections.append(Self.shelfHeight) }
        if sections.isEmpty { sections.append(Self.emptyHeight) }
        let h = notchH + chrome + sections.reduce(0, +) + Self.separator * CGFloat(sections.count - 1)
        return CGSize(width: Self.width, height: h)
    }
    var maxExpandedHeight: CGFloat {
        notchH + chrome + max(Self.mirrorHeight, Self.activityHeight * CGFloat(Self.maxActivities)
            + Self.focusHeight + Self.mediaHeight + Self.shelfHeight + Self.separator * 3)
    }
    static let maxExpandedWidth: CGFloat = 560

    /// `extended`: the collapsed notch grows side pieces (music playing or files on the shelf).
    func size(extended: Bool) -> CGSize {
        if expanded { return expandedSize }
        return closedSize(extended: extended)
    }

    func closedSize(extended: Bool) -> CGSize {
        let base = notchW + (extended ? side * 2 : 0)
        // Singing: a chin under the camera holds the line, as wide as the line needs.
        guard lyric != nil else { return CGSize(width: base, height: notchH) }
        return CGSize(width: min(max(base, lyricWidth + 44), Self.width), height: notchH + Self.lyricHeight)
    }
}

/// How the notch moves, per Motion setting. Springs get quicker with the speed setting.
struct MotionProfile {
    var open: Animation       // opening and closing
    var resize: Animation     // growing side pieces, sections coming and going
    var ooze: CGFloat         // how far the width leads the height (0: both together)
    var bump: CGSize          // squash-and-stretch when something arrives
    var bumpDamping: Double
    var ripple: Bool          // a ring spreading out of the notch when something arrives
    var stagger: Double       // delay between sections as they appear
    var contentDelay: Double  // the panel's content comes in just after the shape
}

extension Settings.Motion {
    func profile(speed: Double) -> MotionProfile {
        let s = min(max(speed, 0.5), 2)
        switch self {
        case .minimal:
            return MotionProfile(open: .easeOut(duration: 0.18), resize: .easeOut(duration: 0.18), ooze: 0,
                                 bump: CGSize(width: 1, height: 1), bumpDamping: 1, ripple: false, stagger: 0, contentDelay: 0)
        case .calm:
            return MotionProfile(open: .spring(response: 0.42 / s, dampingFraction: 0.86), resize: .spring(response: 0.4 / s, dampingFraction: 0.85),
                                 ooze: 0, bump: CGSize(width: 1.04, height: 1.08), bumpDamping: 0.45, ripple: false,
                                 stagger: 0, contentDelay: 0.05 / s)
        case .fluid:
            return MotionProfile(open: .spring(response: 0.5 / s, dampingFraction: 0.74), resize: .spring(response: 0.4 / s, dampingFraction: 0.8),
                                 ooze: 0.55, bump: CGSize(width: 1.07, height: 1.16), bumpDamping: 0.32, ripple: true,
                                 stagger: 0.05 / s, contentDelay: 0.08 / s)
        case .lively:
            return MotionProfile(open: .spring(response: 0.56 / s, dampingFraction: 0.62), resize: .spring(response: 0.42 / s, dampingFraction: 0.7),
                                 ooze: 0.85, bump: CGSize(width: 1.11, height: 1.26), bumpDamping: 0.26, ripple: true,
                                 stagger: 0.07 / s, contentDelay: 0.1 / s)
        }
    }
}

/// The notch's outline, frame and rim, driven by one opening progress (0 closed, 1 open).
/// The width runs ahead and the height behind, so it seems to spread out of the bezel and then
/// drop; closing, it pulls up first and slips back in last, as if it went back inside the Mac.
/// The spring's overshoot (past 1) stretches both, like a jelly settling.
struct NotchFrame: ViewModifier, Animatable {
    var progress: CGFloat
    var closed: CGSize
    var open: CGSize
    var ooze: CGFloat
    var scale: CGFloat
    var glass: Bool

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(progress, .init(.init(closed.width, closed.height), .init(open.width, open.height))) }
        set {
            progress = newValue.first
            closed = CGSize(width: newValue.second.first.first, height: newValue.second.first.second)
            open = CGSize(width: newValue.second.second.first, height: newValue.second.second.second)
        }
    }

    func body(content: Content) -> some View {
        let p = max(progress, -0.06)
        let inside = p > 0 && p < 1
        let lead = inside ? ooze * p * (1 - p) : 0
        let wp = p + lead, hp = p - lead
        let w = max(closed.width + (open.width - closed.width) * wp, 1)
        let h = max(closed.height + (open.height - closed.height) * hp, 1)
        let t = min(max(p, 0), 1)
        let top = min(6 + 6 * min(max(wp, 0), 1.2), w / 4)
        let bottom = min(10 + 22 * min(max(hp, 0), 1.2), max(h / 2, 2))
        let shape = NotchShape(topR: top, botR: bottom)
        content
            .frame(width: w, height: h, alignment: .top)
            .clipShape(shape)
            // Glass rim: a soft inner glow plus a hairline that brightens toward the bottom
            // (the top stays black so it still merges with the physical notch).
            .overlay(
                shape.stroke(Color.white.opacity(glass ? 0.16 : 0.10), lineWidth: 8)
                    .blur(radius: 6 * t)
                    .clipShape(shape)
                    .opacity(t))
            .overlay(
                shape.stroke(LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(glass ? 0.16 : 0.10), location: 0.35),
                    .init(color: .white.opacity(glass ? 0.45 : 0.28), location: 1),
                ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .opacity(t))
            .scaleEffect(1 + (scale - 1) * t, anchor: .top)
    }
}

/// A ring that spreads out of the closed notch and fades, like a drop landing in it.
struct Ripple: View {
    var trigger: Int
    var color: Color
    var size: CGSize
    @StateObject private var phase = Box<CGFloat>(1)

    var body: some View {
        NotchShape(topR: 6, botR: 10)
            .stroke(color, lineWidth: 1.5)
            .frame(width: size.width, height: size.height)
            .scaleEffect(x: 1 + 0.35 * phase.value, y: 1 + 1.4 * phase.value, anchor: .top)
            .opacity(Double(1 - phase.value) * 0.8)
            .blur(radius: 1 + 3 * phase.value)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                phase.value = 0
                withAnimation(.easeOut(duration: 0.75)) { phase.value = 1 }
            }
    }
}

/// Sections of the open notch come in one after the other, sliding down from the camera.
struct Rise: ViewModifier {
    var delay: Double
    var enabled: Bool
    @StateObject private var shown = Box<Bool>(false)

    func body(content: Content) -> some View {
        let on = shown.value || !enabled
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : -10)
            .scaleEffect(on ? 1 : 0.96, anchor: .top)
            .onAppear {
                guard enabled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.75).delay(delay)) { shown.value = true }
            }
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
// MARK: Live activity views

/// A turning arc, played by Core Animation like the music bars.
final class SpinnerLayerView: AnimatedLayerView {
    private let arc = CAShapeLayer()
    var color = NSColor.white.cgColor { didSet { arc.strokeColor = color } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        arc.fillColor = nil
        arc.lineWidth = 2.2
        arc.lineCap = .round
        arc.strokeEnd = 0.68
        arc.strokeColor = color
        root.addSublayer(arc)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func rebuild() {
        arc.frame = bounds
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.2, dy: 1.2), transform: nil)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 0.95
        spin.repeatCount = .infinity
        arc.add(spin, forKey: "spin")
    }
}

struct Spinner: NSViewRepresentable {
    var color: Color
    func makeNSView(context: Context) -> SpinnerLayerView { SpinnerLayerView(frame: .zero) }
    func updateNSView(_ v: SpinnerLayerView, context: Context) { v.color = NSColor(color).cgColor }
}

extension Activity {
    var color: Color {
        switch state {
        case .running: return Color(red: 0.38, green: 0.64, blue: 1)
        case .waiting: return .orange
        case .done: return .green
        case .failed: return Color(red: 1, green: 0.36, blue: 0.36)
        }
    }

    func subtitle(at now: Date) -> String {
        let time = Activity.duration(elapsed(at: now))
        switch state {
        case .waiting: return question ?? L("activityWaiting")
        case .running: return [detail, time].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        case .done: return L("activityDone") + " · " + time
        case .failed: return [L("activityFailed"), detail, time].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// The state at a glance: a spinner (or progress ring) while running, a hand while waiting.
struct ActivityBadge: View {
    var item: Activity
    var size: CGFloat
    var body: some View {
        let c = item.color
        ZStack {
            Circle().fill(c.opacity(0.16))
            switch item.state {
            case .running:
                if let p = item.progress {
                    Circle().stroke(c.opacity(0.25), lineWidth: 2.2).padding(1.2)
                    Circle().trim(from: 0, to: p)
                        .stroke(c, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.2)
                        .animation(.easeOut(duration: 0.4), value: p)
                } else {
                    Spinner(color: c)
                }
                Image(systemName: item.icon ?? "terminal.fill")
                    .font(.system(size: size * 0.36, weight: .bold)).foregroundColor(c)
            case .waiting:
                Image(systemName: "hand.raised.fill").font(.system(size: size * 0.42, weight: .bold)).foregroundColor(c)
            case .done:
                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundColor(c)
            case .failed:
                Image(systemName: "xmark").font(.system(size: size * 0.4, weight: .heavy)).foregroundColor(c)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: item.state)
    }
}

/// Ticks every second for the first minute, then once a minute: a long build doesn't need
/// the notch redrawn every second to show "12m".
struct MinuteSchedule: TimelineSchedule {
    var start: Date
    func entries(from date: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        sequence(first: date) { d in
            let e = d.timeIntervalSince(start)
            return e < 59 ? d.addingTimeInterval(1) : start.addingTimeInterval((floor(e / 60) + 1) * 60)
        }
    }
}

struct ActivityClock: View {
    var item: Activity
    var body: some View {
        if item.state == .running {
            TimelineView(MinuteSchedule(start: item.started ?? Date())) { ctx in Text(Self.short(item.elapsed(at: ctx.date))) }
        } else {
            Text(Self.short(item.elapsed(at: Date())))
        }
    }
    static func short(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : String(format: "%dh%02d", s / 3600, s % 3600 / 60)
    }
}

/// Content swapping in and out of the open notch: a soft blur and a breath of scale, so the
/// question and the player hand over to each other instead of cutting.
struct SoftSwap: ViewModifier {
    var amount: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: amount * 10)
            .opacity(1 - amount)
            .scaleEffect(1 - amount * 0.04, anchor: .top)
            .offset(y: amount * -6)
    }
}

struct QuestionView: View {
    var item: Activity
    var activities: Activities
    @ObservedObject var np: NowPlaying
    @ObservedObject var ui: NotchState
    @StateObject private var picked = Box<Set<String>>([])
    @StateObject private var sent = Box(false)

    var body: some View {
        let options = Array((item.options ?? []).prefix(4))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: item.icon ?? "sparkle").font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                Text(item.title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                if let h = item.header, !h.isEmpty {
                    Text(h).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .fixedSize()
                }
                Spacer(minLength: 6)
                if let step = item.step {
                    Text(step).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(height: 18)
            Text(item.question ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 12)
            VStack(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.element) { i, option in
                    OptionCard(option: option, picked: picked.value.contains(option.label), multi: item.multi == true,
                               sent: sent.value) { pick(option) }
                        // A short cascade, like the rest of the notch opening.
                        .transition(.opacity.combined(with: .offset(y: 6)).animation(.spring(response: 0.4).delay(0.04 * Double(i))))
                }
            }
            HStack {
                Button(L("inTerminal")) { activities.answer(item, "ask") }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                if item.multi == true {
                    Button(L("send")) { send(Array(picked.value)) }
                        .buttonStyle(ActivityButtonStyle(primary: true))
                        .disabled(picked.value.isEmpty || sent.value)
                        .opacity(picked.value.isEmpty ? 0.4 : 1)
                }
            }
            .frame(height: 22)
            .padding(.top, 10)
            if ui.showMedia { miniPlayer.padding(.top, 10) }
        }
    }

    /// The song keeps playing while you answer, so it stays in view, small.
    private var miniPlayer: some View {
        HStack(spacing: 10) {
            Artwork(image: np.artwork, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(np.title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                Text(np.artist).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if Settings.shared.style == .glass { MiniWave(playing: np.isPlaying, color: np.accent) }
            else { Waveform(playing: np.isPlaying, color: np.accent) }
            ControlButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 13, box: 28) { np.playPause() }
                .disabled(!np.canControl)
        }
        .padding(.horizontal, 8)
        .frame(height: NotchState.miniPlayerHeight - 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func pick(_ option: Activity.Option) {
        guard !sent.value else { return }
        if item.multi == true {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if picked.value.contains(option.label) { picked.value.remove(option.label) } else { picked.value.insert(option.label) }
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { picked.value = [option.label] }
            send([option.label])
        }
    }

    /// The choice lights up for a moment before the notch goes back to what it was showing.
    private func send(_ labels: [String]) {
        guard !labels.isEmpty, !sent.value else { return }
        sent.value = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        // Keep the order the agent listed them in.
        let ordered = (item.options ?? []).map(\.label).filter(labels.contains)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { activities.choose(item, ordered) }
    }
}

struct OptionCard: View {
    var option: Activity.Option
    var picked: Bool
    var multi: Bool
    var sent: Bool
    var action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if multi {
                    Image(systemName: picked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14)).foregroundColor(.white.opacity(picked ? 0.95 : 0.4))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    if let d = option.description, !d.isEmpty {
                        Text(d).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                if picked && !multi {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if hover.value && !sent {
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5))
                        .transition(.opacity.combined(with: .offset(x: -4)))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: NotchState.optionHeight)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(picked ? 0.18 : hover.value ? 0.11 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(picked ? 0.35 : 0.08), lineWidth: picked ? 1 : 0.6))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(picked && sent ? 1.015 : 1)
            // Once sent, the others step back.
            .opacity(sent && !picked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover.value = h } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: picked)
        .animation(.easeOut(duration: 0.2), value: sent)
    }
}

/// The words beside the small player: the line being sung bright, its neighbours faded,
/// everything gliding up as the song goes on.
struct LyricsColumn: View {
    @ObservedObject var lyrics: Lyrics
    var accent: Color

    var body: some View {
        Group {
            switch lyrics.status {
            case .ready, .plain:
                let i = lyrics.index ?? -1
                let plain = lyrics.status == .plain
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(max(0, i - 1)...max(0, min(lyrics.lines.count - 1, i + 2)), id: \.self) { n in
                        let text = lyrics.lines[n].text
                        // Without times the "current" line is only roughly right, so it isn't spotlit.
                        let now = n == i && !plain
                        Text(text.isEmpty ? "♪" : text)
                            .font(.system(size: now ? 14.5 : 13, weight: now ? .bold : .semibold))
                            .foregroundColor(.white.opacity(now ? 1 : plain ? (n < i ? 0.4 : 0.7) : n < i ? 0.3 : 0.45))
                            .lineLimit(now ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: now ? accent.opacity(0.6) : .clear, radius: 8)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)),
                                                    removal: .opacity.combined(with: .offset(y: -14))))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(.spring(response: plain ? 0.9 : 0.5, dampingFraction: 0.9), value: i)
                .overlay(alignment: .bottomTrailing) {
                    if plain {
                        Text(L("lyricsPlain")).font(.system(size: 9.5, weight: .medium)).foregroundColor(.white.opacity(0.4))
                    }
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                             .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            case .loading, .idle:
                Label(L("lyricsLoading"), systemImage: "quote.bubble")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing:
                Label(L("lyricsMissing"), systemImage: "quote.bubble")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A speaker in the player's corner; under the mouse it opens into a slider for the Mac's volume.
struct VolumeControl: View {
    @ObservedObject var open: Box<Bool>
    @StateObject private var level = Box<Float?>(nil)
    @StateObject private var available = Box(true)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: SystemVolume.icon(level.value ?? 0.5))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(open.value ? 0.95 : 0.6))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 30)
            if open.value, let v = level.value {
                ProgressBar(fraction: Double(v), live: true) { f in
                    if let set = SystemVolume.set(Float(f)) { level.value = set }
                }
                .frame(width: 74)
                .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .leading)))
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .opacity(available.value ? 1 : 0)
        .allowsHitTesting(available.value)
        .help(L("volume"))
        .onAppear { refresh() }
        .onDisappear { open.value = false }
        .onHover { h in
            if h { refresh() }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { open.value = h && level.value != nil }
        }
    }

    /// Read when shown or hovered (no polling); outputs without a volume (HDMI) hide it.
    private func refresh() {
        level.value = SystemVolume.get()
        available.value = level.value != nil
    }
}

/// Dots under the open notch, one per page; pointing at one is enough to switch.
struct PageDots: View {
    @StateObject private var rest = Box<DispatchWorkItem?>(nil)
    var pages: [NotchState.Page]
    var current: NotchState.Page
    var accent: Color
    var select: (NotchState.Page) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(pages, id: \.self) { p in
                let on = p == current
                Capsule()
                    .fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.28))
                    .frame(width: on ? 16 : 6, height: 6)
                    .shadow(color: on ? accent.opacity(0.6) : .clear, radius: 4)
                    .frame(width: 24, height: NotchState.dotsHeight)
                    .contentShape(Rectangle())
                    // A click switches at once; resting on a dot for a moment does too, passing over it doesn't.
                    .onHover { inside in
                        rest.value?.cancel()
                        guard inside else { return }
                        let w = DispatchWorkItem { select(p) }
                        rest.value = w
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
                    }
                    .onTapGesture { rest.value?.cancel(); select(p) }
                    .help(L("page." + p.rawValue))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: current)
    }
}

/// Allow / Deny: small capsules, the main one filled.
struct ActivityButtonStyle: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(primary ? .black : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(primary ? Color.white.opacity(configuration.isPressed ? 0.7 : 0.92)
                                               : Color.white.opacity(configuration.isPressed ? 0.22 : 0.12)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ActivityRow: View {
    var item: Activity
    var activities: Activities
    var body: some View {
        HStack(spacing: 12) {
            ActivityBadge(item: item, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                // Only a running one has a clock to keep up to date.
                Group {
                    if item.state == .running {
                        TimelineView(MinuteSchedule(start: item.started ?? Date())) { ctx in Text(item.subtitle(at: ctx.date)) }
                    } else {
                        Text(item.subtitle(at: Date()))
                    }
                }
                .font(.system(size: 11.5, design: item.state == .waiting ? .monospaced : .default))
                .foregroundColor(item.state == .waiting ? .white.opacity(0.8) : .white.opacity(0.55))
                .truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if item.state == .waiting {
                HStack(spacing: 6) {
                    Button(L("deny")) { activities.answer(item, "deny") }.buttonStyle(ActivityButtonStyle(primary: false))
                    Button(L("allow")) { activities.answer(item, "allow") }.buttonStyle(ActivityButtonStyle(primary: true))
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if item.finished {
                ControlButton(symbol: "xmark", size: 10, color: .white.opacity(0.4), box: 24) { activities.dismiss(item) }
            }
        }
        .frame(height: NotchState.activityHeight)
        .contentShape(Rectangle())
        .onTapGesture { activities.activate(item) }
        .help(item.question ?? item.detail ?? "")
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: item.state)
    }
}

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
    /// Report every move while dragging (volume), not just where it was let go (seeking).
    var live = false
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
                .onChanged {
                    let f = min(max($0.location.x / g.size.width, 0), 1)
                    box.value = f
                    if live { onSeek(f) }
                }
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
        if settings.micEnabled {
            let muted = c.mic.muted
            m.addItem(item(muted ? L("unmuteMic") : L("muteMic"), muted ? "mic" : "mic.slash", key: "m", modifiers: [.control, .option]) {
                NotificationCenter.default.post(name: AppDelegate.micToggleRequested, object: nil)
            })
        }
        if settings.ocrEnabled || settings.mirrorEnabled || settings.micEnabled { m.addItem(.separator()) }

        m.addItem(.sectionHeader(title: L("appearance")))
        let icons: [Settings.Style: String] = [.basic: "capsule.fill", .elevated: "square.stack.3d.up.fill", .glass: "drop.fill"]
        for style in Settings.Style.allCases {
            m.addItem(item(style.title, icons[style], on: settings.style == style) { settings.style = style })
        }
        let motion = item(L("motion"), "wand.and.stars") {}
        let motions = NSMenu()
        motions.autoenablesItems = false
        for mo in Settings.Motion.allCases {
            motions.addItem(item(mo.title, nil, on: settings.motion == mo) { settings.motion = mo })
        }
        motion.submenu = motions
        m.addItem(motion)
        m.addItem(.separator())

        m.addItem(.sectionHeader(title: L("behavior")))
        m.addItem(item(L("peekOnTrack"), "music.note", on: settings.peekOnTrackChange) { settings.peekOnTrackChange.toggle() })
        m.addItem(item(L("pages"), "rectangle.split.3x1", on: settings.pagesEnabled) { settings.pagesEnabled.toggle() })
        m.addItem(item(L("otherScreens"), "display.2", on: settings.showOnAllScreens) { settings.showOnAllScreens.toggle() })
        m.addItem(item(L("launchAtLogin"), "sunrise", on: settings.launchAtLogin) { settings.launchAtLogin.toggle() })
        let addons = item(L("addons"), "puzzlepiece.extension") {}
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(item(L("addonOCR"), "text.viewfinder", on: settings.ocrEnabled) { settings.ocrEnabled.toggle() })
        sub.addItem(item(L("addonMirror"), "camera", on: settings.mirrorEnabled) { settings.mirrorEnabled.toggle() })
        sub.addItem(item(L("addonLyrics"), "quote.bubble", on: settings.lyricsEnabled) { settings.lyricsEnabled.toggle() })
        sub.addItem(item(L("addonActivities"), "bolt.horizontal.circle", on: settings.activitiesEnabled) {
            settings.activitiesEnabled.toggle()
            // Connecting the agents lives in Settings; show it the first time.
            if settings.activitiesEnabled && !AgentHooks.anyInstalled { SettingsWindow.shared.show(welcome: false, pane: .addons) }
        })
        sub.addItem(item(L("headphonesHQ"), "headphones", on: settings.keepHeadphonesHQ) { settings.keepHeadphonesHQ.toggle() })
        sub.addItem(.separator())
        sub.addItem(item(L("addonGestures"), "hand.draw", on: settings.gesturesEnabled) { settings.gesturesEnabled.toggle() })
        sub.addItem(item(L("addonMic"), "mic", on: settings.micEnabled) { settings.micEnabled.toggle() })
        sub.addItem(item(L("addonLid"), "laptopcomputer", on: settings.lidPauseEnabled) { settings.lidPauseEnabled.toggle() })
        sub.addItem(item(L("addonHaptics"), "hand.tap", on: settings.hapticsEnabled) { settings.hapticsEnabled.toggle() })
        sub.addItem(item(L("addonGlow"), "rectangle.dashed", on: settings.edgeGlowEnabled) { settings.edgeGlowEnabled.toggle() })
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
        // Convert, shrink, cut out, read, compress: the result lands on the shelf too.
        let actions = many ? [] : QuickAction.available(for: entry)
        let files = group.filter { $0.kind == .file }
        if !actions.isEmpty || !files.isEmpty {
            let quick = NSMenuItem(title: L("quickActions"), action: nil, keyEquivalent: "")
            quick.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
            let sub = NSMenu()
            for a in actions {
                let i = ClosureMenuItem(a.title) { QuickActions.run(a, on: entry, shelf: shelf) }
                i.image = NSImage(systemSymbolName: a.symbol, accessibilityDescription: nil)
                sub.addItem(i)
            }
            if !files.isEmpty {
                if !actions.isEmpty { sub.addItem(.separator()) }
                let z = ClosureMenuItem(files.count > 1 ? L("zipN", files.count) : L("zip")) { QuickActions.zip(files, shelf: shelf) }
                z.image = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil)
                sub.addItem(z)
            }
            quick.submenu = sub
            m.addItem(quick)
        }
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
    @ObservedObject var activities: Activities
    @ObservedObject var mic: MicMonitor
    @ObservedObject var lyrics = Lyrics.shared
    @ObservedObject var settings = Settings.shared
    /// The volume slider is out (the app icons beside it step aside).
    @StateObject private var volumeOpen = Box(false)

    private var profile: MotionProfile { settings.effectiveMotion.profile(speed: settings.motionSpeed) }

    var body: some View {
        let extended = NotchState.isExtended(np: np, shelf: shelf, foco: foco, activities: activities, mic: mic)
        let closed = ui.closedSize(extended: extended)
        let open = ui.expandedSize
        let total = open.height
        let style = settings.style
        let glass = style == .glass
        let lifted = style != .basic
        let motion = profile
        let magnetic = settings.magnetism && settings.effectiveMotion != .minimal
        // Magnetism: the closed notch stretches toward the cursor as it gets close. Without it, the
        // richer styles still rise a little under the mouse before opening.
        let pull = magnetic && !ui.expanded ? ui.proximity : 0
        let lift = !magnetic && lifted && ui.hovering && !ui.expanded

        ZStack(alignment: .top) {
            // Expanded: frosted glass tinted by the album art, fading into solid black
            // at the top so it still blends with the physical notch.
            if ui.expanded {
            ZStack(alignment: .top) {
                PanelMaterial(glass: glass, tint: ui.showMedia ? np.accent : .white)
                Color.black.opacity(glass ? 0.22 : 0.28)
                if ui.showMedia, let art = np.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: open.width, height: total)
                        .blur(radius: 50)
                        .saturation(glass ? 1.5 : 1)
                        .opacity(glass ? 0.55 : 0.4)
                }
                if ui.lyricsMode && settings.lyricsEnabled && ui.showMedia && ui.question == nil {
                    LinearGradient(colors: [.clear, np.accent.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        .transition(.opacity)
                }
                if style == .elevated {
                    // Light falling on a raised surface: a little brighter at the top.
                    LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
                }
                if glass {
                    // A sheen from above, like light on a pane of glass.
                    LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
                    // Not under a question, a message or the lyrics: they sit where the waves flow.
                    if ui.showMedia && !ui.mirrorOn && ui.question == nil && ui.toast == nil && !(ui.lyricsMode && settings.lyricsEnabled) {
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
            .frame(width: open.width, height: total)
            .transition(.opacity)
            }

            // Collapsed: pure black, it has to look like part of the hardware.
            Color.black.opacity(ui.expanded ? 0 : 1)

            if ui.expanded {
                expanded.transition(.asymmetric(insertion: contentInsertion(lifted: lifted),
                                                removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else if extended {
                collapsed.transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .modifier(NotchFrame(progress: ui.expanded ? 1 : 0, closed: closed, open: open, ooze: motion.ooze,
                             scale: CGFloat(min(max(settings.notchScale, 0.85), Double(NotchState.maxScale))), glass: glass))
        // A ring spreads out of the notch when something arrives (Fluid and Lively).
        .background(alignment: .top) {
            if motion.ripple && !ui.expanded {
                Ripple(trigger: ui.pulse, color: ui.pulseColor, size: closed)
            }
        }
        // Elevated and Glass: while playing, a soft light in the album's color under the closed notch.
        .background(alignment: .bottom) {
            Capsule()
                .fill(np.accent)
                .frame(width: closed.width * 0.55, height: 3)
                .blur(radius: 4)
                .offset(y: 3)
                .opacity(lifted && np.isPlaying && !ui.expanded ? 0.75 : 0)
                .animation(.easeInOut(duration: 0.4), value: np.isPlaying)
                .allowsHitTesting(false)
        }

        .onDrop(of: Shelf.dropTypes, isTargeted: Binding(get: { ui.dropTargeted }, set: { ui.dropTargeted = $0 })) { providers in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { shelf.accept(providers) }
        }
        .scaleEffect(x: ui.bump ? motion.bump.width : 1, y: ui.bump ? motion.bump.height : 1, anchor: .top)
        .animation(.spring(response: 0.22, dampingFraction: motion.bumpDamping), value: ui.bump)
        .scaleEffect(x: lift ? 1.04 : 1 + 0.045 * pull, y: lift ? 1.12 : 1 + 0.18 * pull, anchor: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: lift)
        .animation(.spring(response: 0.26, dampingFraction: 0.58), value: pull)
        // Halo in the album's color, then the drop shadow (two layers when elevated: close and ambient).
        .shadow(color: (ui.showMedia ? np.accent : .white).opacity(ui.expanded ? (glass ? 0.3 : lifted ? 0.22 : 0.18) : 0),
                radius: ui.expanded ? (lifted ? 32 : 24) : 0)
        .shadow(color: .black.opacity(ui.expanded || lift || pull > 0.3 ? 0.45 : 0),
                radius: ui.expanded ? (lifted ? 10 : 18) : lift || pull > 0.3 ? 6 : 0,
                y: ui.expanded ? (lifted ? 5 : 8) : lift || pull > 0.3 ? 3 : 0)
        .shadow(color: .black.opacity(lifted && ui.expanded ? 0.35 : 0), radius: lifted && ui.expanded ? 36 : 0,
                y: lifted && ui.expanded ? 20 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(motion.open, value: ui.expanded)
        .animation(motion.resize, value: extended)
        .animation(motion.resize, value: ui.expandedSize.height)
        .animation(motion.resize, value: settings.sideScale)
        // Each new line: the chin stretches or shrinks to it, the words cross-fade.
        .animation(motion.resize, value: ui.lyric)
        .animation(.easeInOut(duration: 0.5), value: np.accent)
    }

    /// The open panel's content: out of a blur in the richer styles and motions, a plain fade in Minimal.
    private func contentInsertion(lifted: Bool) -> AnyTransition {
        let motion = settings.effectiveMotion
        if motion == .minimal { return AnyTransition.opacity.animation(.easeOut(duration: 0.15)) }
        let delay = profile.contentDelay
        if lifted || motion != .calm {
            return AnyTransition.modifier(active: Materialize(amount: 1), identity: Materialize(amount: 0))
                .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(delay))
        }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.9, anchor: .top))
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay))
    }

    private var micShown: Bool { mic.shown }

    /// Left: what's running, else what's playing, else the Foco phase, else the shelf, else the mic.
    /// Right: the activity's progress, the Foco countdown, the waveform, then the shelf count.
    private var collapsed: some View {
        // Left: what's playing, else the Foco phase, else a live activity, else the shelf, else the mic.
        // Right: the Foco countdown, then a question waiting for you, the waveform, the activity's
        // clock, and last the shelf count.
        let activity = activities.items.first
        return HStack {
            if np.hasMedia {
                Artwork(image: np.artwork, size: ui.notchH - 12)
                    // Something is running too: a dot in its color on the cover.
                    .overlay(alignment: .bottomTrailing) {
                        if let activity {
                            Circle().fill(activity.color).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                                .transition(.scale)
                        }
                    }
            } else if let s = foco.session {
                Image(systemName: s.isBreak ? "cup.and.saucer.fill" : "scope")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(foco.color)
            } else if let activity {
                ActivityBadge(item: activity, size: ui.notchH - 12)
            } else if !shelf.isEmpty {
                Image(systemName: "tray.full.fill").font(.system(size: 12, weight: .semibold))
            } else if micShown {
                Image(systemName: mic.muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(mic.muted ? .red : .orange)
            }
            Spacer()
            if foco.session != nil {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(FocoTimer.clock(foco.remaining(at: ctx.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(foco.color)
                        .fixedSize()
                }
            } else if let activity, activity.state == .waiting {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(activity.color)
                    .symbolEffect(.bounce, value: activity.question)
            } else if np.hasMedia {
                musicIndicator
            } else if let activity {
                ActivityClock(item: activity)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(activity.color)
                .fixedSize()
            } else if !shelf.isEmpty {
                Text("\(shelf.items.count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 13)
        .frame(width: ui.notchW + ui.side * 2, height: ui.notchH)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            if let line = ui.lyric {
                lyricLine(line).offset(y: ui.notchH - 3)
            }
        }
        // Singing: the album's color glows up from the bottom of the pill.
        .background(alignment: .bottom) {
            if ui.lyric != nil {
                LinearGradient(colors: [.clear, np.accent.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: ui.notchH + NotchState.lyricHeight)
                    .offset(y: NotchState.lyricHeight)
                    .transition(.opacity)
            }
        }
        // Like the orange privacy light: a dot at the edge while an app listens.
        .overlay(alignment: .trailing) {
            if micShown && (np.hasMedia || !shelf.isEmpty || foco.session != nil || !activities.items.isEmpty) {
                micDot.padding(.trailing, 4)
            }
        }
    }

    /// The line being sung, in the album's light: each new one rises in from below.
    private func lyricLine(_ line: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.85))
            Text(line)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .id(line)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity.combined(with: .offset(y: -8))))
        }
        .padding(.horizontal, 18)
        .frame(height: NotchState.lyricHeight)
    }

    private var micDot: some View {
        Circle()
            .fill(mic.muted ? Color.red : Color.orange)
            .frame(width: 5, height: 5)
            .shadow(color: (mic.muted ? Color.red : Color.orange).opacity(0.8), radius: 3)
            .transition(.scale.combined(with: .opacity))
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
        ZStack {
            if ui.lyricsMode && settings.lyricsEnabled {
                lyricsPlayer.transition(.modifier(active: SoftSwap(amount: 1), identity: SoftSwap(amount: 0)))
            } else {
                fullPlayer.transition(.modifier(active: SoftSwap(amount: 1), identity: SoftSwap(amount: 0)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: ui.lyricsMode)
        .frame(height: NotchState.mediaHeight)
    }

    private var lyricsButton: some View {
        ControlButton(symbol: ui.lyricsMode ? "quote.bubble.fill" : "quote.bubble", size: 15,
                      color: ui.lyricsMode ? np.accent : .white.opacity(0.7)) { ui.lyricsMode.toggle() }
            .help(L("lyrics"))
    }

    /// Lyrics view: a small player on the left, the words scrolling on the right.
    private var lyricsPlayer: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Artwork(image: np.artwork, size: 44)
                        .shadow(color: np.accent.opacity(0.45), radius: 10, y: 3)
                        .onTapGesture { np.openPlayer() }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(np.title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(.white)
                        Text(np.artist).font(.system(size: 11.5, weight: .medium)).foregroundColor(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !np.isPlaying)) { ctx in
                    let pos = np.currentPosition(at: ctx.date)
                    HStack(spacing: 7) {
                        Text(fmt(pos))
                        ProgressBar(fraction: np.duration > 0 ? pos / np.duration : 0) { np.seek(to: $0 * np.duration) }
                        Text("-" + fmt(max(np.duration - pos, 0)))
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
                }
                HStack(spacing: 0) {
                    lyricsButton
                    Spacer(minLength: 0)
                    ControlButton(symbol: "backward.fill", size: 14, box: 32) { np.previous() }
                    ControlButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 19, box: 36) { np.playPause() }
                    ControlButton(symbol: "forward.fill", size: 14, box: 32) { np.next() }
                    Spacer(minLength: 0)
                }
                .disabled(!np.canControl)
            }
            .frame(width: 188)
            LyricsColumn(lyrics: lyrics, accent: np.accent)
        }
    }

    private var fullPlayer: some View {
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
                    if settings.lyricsEnabled { lyricsButton }
                    if settings.mirrorEnabled {
                        ControlButton(symbol: "camera", size: 15, color: .white.opacity(0.7)) { ui.mirrorOn = true }
                            .help(L("cameraMirror"))
                    }
                    if np.isMusicApp {
                        ControlButton(symbol: np.favorited ? "heart.fill" : "heart", size: 17,
                                      color: np.favorited ? .pink : .white.opacity(0.7)) { np.toggleFavorite() }
                    }
                }
                .frame(width: 118, alignment: .leading)
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
                HStack(spacing: 0) {
                    VolumeControl(open: volumeOpen)
                    if !volumeOpen.value { sourceSwitcher.transition(.opacity) }
                }
                .frame(width: 118, alignment: .trailing)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: volumeOpen.value)
            }
        }
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
            } else if let q = ui.question {
                // The agent takes over; the music keeps going in the strip at the bottom.
                QuestionView(item: q, activities: activities, np: np, ui: ui)
                    .id(q.id + (q.question ?? ""))
                    .transition(.modifier(active: SoftSwap(amount: 1), identity: SoftSwap(amount: 0)))
            } else {
                VStack(spacing: 0) { regularSections }
                    .transition(.modifier(active: SoftSwap(amount: 1), identity: SoftSwap(amount: 0)))
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: ui.question.map { $0.id + ($0.question ?? "") })
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
        // Beside the camera, like status lights built into the bezel: volume on the left, mic on the right.
        .overlay(alignment: .top) { ears }
    }

    private var ears: some View {
        let earW = max(0, (ui.expandedSize.width - ui.notchW) / 2 - NotchState.hPad - 6)
        return HStack(spacing: 0) {
            ZStack {
                if let l = ui.level { levelView(l) }
            }
            .frame(width: earW, alignment: .trailing)
            Spacer(minLength: ui.notchW + 12)
            ZStack {
                if micShown {
                    Button { NotificationCenter.default.post(name: AppDelegate.micToggleRequested, object: nil) } label: {
                        Label(mic.muted ? L("micMuted") : L("micLive"), systemImage: mic.muted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .labelStyle(.iconOnly)
                            .foregroundColor(mic.muted ? .red : .orange)
                            .frame(width: 22, height: 18)
                            .background(Capsule().fill((mic.muted ? Color.red : Color.orange).opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help(mic.muted ? L("unmuteMic") : L("muteMic"))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: earW, alignment: .leading)
        }
        .padding(.horizontal, NotchState.hPad)
        .frame(height: ui.notchH)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ui.level)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mic.muted)
    }

    private func levelView(_ l: NotchState.Level) -> some View {
        HStack(spacing: 7) {
            Image(systemName: l.icon)
                .font(.system(size: 11, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            if let v = l.value {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(v))
                    }
                }
                .frame(width: 64, height: 5)
                .animation(.spring(response: 0.2, dampingFraction: 0.85), value: v)
            }
        }
        .foregroundColor(.white.opacity(0.9))
        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
    }

    /// Each section slides down after the one above it.
    private func rise(_ index: Int) -> Rise {
        let p = profile
        let shown = [ui.activityRows > 0, ui.showFocus, ui.showMedia, ui.showShelf].prefix(index).filter { $0 }.count
        return Rise(delay: p.contentDelay + p.stagger * Double(shown), enabled: p.stagger > 0)
    }

    private var activitySection: some View {
        VStack(spacing: 0) {
            ForEach(activities.items.prefix(ui.activityRows)) { item in
                ActivityRow(item: item, activities: activities)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: activities.items)
    }

    /// One page at a time, sliding sideways, with the dots below.
    private var pagedSections: some View {
        let current = ui.currentPage
        let forward = ui.pageForward
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                pageContent(current)
                    .id(current)
                    .transition(.asymmetric(
                        insertion: .modifier(active: SoftSwap(amount: 0.7), identity: SoftSwap(amount: 0))
                            .combined(with: .offset(x: forward ? 46 : -46)),
                        removal: .opacity.combined(with: .offset(x: forward ? -46 : 46))))
            }
            // Shorter pages sit in the middle of the shared height.
            .frame(height: ui.pagedHeight, alignment: .center)
            PageDots(pages: ui.pages, current: current, accent: np.accent) { ui.go(to: $0) }
                .frame(height: NotchState.dotsHeight)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: current)
    }

    @ViewBuilder private func pageContent(_ p: NotchState.Page) -> some View {
        switch p {
        case .main:
            VStack(spacing: 0) {
                if ui.showFocus { focusSection }
                if ui.showFocus && ui.showMedia { hairline }
                if ui.showMedia { mediaSection }
            }
        case .shelf: shelfSection
        case .activities: activitySection
        }
    }

    @ViewBuilder private var regularSections: some View {
        if ui.paged {
            pagedSections
        } else {
            stackedSections
        }
    }

    @ViewBuilder private var stackedSections: some View {
            if ui.activityRows > 0 { activitySection.modifier(rise(0)) }
            if ui.showFocus {
                if ui.activityRows > 0 { hairline }
                focusSection.modifier(rise(1))
            }
            if ui.showMedia {
                if ui.showFocus || ui.activityRows > 0 { hairline }
                mediaSection.modifier(rise(2))
            }
            if ui.showShelf {
                if ui.activityRows > 0 || ui.showFocus || ui.showMedia { hairline }
                shelfSection.modifier(rise(3))
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
    /// Settings lists every add-on; the walkthrough only has room for the first few.
    var extras = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(L("addonOCR"), isOn: $settings.ocrEnabled)
            Toggle(L("addonMirror"), isOn: $settings.mirrorEnabled)
            Toggle(L("addonLyrics"), isOn: $settings.lyricsEnabled.animation(.spring(response: 0.35)))
                .help(L("addonLyricsHint"))
            if settings.lyricsEnabled {
                Toggle(L("lyricsClosed"), isOn: $settings.lyricsClosed)
                    .padding(.leading, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Toggle(L("addonActivities"), isOn: $settings.activitiesEnabled.animation(.spring(response: 0.35)))
                .help(L("activitiesHint"))
            if settings.activitiesEnabled {
                ActivitiesSetup().transition(.opacity.combined(with: .move(edge: .top)))
            }
            Toggle(L("headphonesHQ"), isOn: $settings.keepHeadphonesHQ)
                .help(L("headphonesHQHint"))
            if extras {
                Divider().opacity(0.5)
                addon(L("addonGestures"), L("addonGesturesHint"), $settings.gesturesEnabled)
                addon(L("addonMic"), L("addonMicHint"), $settings.micEnabled)
                addon(L("addonLid"), L("addonLidHint"), $settings.lidPauseEnabled)
                addon(L("addonHaptics"), L("addonHapticsHint"), $settings.hapticsEnabled)
                addon(L("addonGlow"), L("addonGlowHint"), $settings.edgeGlowEnabled)
            }
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

    private func addon(_ title: String, _ hint: String, _ on: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: on)
            Text(hint)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The lid angle to pause at, with the live angle to find a good one.
struct LidSettings: View {
    @ObservedObject var lid: LidSensor
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if lid.available {
                HStack(spacing: 10) {
                    Text(L("lidAngle", Int(settings.lidThreshold))).font(.system(size: 13).monospacedDigit())
                        .frame(width: 170, alignment: .leading)
                    Slider(value: $settings.lidThreshold, in: 15...100, step: 1)
                }
                if let a = lid.angle {
                    Text(L("lidNow", Int(a.rounded())))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(a < settings.lidThreshold ? .orange : .secondary)
                }
            } else {
                Label(L("lidUnavailable"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { lid.watching = true }
        .onDisappear { lid.watching = false }
    }
}

/// How to install and use the notch command.
struct ActivitiesHelp: View {
    static let install = "sudo mkdir -p /usr/local/bin && sudo ln -sf /Applications/NotchUser.app/Contents/Resources/notch /usr/local/bin/notch"
    @StateObject private var copied = Box<Bool>(false)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("terminalHint"))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Text(Self.install)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.3)))
                Button(copied.value ? L("copied") : L("copyCommand")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.install, forType: .string)
                    copied.value = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied.value = false }
                }
                .controlSize(.small)
            }
            Text("notch run npm test    notch notify \"Build ok\"    notch progress build 40")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

/// Motion style, speed and magnetism.
struct MotionSettings: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $settings.motion) {
                ForEach(Settings.Motion.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(L("motionHint"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(L("motionSpeed")).font(.system(size: 13)).frame(width: 90, alignment: .leading)
                Text(L("slower")).font(.system(size: 10.5)).foregroundColor(.secondary)
                Slider(value: $settings.motionSpeed, in: 0.6...1.6)
                Text(L("faster")).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            .disabled(settings.motion == .minimal)
            .opacity(settings.motion == .minimal ? 0.5 : 1)
            Toggle(L("magnetism"), isOn: $settings.magnetism)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                Label(L("reduceMotionOn"), systemImage: "figure.walk")
                    .font(.system(size: 11)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L("tryIt")) { NotificationCenter.default.post(name: Settings.previewRequested, object: nil) }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How big the open notch is and how far the closed one sticks out.
struct SizeSettings: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(L("notchSize"), $settings.notchScale, 0.85...1.25)
            row(L("sideSize"), $settings.sideScale, 0.7...1.6)
            Text(L("sizeHint"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("reset")) {
                    settings.notchScale = 1
                    settings.sideScale = 1
                }
                .controlSize(.small)
                .disabled(settings.notchScale == 1 && settings.sideScale == 1)
                Spacer()
                Button(L("tryIt")) { NotificationCenter.default.post(name: Settings.previewRequested, object: nil) }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Open the notch while the size is being changed, to see it.
        .onChange(of: settings.notchScale) { _, _ in
            NotificationCenter.default.post(name: Settings.previewRequested, object: nil)
        }
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).frame(width: 190, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// Under the Live activities switch: what shows up on its own, and the agents to connect.
struct ActivitiesSetup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupRow(icon: "hammer.fill", color: .blue, title: L("autoTasks"), hint: L("autoTasksHint")) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 14))
            }
            ForEach(Agent.allCases) { agent in
                Divider().opacity(0.5)
                AgentRow(agent: agent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

struct SetupRow<Trailing: View>: View {
    var icon: String
    var color: Color
    var title: String
    var hint: String
    var hintColor: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(hint).font(.system(size: 10.5)).foregroundColor(hintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// One agent: Connect → a short spinner → "Connected" (with Disconnect next to it).
struct AgentRow: View {
    var agent: Agent
    @StateObject private var connected: Box<Bool>
    @StateObject private var working = Box<Bool?>(nil)  // connecting (true) or disconnecting (false)
    @StateObject private var error = Box(false)

    init(agent: Agent) {
        self.agent = agent
        _connected = StateObject(wrappedValue: Box(AgentHooks.installed(agent)))
    }

    private var hint: String {
        if error.value { return L("agentSettingsError", AgentHooks.configURL(agent).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) }
        if connected.value { return L(agent == .codex ? "codexTrust" : "claudeRestart") }
        return L("agentHint." + agent.rawValue)
    }

    var body: some View {
        SetupRow(icon: agent.icon, color: agent.color, title: agent.settingsName, hint: hint,
                 hintColor: error.value ? .red : .secondary) {
            control
        }
    }

    @ViewBuilder private var control: some View {
        if let target = working.value {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text(L(target ? "connecting" : "disconnecting")).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .fixedSize()
            .transition(.opacity)
        } else if connected.value {
            HStack(spacing: 8) {
                // The bounce goes on the check alone: on the whole label it pushed the text past the capsule.
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, value: connected.value)
                    Text(L("connected")).lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.green)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.14)))
                Button(L("disconnect")) { toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
            Button(L("connect")) { toggle() }
                .controlSize(.small)
                .fixedSize()
                .transition(.opacity)
        }
    }

    private func toggle() {
        let on = !connected.value
        withAnimation(.easeOut(duration: 0.15)) { working.value = on }
        let started = Date()
        let agent = agent
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = (try? AgentHooks.set(agent, on)) != nil
            let installed = AgentHooks.installed(agent)
            // Long enough to see that something happened, even though writing takes a moment.
            let wait = max(0, 0.7 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    working.value = nil
                    error.value = !ok
                    connected.value = installed
                }
            }
        }
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
        case general, appearance, motion, addons, permissions
        var id: String { rawValue }
        var title: String { L(rawValue == "general" ? "general" : rawValue) }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .appearance: return "paintbrush.fill"
            case .motion: return "wand.and.stars"
            case .addons: return "puzzlepiece.extension.fill"
            case .permissions: return "hand.raised.fill"
            }
        }
        var color: Color {
            switch self {
            case .general: return .gray
            case .appearance: return .purple
            case .motion: return .pink
            case .addons: return .orange
            case .permissions: return .blue
            }
        }
    }
    /// The pane the next Settings window opens on.
    static var startPane: Pane = .general
    @Published var pane: Pane = SettingsModel.startPane
}

/// Settings in landscape, like System Settings: sections on the left, their options on the right.
struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var perms: Permissions
    var lid: LidSensor?
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
                        Toggle(L("pages"), isOn: $settings.pagesEnabled)
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
            case .motion:
                glassSection(L("motion")) { MotionSettings() }
                glassSection(L("size")) { SizeSettings() }
            case .addons:
                glassSection("") { AddOnsList(extras: true) }
                Text(L("addonsSub"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if settings.lidPauseEnabled, let lid {
                    glassSection(L("addonLid")) { LidSettings(lid: lid) }
                }
                glassSection(L("terminalActivities")) { ActivitiesHelp() }
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
    var lid: LidSensor?

    func show(welcome: Bool, pane: SettingsModel.Pane = .general) {
        SettingsModel.startPane = pane
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
            let controller = NSHostingController(rootView: SettingsView(perms: perms, lid: lid))
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
    private let np: NowPlaying
    let activities: Activities
    let mic: MicMonitor
    private var mirrorWatch: AnyCancellable?
    let panel: NotchPanel
    let displayID: CGDirectDisplayID
    var peekUntil = Date.distantPast
    /// Opens the notch whatever it holds, to try the motion and size settings.
    var previewUntil = Date.distantPast
    var levelUntil = Date.distantPast
    private var swipe: CGFloat = 0
    private var swiped = false
    /// Keeps the notch open on the mirror for a moment, e.g. right after camera access was granted.
    var mirrorHoldUntil = Date.distantPast
    var toastUntil = Date.distantPast
    private var hoverSince: Date?
    private var leftSince: Date?
    /// Restarts the short grace period before the notch closes (e.g. once its menu is dismissed).
    func leaveDelayFromNow() { leftSince = Date() }

    init(screen: NSScreen, np: NowPlaying, shelf: Shelf, foco: FocoTimer, camera: CameraMirror, activities: Activities, mic: MicMonitor) {
        displayID = screen.displayID
        self.camera = camera
        self.np = np
        self.activities = activities
        self.mic = mic
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let host = HostingView(rootView: NotchView(np: np, ui: ui, shelf: shelf, foco: foco, camera: camera,
                                                   activities: activities, mic: mic))
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
        // Room for the largest open notch (size setting) and its shadow.
        let w = NotchState.maxExpandedWidth * NotchState.maxScale, h = (ui.maxExpandedHeight + 40) * NotchState.maxScale
        panel.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h), display: true)
    }

    func close() { panel.orderOut(nil) }

    /// Quick squash-and-stretch, like the island reacting to something new.
    func bump(_ color: Color = .white) {
        ui.bump = true
        ui.pulseColor = color
        ui.pulse += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { self.ui.bump = false }
    }

    /// The closed notch sings along while the song plays (not while something is being dropped).
    func updateLyric(fileDrag: Bool = false) {
        let s = Settings.shared
        let timed = Lyrics.shared.status == .ready  // plain lyrics are only roughly placed: not under the camera
        let line = s.lyricsEnabled && s.lyricsClosed && timed && np.isPlaying && !fileDrag ? Lyrics.shared.line : nil
        guard ui.lyric != line else { return }
        if let line { ui.lyricWidth = Lyrics.width(line) }
        ui.lyric = line
    }

    func showLevel(_ l: NotchState.Level) {
        ui.level = l
        levelUntil = Date().addingTimeInterval(1.3)
    }

    /// Two fingers on the notch: up and down for the volume, sideways for the previous or next song.
    func scroll(_ e: NSEvent) -> Bool {
        guard Settings.shared.gesturesEnabled else { return false }
        if e.phase.contains(.began) || e.phase.contains(.mayBegin) {
            swipe = 0
            swiped = false
        }
        // In the direction the fingers move, whatever the natural scrolling setting.
        let inverted = e.isDirectionInvertedFromDevice
        let up = inverted ? -e.scrollingDeltaY : e.scrollingDeltaY
        let right = inverted ? e.scrollingDeltaX : -e.scrollingDeltaX
        guard up != 0 || right != 0 else { return true }
        // The momentum after the fingers lift would keep changing things.
        let coasting = !e.momentumPhase.isEmpty
        if abs(right) > abs(up) {
            // Sideways over the shelf scrolls the shelf.
            let fromTop = panel.frame.height - e.locationInWindow.y
            guard np.hasMedia, !ui.showShelf || !ui.expanded || fromTop < ui.shelfTop * ui.scale else { return false }
            guard e.hasPreciseScrollingDeltas, !swiped, !coasting else { return true }
            swipe += right
            if abs(swipe) > 70 {
                swiped = true
                let forward = swipe > 0
                forward ? np.next() : np.previous()
                showLevel(.init(icon: forward ? "forward.fill" : "backward.fill", value: nil))
                Haptics.play(.tap)
                bump(np.accent)
            }
            return true
        }
        guard !coasting, let v = SystemVolume.get() else { return true }
        let step = e.hasPreciseScrollingDeltas ? Float(up) / 350 : (up > 0 ? 1 : -1) / 16
        if let now = SystemVolume.set(v + step) {
            showLevel(.init(icon: SystemVolume.icon(now), value: Double(now)))
            // A tick at both ends, like reaching the end of a slider.
            if (now == 0 || now == 1) && now != v { Haptics.play(.tap) }
        }
        return true
    }

    /// Whether this notch needs the fast hover loop: it is open, peeking, or the mouse is close.
    func isHot(_ mouse: NSPoint) -> Bool {
        guard let s = screen else { return false }
        let zone = NSRect(x: s.frame.midX - 420, y: s.frame.maxY - 260, width: 840, height: 260)
        return ui.expanded || Date() < peekUntil || Date() < previewUntil || Date() < levelUntil || zone.contains(mouse)
    }

    /// While the right-click menu is open the notch holds still: the mouse is over the menu, not
    /// the notch, and closing it would also close the menu.
    var menuOpen = false
    let menuWatcher = MenuWatcher()

    func tick(fileDrag: Bool, np: NowPlaying, shelf: Shelf, foco: FocoTimer, activities: Activities) {
        guard let s = screen, !menuOpen else { return }

        if fileDrag != ui.dragging { ui.dragging = fileDrag }
        // While something is carried in, the notch shows only the big drop zone.
        let showShelf = !shelf.isEmpty || fileDrag
        let showMedia = np.hasMedia && !fileDrag
        let showFocus = foco.session != nil && !fileDrag
        if ui.showMedia != showMedia { ui.showMedia = showMedia }
        if ui.showShelf != showShelf { ui.showShelf = showShelf }
        if ui.showFocus != showFocus { ui.showFocus = showFocus }
        updateLyric(fileDrag: fileDrag)
        let question = fileDrag ? nil : activities.question
        if ui.question != question { ui.question = question }
        let rows = fileDrag ? 0 : min(activities.items.count, NotchState.maxActivities)
        if ui.activityRows != rows { ui.activityRows = rows }
        // A clock on the right: Foco's countdown, or how long the activity has been going.
        let timerShown = foco.session != nil || (!np.hasMedia && !activities.items.isEmpty && !activities.waiting)
        if ui.timerShown != timerShown { ui.timerShown = timerShown }
        let scale = CGFloat(min(max(Settings.shared.notchScale, 0.85), Double(NotchState.maxScale)))
        if ui.scale != scale { ui.scale = scale }
        if ui.level != nil && Date() >= levelUntil { ui.level = nil }

        let extended = NotchState.isExtended(np: np, shelf: shelf, foco: foco, activities: activities, mic: mic)
        var sz = ui.size(extended: extended)
        if ui.expanded { sz = CGSize(width: sz.width * scale, height: sz.height * scale) }
        let rect = NSRect(x: s.frame.midX - sz.width / 2, y: s.frame.maxY - sz.height, width: sz.width, height: sz.height)
            .insetBy(dx: -2, dy: -2)
        let mouse = NSEvent.mouseLocation
        // Open, it keeps a little slack below and beside it: reaching for the dots on its bottom edge
        // (or overshooting a button) isn't leaving.
        let inside = ui.expanded
            ? NSRect(x: rect.minX - 8, y: rect.minY - 16, width: rect.width + 16, height: rect.height + 16).contains(mouse)
            : rect.contains(mouse)
        // Magnetism: how close the cursor is to the closed notch, in steps so it redraws rarely.
        var near: CGFloat = 0
        if !ui.expanded && Settings.shared.magnetism {
            let dx = max(rect.minX - mouse.x, 0, mouse.x - rect.maxX)
            let dy = max(rect.minY - mouse.y, 0)
            near = (max(0, 1 - hypot(dx, dy) / 110) * 8).rounded() / 8
        }
        if ui.proximity != near { ui.proximity = near }
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
        let want = hovering || dragNear || camera.asking || now < mirrorHoldUntil || now < toastUntil || now < previewUntil
            || (now < peekUntil && (np.hasMedia || foco.session != nil || !activities.items.isEmpty))
        // Dragging a file in needs the drop zone, not the mirror; nor is there one with the add-on off.
        if ui.mirrorOn && (fileDrag || !Settings.shared.mirrorEnabled) { ui.mirrorOn = false }

        if want != ui.expanded {
            // Closing the notch closes the mirror, which turns the camera off.
            if !want && ui.mirrorOn { ui.mirrorOn = false }
            // It opens on the music again next time.
            if !want && ui.page != .main { ui.page = .main }
            ui.expanded = want
            if want {
                shelf.prune()
                if (hovering || dragNear) && Settings.shared.hapticsEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
        if inside { peekUntil = .distantPast }
        if ui.expanded && rows > 0 { activities.markSeen() }
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
    let activities = Activities()
    let mic = MicMonitor()
    let lid = LidSensor()
    static let micToggleRequested = Notification.Name("NotchUser.micToggleRequested")
    private var ocrHotKey: HotKey?
    private var micHotKey: HotKey?
    /// What lowering the lid did, so raising it undoes exactly that.
    private var lidPausedMusic = false
    private var lidMutedMic = false
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
            self?.controllers.forEach { $0.bump(); $0.ui.go(to: .shelf) }
            Haptics.play(.tap)
        }
        // A question from an agent stays up a little longer than a finished build.
        activities.onAttention = { [weak self] in
            // A question to pick from holds the notch longer than a yes/no.
            self?.peek(self?.activities.question != nil ? 25 : 6)
            self?.controllers.forEach { $0.ui.go(to: .activities) }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        activities.onFinish = { [weak self] done in
            guard let self else { return }
            let failed = done.contains { $0.state == .failed }
            // Commands with a known result (run through notch or NotchUser run) get the full signal;
            // agents finishing a turn and builds noticed in the background, just a tap.
            if done.contains(where: { $0.id.hasPrefix("notch-") || $0.id.hasPrefix("run-") }) {
                Haptics.play(failed ? .failure : .success)
                EdgeGlow.shared.flash(failed ? .systemRed : .systemGreen)
            } else {
                Haptics.play(.tap)
            }
            self.controllers.forEach { $0.bump(failed ? .red : .green) }
            self.peek(3)
        }
        // Answered: show the player coming back, then let the notch close if the mouse is away.
        activities.onAnswered = { [weak self] in
            self?.controllers.forEach { c in c.peekUntil = min(c.peekUntil, Date().addingTimeInterval(1.6)) }
        }
        DispatchQueue.global(qos: .utility).async { AgentHooks.upgrade() }
        activities.update()
        NotificationCenter.default.addObserver(forName: Settings.activitiesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.activities.update()
        }
        setUpAddOns()
        Lyrics.shared.attach(np)
        // Lines change on the song's beat, not the mouse loop's: tell the notches right away.
        Lyrics.shared.onChange = { [weak self] in self?.controllers.forEach { $0.updateLyric() } }
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
        // Gestures on the notch: scrolls over a notch window go to its controller first.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let c = self?.controllers.first(where: { $0.panel === e.window }) else { return e }
            return c.scroll(e) ? nil : e
        }
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
            controllers.append(NotchController(screen: s, np: np, shelf: shelf, foco: foco, camera: camera,
                                               activities: activities, mic: mic))
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
        guard let c = mainController else { return }
        c.ui.toast = toast
        c.toastUntil = Date().addingTimeInterval(seconds)
        c.bump(toast.ok ? .green : .orange)
        setTickRate(hot: true)
    }

    private var mainController: NotchController? {
        controllers.first(where: { $0.screen?.hasNotch == true }) ?? controllers.first
    }

    // MARK: Add-ons: microphone, lid, activities, quick actions

    private func setUpAddOns() {
        mic.update()
        lid.update()
        SettingsWindow.shared.lid = lid
        updateMicHotKey()
        let center = NotificationCenter.default
        center.addObserver(forName: Settings.micChanged, object: nil, queue: .main) { [weak self] _ in
            self?.mic.update()
            self?.updateMicHotKey()
        }
        center.addObserver(forName: Settings.lidChanged, object: nil, queue: .main) { [weak self] _ in self?.lid.update() }
        center.addObserver(forName: Self.micToggleRequested, object: nil, queue: .main) { [weak self] _ in self?.toggleMic() }
        center.addObserver(forName: Settings.previewRequested, object: nil, queue: .main) { [weak self] _ in
            guard let self, let c = self.mainController else { return }
            c.previewUntil = Date().addingTimeInterval(2.5)
            self.setTickRate(hot: true)
        }

        lid.onLowered = { [weak self] in
            guard let self else { return }
            if self.np.isPlaying && self.np.canControl {
                self.np.playPause()
                self.lidPausedMusic = true
            }
            if !self.mic.muted, self.mic.toggle() == true { self.lidMutedMic = true }
            if self.lidPausedMusic || self.lidMutedMic {
                self.showToast(.init(icon: "laptopcomputer", title: L("lidPaused"), detail: nil, ok: true))
            }
        }
        lid.onRaised = { [weak self] in
            guard let self else { return }
            if self.lidPausedMusic {
                self.lidPausedMusic = false
                if !self.np.isPlaying { self.np.playPause() }
            }
            if self.lidMutedMic {
                self.lidMutedMic = false
                if self.mic.muted { _ = self.mic.toggle() }
            }
        }

        QuickActions.onResult = { [weak self] toast in
            self?.showToast(toast, seconds: 3.2)
            Haptics.play(toast.ok ? .tap : .failure)
        }
    }

    private func updateMicHotKey() {
        micHotKey = Settings.shared.micEnabled
            ? HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey) { [weak self] in self?.toggleMic() }
            : nil
    }

    private func toggleMic() {
        switch mic.toggle() {
        case true?:
            showToast(.init(icon: "mic.slash.fill", title: L("micMuted"), detail: L("micMutedHint"), ok: false))
        case false?:
            showToast(.init(icon: "mic.fill", title: L("micLive"), detail: nil, ok: true))
        case nil:
            showToast(.init(icon: "mic.badge.xmark", title: L("micMuteFailed"), detail: nil, ok: false))
        }
        Haptics.play(.tap)
    }

    // MARK: notchuser:// (sent by the notch command, see Tools/notch)

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    /// notify, start, progress, done, clear and glow; values come as query items.
    private func handle(_ url: URL) {
        guard url.scheme == "notchuser", let action = url.host else { return }
        var q: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            if let v = item.value, !v.isEmpty { q[item.name] = v }
        }
        let id = q["id"] ?? "default"
        let ok = q["ok"].map { $0 == "1" || $0 == "true" || $0 == "ok" } ?? true
        switch action {
        case "notify":
            showToast(.init(icon: q["icon"] ?? (ok ? "bell.fill" : "exclamationmark.triangle.fill"),
                            title: q["title"] ?? "NotchUser", detail: q["detail"], ok: ok), seconds: 3.5)
            Haptics.play(ok ? .tap : .failure)
            if let g = q["glow"] { EdgeGlow.shared.flash(Self.color(g)) }
        case "start", "progress", "done":
            // Into the same folder as everything else, so they list, expire and alert like the rest.
            let fileID = "notch-" + id
            var a = ActivityFiles.read(fileID) ?? Activity(id: fileID, title: q["title"] ?? id, state: .running, started: Date())
            a.id = fileID
            if let v = q["title"] { a.title = v }
            if let v = q["detail"] { a.detail = v }
            if let v = q["icon"] { a.icon = v }
            if let v = q["value"].flatMap(Double.init) { a.progress = min(max(v, 0), 1) }
            if action == "done" {
                a.state = ok ? .done : .failed
                if ok { a.progress = nil }
            } else {
                if a.finished { a.started = Date() }
                a.state = .running
                a.icon = a.icon ?? "terminal.fill"
            }
            ActivityFiles.write(a)
            setTickRate(hot: true)
        case "clear":
            if let one = q["id"] {
                ActivityFiles.remove("notch-" + one)
            } else {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: ActivityFiles.dir.path)) ?? []
                for f in files where f.hasPrefix("notch-") && f.hasSuffix(".json") { ActivityFiles.remove(String(f.dropLast(5))) }
            }
        case "glow":
            EdgeGlow.shared.flash(Self.color(q["color"] ?? "white"))
        case "lyrics":
            // Opens (or closes) the lyrics view, e.g. from a keyboard shortcut in Shortcuts.
            guard Settings.shared.lyricsEnabled, let c = mainController else { return }
            c.ui.lyricsMode.toggle()
            if c.ui.lyricsMode { c.peekUntil = Date().addingTimeInterval(5) }
            setTickRate(hot: true)
        default:
            break
        }
    }

    /// A color name (green, red, orange, blue, purple, white) or #RRGGBB.
    private static func color(_ s: String) -> NSColor {
        switch s.lowercased() {
        case "green": return .systemGreen
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "pink": return .systemPink
        default:
            let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return .white }
            return NSColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
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
        controllers.forEach { $0.tick(fileDrag: fileDrag, np: np, shelf: shelf, foco: foco, activities: activities) }
        let viewing = controllers.contains { $0.ui.lyricsMode }
        if Lyrics.shared.viewing != viewing { Lyrics.shared.viewing = viewing }
        let mouse = NSEvent.mouseLocation
        setTickRate(hot: mouseDown || controllers.contains(where: { $0.isHot(mouse) }))
    }
}

@main
enum Main {
    static func main() {
        // `NotchUser run …`, `NotchUser claude-hook`…: a command-line call, not the app.
        if let code = CLI.run(Array(CommandLine.arguments.dropFirst())) { exit(code) }
        signal(SIGPIPE, SIG_IGN) // writing to a dead helper must not kill the app
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
