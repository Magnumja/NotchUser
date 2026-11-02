# Security policy

NotchUser runs on your Mac with access to things that matter: what's playing, files you drop on the shelf, the settings of your AI agents (Claude Code, Codex, Copilot) and, if you turn them on, the camera and the screen. Security reports are taken seriously and handled privately.

## Supported versions

Only the latest release gets security fixes. Please update before reporting: the fix may already be out.

| Version | Supported |
| --- | --- |
| Latest release ([releases](https://github.com/Magnumja/NotchUser/releases/latest)) | ✅ |
| Older versions | ❌ |

## Reporting a vulnerability

**Please don't open a public issue, pull request or discussion for a security problem.**

1. Go to the repository's **[Security](https://github.com/Magnumja/NotchUser/security) tab → Report a vulnerability** and send a private report. Only the maintainer can see it.
2. If that button isn't available, open an issue titled **"Security contact"** with no details at all, and you'll be given a private channel.

Include, as far as you can:

- The NotchUser version and your macOS version.
- What an attacker could do, and what they need (local access, a crafted file, a malicious web page, a song title…).
- Steps to reproduce, or a proof of concept.
- Any fix you'd suggest.

## What happens next

- **Within 7 days:** you get an answer confirming the report was received and whether it's accepted.
- **Within 30 days** (for confirmed issues): a fix is released, or you're told why it takes longer.
- You're credited in the release notes, unless you'd rather stay anonymous.

Please give the fix time to ship before talking about the issue publicly.

## Scope

Reports are especially welcome about:

- **The agent hooks:** what NotchUser writes into `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.copilot/hooks/`, and how it answers permission requests for an agent.
- **Local files:** the activities folder (`~/Library/Application Support/NotchUser/Activities`), the `notch` command and `notchuser://` links, and anything another app or web page could make the notch show or do.
- **The Now Playing helper:** `helper.m`, loaded into `/usr/bin/perl`.
- **The shelf:** files, links and text dropped on it, and its quick actions.
- **Network requests:** Spotify cover art, synced lyrics from LRCLIB, and the daily update check against the GitHub API.

Out of scope: problems that need someone to already control your Mac or your user account, and issues in macOS, Spotify, LRCLIB or the agents themselves (please report those to them).

---

### Em português

Encontrou uma falha de segurança? **Não abra uma issue pública.** Use a aba **[Security](https://github.com/Magnumja/NotchUser/security) → Report a vulnerability** pra mandar um relato privado. Se o botão não aparecer, abra uma issue chamada **"Security contact"** sem nenhum detalhe, e você recebe um canal privado. A resposta vem em até 7 dias, e a correção de falhas confirmadas em até 30 dias.
