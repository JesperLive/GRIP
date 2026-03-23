# GRIP – Guild Recruitment Automation

**Retail / Midnight 12.0.1+** · **v1.5.5** · **Localized (EN/DE/FR/ES)**

[![Discord](https://img.shields.io/badge/Discord-Tempting%20Us-7289da?logo=discord&logoColor=white)](https://discord.gg/temptingus) [![Sponsor](https://img.shields.io/badge/Sponsor-♥-ea4aaa)](https://paypal.me/jesperlive)

---

Stop manually `/who`-ing and whispering one player at a time. GRIP handles the entire recruitment pipeline — scanning, whispering, inviting, and posting — so you can focus on running your guild.

---

## Screenshots

| Home | Ghost Mode Active |
|:---:|:---:|
| ![Home](screenshots/home.png) | ![Ghost Mode](screenshots/ghost_active.png) |

| Settings | Settings (cont.) | Ads |
|:---:|:---:|:---:|
| ![Settings](screenshots/settings.png) | ![Settings 2](screenshots/settings_2.png) | ![Ads](screenshots/ads.png) |

---

## What GRIP Does

**Scan** → `/who` for unguilded players, auto-expanding saturated brackets by class

**Whisper** → Queue personalized messages with multiple templates and sequential/random rotation

**Invite** → One guild invite per click/keybind (Blizzard-compliant hardware-event gating)

**Post** → Schedule Trade and General channel recruitment ads on a timer

**Ghost Mode** → Full pipeline automation via invisible overlay — scan, whisper, invite, and post all drain through a single hardware-event queue

---

## Built for Safety

Guild leaders fear the Silence penalty. GRIP is designed around that reality.

- **Daily whisper cap** with 80% warning — hard stop before you hit risky territory
- **Opt-out detection** — "no thanks", "stop", profanity in EN/FR/DE/ES auto-blacklists the player
- **Invite-first mode** — only whisper players who successfully received your guild invite
- **Account-wide blacklist** — temp (auto-expiring) and permanent tiers, shared across all alts
- **Officer sync** — guild officers running GRIP share blacklists and templates automatically via addon comms
- **No-response escalation** — repeated ignores escalate from temp to permanent blacklist
- **Campaign cooldown** — built-in break timer with soft warning and hard auto-pause
- **Execution gate** — every whisper, invite, and post is checked against the blacklist at send time

---

## Smart Filtering

- **Zone filter** — expansion-grouped, dynamically populated from C_Map with seasonal zone detection
- **Race & class filters** — target exactly who you want
- **Raider.IO integration** — filter by M+ score when the [Raider.IO](https://www.curseforge.com/wow/addons/raiderio) addon is installed (optional, works fine without it)

---

## Tracking & Stats

- **30-day rolling stats** — whispers, invites, accepts, declines, opt-outs, posts, scans
- **Accept rate** and **peak hour analysis** — know when recruitment works best
- **Performance profiling** — `/grip perf` for baseline metrics

---

## Sharing & Sync

- **Officer blacklist sync** — set-union merge over GUILD addon channel (add-only, never removes)
- **Template sync** — share whisper templates with last-writer-wins resolution
- **Clipboard import/export** — encoded strings for cross-guild sharing

---

## Install

**CurseForge / Wago / WoWInterface** — search for "GRIP" or install via your addon manager.

**Manual install:**

1. Download the latest release from [GitHub Releases](https://github.com/JesperLive/GRIP/releases).
2. Extract the `GRIP` folder into:
   `World of Warcraft/_retail_/Interface/AddOns/GRIP/`
3. Restart WoW or run `/reload`.

---

## Quick Start

1. `/grip` to open the UI (or click the **minimap button**)
2. Set your level range and filters in **Settings**
3. Write your whisper templates (supports `{player}`, `{guild}`, `{guildlink}`)
4. Hit **Scan** → **Whisper+Invite** → **Post Next**

---

## Minimap Button

- **Left-click** — Toggle GRIP window (Home)
- **Middle-click** — Open Settings
- **Right-click** — Open Ads
- **Drag** — Move around minimap

---

## Keybindings

Available under **Key Bindings > AddOns > GRIP**:

- Toggle GRIP window
- Send next `/who` scan
- Send next guild invite
- Send next Trade/General post

Keybindings satisfy hardware-event requirements for restricted actions.

---

## Slash Commands

```
/grip                — toggle UI
/grip build          — rebuild /who queue
/grip scan           — send next /who
/grip whisper        — start/stop whisper queue
/grip invite         — whisper+invite next candidate
/grip post           — send next queued post
/grip status         — counts + blacklist breakdown
/grip stats [7d|30d] — recruitment stats summary
/grip perf [all]     — performance baseline metrics
/grip ghost start|stop|status
/grip sync on|off|now
/grip export bl|templates
/grip import
/grip templates list|add|remove|rotation
/grip set <key> <value>
/grip debug on|off|dump|clear|copy|capture|status
```

---

## Important Notes

- **Hardware events:** `/who`, guild invites, and channel posts require a mouse click or key press. This is a Blizzard restriction — GRIP queues the actions, you trigger them.
- **Guild Finder link:** The `{guildlink}` token needs an active Guild Finder listing. Falls back to guild name.
- **Raider.IO:** Requires the [Raider.IO](https://www.curseforge.com/wow/addons/raiderio) addon separately. Without it, the filter is skipped.
- **Officer sync:** Requires 2+ officers running GRIP. Uses GUILD addon channel — no external servers.
- **Localization:** English fully supported. DE/FR/ES translations welcome via CurseForge localization portal.
- **Not affiliated with Blizzard.** Use at your own discretion.

---

## License

![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)

GRIP is licensed under the [GNU General Public License v2](LICENSE).

---

**Feedback & Support:** [discord.gg/temptingus](https://discord.gg/temptingus)
