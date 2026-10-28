<p align="center">
  <img src="Assets/logo.png" width="340" alt="NotchUser">
</p>

<h3 align="center">Turn your MacBook's notch into a music player and a file shelf.</h3>

<p align="center">
  Native, featherweight, free and open source. No account, no tracking, no subscription.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Magnumja/NotchUser?style=flat-square&label=version&color=8A5CF6" alt="Latest version"></a>
  <a href="../../releases"><img src="https://img.shields.io/github/downloads/Magnumja/NotchUser/total?style=flat-square&color=EA7A4E" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-3A7BF0?style=flat-square" alt="Universal binary">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Magnumja/NotchUser?style=flat-square&color=2EA043" alt="MIT license"></a>
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/Magnumja/NotchUser?style=flat-square&color=F5C542" alt="Stars"></a>
</p>

<p align="center">
  <a href="../../releases/latest/download/NotchUser.zip"><b>⬇ Download NotchUser for Mac</b></a>
  &nbsp;·&nbsp;
  <a href="README.pt-BR.md">Leia em português</a>
</p>

<p align="center">
  <img src="Assets/screens/hero.png" width="820" alt="NotchUser open under the notch, playing a song from Spotify">
</p>

<p align="center">
  <a href="Assets/video/NotchUser-Promo.mp4"><img src="Assets/video/poster.png" width="640" alt="Play the 30-second NotchUser film"></a>
  <br><sub>🎬 <a href="Assets/video/NotchUser-Promo.mp4"><b>Watch the 30-second film</b></a>: music, the shelf and the three styles in motion.</sub>
</p>

---

## Why NotchUser

The notch is dead space in the middle of your menu bar. NotchUser puts it to work, and it looks like it was always meant to be there.

- **Hover, and it opens.** Cover art, progress, and playback controls grow out of the notch, then tuck back in when the mouse leaves.
- **Works with what you already use.** Spotify, Apple Music, and anything playing in the browser (YouTube, SoundCloud, streaming sites). Several at once? It follows whichever started last, and you can switch.
- **A shelf for the things you're moving around.** Drag files, links, or text to the notch, then drag them out wherever they need to go: WhatsApp, Mail, Finder, AirDrop.
- **Light enough to forget about.** With music playing and the notch closed it uses **~0% CPU and about 30 MB of memory**. The animations run in Core Animation, inside macOS itself.

<p align="center">
  <img src="Assets/screens/closed.png" width="820" alt="The closed notch showing the album cover and a wave in the album's color">
  <br><sub>Closed, it stays out of the way: the cover on one side, a wave in the album's color on the other.</sub>
</p>

## Three styles

<p align="center">
  <img src="Assets/screens/styles.png" width="900" alt="The three styles side by side: Basic, Elevated and Glass">
</p>

| Style | What it feels like |
| --- | --- |
| **Basic** | Pure black, as if it were part of the hardware. |
| **Elevated** | Layered shadows, controls in relief, a glow in the album's color under the notch, and a cover that tilts toward your mouse. |
| **Glass** | Apple's Liquid Glass (macOS 26+): see-through panel, glass shelf and controls, and waves in the album's color that follow the music. |

Pick one in the welcome tour, in Settings, or with a right-click on the notch → **Appearance**.

## Everything it does

**Music**
- Cover, title, artist, scrubbable progress bar, previous / play-pause / next.
- Click the cover to open the app that's playing; app icons in the corner switch between sources.
- Long titles slide into view when you hover them.
- A small hop when the song changes, without popping open (you can turn that on in Settings).

**Shelf**
- Files, links and text, with thumbnails. Click to select several and drag them all out together.
- Right-click for Open, Show in Finder, Copy, AirDrop. Files that were moved or deleted disappear on their own.
- While you drag something, a large drop zone opens below the notch, so you never hit the top edge by accident.

<p align="center">
  <img src="Assets/screens/shelf.gif" width="640" alt="Dragging a file into the notch shelf and out into another folder">
  <br><sub>Drag. Drop. Done.</sub>
</p>

**Optional add-ons** (off until you turn them on)
- **Copy text from the screen:** press **⌘⇧2**, select any area (a video, an image, a locked PDF, a slide in a call), and its text goes to the clipboard. Recognition runs on your Mac; the image is deleted right after.
- **Camera mirror:** click the notch to check yourself before a call. The camera is only on while the mirror is open.
- **Bluetooth headphones in high quality:** keeps the MacBook's mic as input, so headphones never drop to "call quality."

**And also**
- A pill at the top of external displays, which have no notch.
- English, Português, and Español, or follow the Mac's language.
- A welcome tour that asks for every permission in one place, all of them optional.

## Install

1. Download **[NotchUser.zip](../../releases/latest/download/NotchUser.zip)**, unzip it, and drag **NotchUser.app** to **Applications**.
2. The app isn't signed with a paid Apple developer account, so the first time macOS will block it:
   - **Right-click the app → Open → Open**, or
   - on recent macOS: **System Settings → Privacy & Security → Open Anyway**.

   If macOS says the app is "damaged," run this once and open it again:
   ```bash
   xattr -dr com.apple.quarantine /Applications/NotchUser.app
   ```
3. A short welcome tour lets you pick the language and style, turn on add-ons, and grant permissions.

Requires **macOS 14 Sonoma or later**, on Apple Silicon or Intel.

## How to use it

| Where | What to do |
| --- | --- |
| Notch | Hover to open · right-click for styles, options, **Settings…** and **Quit** |
| Album cover | Click to open the app that's playing |
| Icons in the player's corner | Switch between Spotify, the browser, Music… |
| Shelf | Click to select · double-click to open · drag out · right-click for more |
| Anywhere | **⌘⇧2** copies text from the screen (with the add-on on) |

## Privacy

- **No account, no analytics, no tracking.** NotchUser doesn't send anything anywhere.
- Its only network request downloads the Spotify cover art from Spotify's own servers.
- Text recognition runs on your Mac with Apple's Vision framework, and the captured image is deleted immediately.
- Each permission (Automation for Spotify/Music, Camera, Screen Recording) is only requested for the feature that needs it.

## Performance

Measured on a MacBook with music playing:

| | Notch closed | Notch open |
| --- | --- | --- |
| CPU | ~0.0–0.1% | only the progress bar updates while you look at it |
| Memory | ~30 MB | — |

The bars and waves are handed to Core Animation once and played by macOS. The app doesn't redraw itself to animate them. Mouse tracking slows down to 4 checks a second when the cursor is far from the notch.

## Also for Linux and Windows

- **Ubuntu and other GNOME distros:** [NotchUser-Linux](https://github.com/Magnumja/NotchUser-Linux), a GNOME Shell extension.
- **Windows 10/11:** [NotchUser-Windows](https://github.com/Magnumja/NotchUser-Windows), a pill at the top of the screen.

## Build from source

Only the Xcode Command Line Tools are needed (`xcode-select --install`), not the full Xcode.

```bash
zsh build.sh            # build, install into /Applications and open
zsh build.sh release    # build dist/NotchUser.zip to share
```

| File | What it is |
| --- | --- |
| `main.swift` | The whole app (SwiftUI + AppKit). |
| `helper.m` | Reads the system's "Now Playing" (see below). |
| `Tools/make_icon.swift` | Makes the app icon from `Assets/logo.png`. |
| `Tools/make_gif.swift` | Turns a screen recording into a GIF. |

### How it reads music from the browser

Since macOS 15.4, only Apple's own apps may read the system's "Now Playing" (the private MediaRemote framework). NotchUser uses the same approach as other notch apps: a small helper (`helper.m`) is loaded by `/usr/bin/perl`, which is signed by Apple, and passes title, artist, time, and cover art back to the app. It doesn't change any system setting.

**Heads-up:** this is an unofficial path and Apple may close it in an update. If that happens, NotchUser keeps working with Spotify and Apple Music (through AppleScript); only the browser part stops.

## Contributing

Issues and pull requests are very welcome, whether it's a bug, an idea, or a translation. If NotchUser made your notch more useful, **a ⭐ on the repo helps other people find it.**

## License

[MIT](LICENSE). Use it, change it, share it.
