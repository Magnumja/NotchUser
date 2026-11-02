# Contributing to NotchUser

Thanks for helping make the notch useful. Bugs, ideas, translations and code are all welcome.

## Report a bug or ask for a feature

Open an [issue](https://github.com/Magnumja/NotchUser/issues/new/choose) and pick the form that fits. For bugs, the NotchUser version (Settings, under the app name), your macOS version and your Mac model help a lot.

Security problems go through the private channel in [SECURITY.md](SECURITY.md), never a public issue.

## Build it

Only the Xcode Command Line Tools are needed (`xcode-select --install`), no Xcode project.

```bash
zsh build.sh            # build, install into /Applications and open
zsh build.sh release    # build dist/NotchUser.zip
```

- `main.swift` is the whole app (SwiftUI + AppKit).
- `helper.m` reads the system's Now Playing.
- `Tools/notch` is the Terminal command.

## Send a pull request

1. Fork, then branch from `main`.
2. Keep the change focused: one fix or one feature per pull request.
3. Match the code around it: naming, comment style, no new dependencies.
4. Keep it light. NotchUser idles near 0.1% CPU; avoid timers that tick when nothing changes.
5. Run `zsh build.sh` and try the change on a real Mac. Say in the pull request what you tested, with a screenshot or a short video if it's visual.
6. New text in the app goes in all three languages (English, Português, Español). If you only speak one, write it in English and say so.

## Translations

Every piece of text lives in one table near the top of `main.swift`, with an `en`, `pt` and `es` entry each. A new language or a better translation is a great first pull request.

## Code of conduct

Be kind. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
