# GRIP – Guild Recruitment Automation

**Automate the grind, not the game.**

GRIP streamlines guild recruitment in World of Warcraft Retail by scanning for unguilded players, queuing whispers and guild invites, and scheduling Trade/General channel ads — all while fully respecting Blizzard's hardware-event restrictions.

> **Version:** 0.4.0 · **Interface:** 120001 (Midnight 12.0.1+)

---

## Features

- **/who Scanning** — Automatically queries `/who` by level bracket, expands saturated results by class, and filters out already-contacted or blacklisted players.
- **Whisper Queue** — Rate-limited outgoing whispers with customizable message templates. Supports `{name}`, `{guild}`, and clickable `{guildlink}` tokens.
- **Guild Invite Pipeline** — One invite per click/keybind (hardware-event compliant). Tracks no-responses and escalates repeat ignores to temp → permanent blacklist.
- **Trade/General Ad Scheduler** — Configure separate messages for Trade and General chat. Posts are queued on a timer; you trigger them with a click or keybind.
- **Smart Blacklisting** — Two-tier system: temporary (configurable expiry in days) and permanent (with reason tracking). The Execution Gate blocks every whisper, invite, and post for blacklisted names.
- **Minimap Button** — Left-click to toggle UI, middle-click for Settings, right-click for Ads. Draggable.
- **Full Keybind Support** — Bind Toggle UI, Scan, Invite, and Post to any key combo via WoW's Key Bindings menu.

---

## Installation

1. Download or clone this repository.
2. Copy the `GRIP` folder into your WoW addons directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/GRIP/
   ```
3. Restart WoW or type `/reload`.

---

## Quick Start

1. Open the GRIP window: `/grip` or click the minimap button.
2. **Settings tab** — Set your level range, select which zones/races/classes to target, and write your whisper message.
3. **Home tab** — Click **Scan** to run a `/who` query. Candidates appear in the Potential list. Click **Whisper+Invite** to start the recruitment pipeline.
4. **Ads tab** — Write your Trade and General channel messages, set the post interval, and click **Post Next** when the queue is ready.

---

## Slash Commands

| Command | Description |
|---|---|
| `/grip` | Toggle the GRIP window |
| `/grip help` | Show all available commands |
| `/grip build` | Rebuild the `/who` scan queue |
| `/grip scan` | Send the next `/who` query |
| `/grip whisper` | Start or stop the whisper queue |
| `/grip invite` | Whisper + invite the next candidate |
| `/grip post` | Send the next queued Trade/General post |
| `/grip clear` | Clear the Potential list |
| `/grip status` | Print current queue counts |
| `/grip minimap on\|off` | Show or hide the minimap button |

See `/grip help` in-game for the full list, including debug, blacklist management, and zone diagnostic commands.

---

## How It Works

```
/who scan → Potential list → Whisper queue → Guild invite → Finalize/Blacklist
                                          ↗
            Trade/General post scheduler ─┘
```

GRIP never bypasses Blizzard's restrictions. Actions that require a **hardware event** (mouse click, keybind, or slash command) — like `/who` queries, guild invites, and channel posts — are queued and only fire when you trigger them. Whispers are not hardware-restricted and drain automatically on a timer.

---

## Blizzard Compliance

GRIP is designed to work within Blizzard's addon policies:

- **Hardware-event gating** — Restricted APIs (`C_FriendList.SendWho`, `C_GuildInfo.Invite`, channel `SendChatMessage`) only execute from genuine player input.
- **Rate limiting** — Whispers, scans, and posts all enforce minimum intervals to stay well within server throttle limits.
- **No automation of restricted actions** — GRIP queues and organizes; you press the button.

---

## Configuration

All settings are saved per-account in `WTF/Account/<name>/SavedVariables/GRIP.lua` and persist across sessions.

Key options (configurable via Settings tab or `/grip set`):

- **Level range** and step size for `/who` brackets
- **Zone/Race/Class filters** — allowlists to narrow scan targets
- **Whisper message** — with template tokens (`{name}`, `{guild}`, `{guildlink}`)
- **Post messages** — separate templates for Trade and General chat
- **Post interval** — minutes between queued ads
- **Blacklist duration** — days before temp blacklist entries expire

---

## License

All rights reserved. This addon is provided as-is for personal use.
