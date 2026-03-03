# GRIP – Guild Recruitment Automation

**Target:** Retail / Midnight (12.0.1+)
**Interface:** 120001
**Version:** 0.5.0-beta

---

## Features

- `/who` scanning for unguilded characters
- Whisper queue with rate limiting
- Guild invites (hardware-event gated, one per click/keybind)
- Trade/General post scheduling (hardware-event gated)
- Temp + permanent blacklisting with configurable duration
- Daily whisper cap (default 500/day) with 80% warning
- Opt-out response detection (auto-blacklists "no thanks" etc.)
- Multiple whisper templates with sequential/random rotation
- Sound feedback for key events (queue done, invite accepted, cap warning)
- Expansion-grouped zone filter with seasonal detection
- Minimap button + addon compartment support
- Ghost Mode (experimental) — full pipeline automation via invisible overlay frame
- Campaign cooldown — session fatigue protection with soft warning + hard auto-pause
- Account-wide blacklist — shared across all characters on the account

---

## Blizzard Restrictions (Important)

Some actions require a **hardware event** (mouse click or key press).
GRIP **cannot fully automate** the following:

- `/who` queries — `C_FriendList.SendWho()` (hardware event)
- Guild invites — `C_GuildInfo.Invite()` (hardware event)
- Channel posts — `C_ChatInfo.SendChatMessage(..., "CHANNEL")` (hardware event)

GRIP queues and organizes these actions and provides buttons/keybinds so you can trigger them safely and compliantly.

---

## Install

1. Copy the `GRIP` folder into:

   `World of Warcraft/_retail_/Interface/AddOns/GRIP/`

2. Restart WoW or run `/reload`.

---

## Quick Start

1. Type `/grip` to open the UI
   (or click the **minimap button**).

### Home
- **Scan** — Sends the next `/who` query (locks for configured minimum interval)
- **Whisper+Invite** — Starts whisper queue and sends **one invite**
- **Post Next** — Sends the next queued recruitment ad
- Daily cap status is shown on the Home page

### Settings
- Adjust level range for `/who` scans
- Configure zone/race/class filters (zones grouped by expansion)
- Edit whisper templates (multiple templates with rotation)
- Toggle sound feedback for individual events

### Ads
- Configure General and Trade messages
- Set post interval (scheduler queues messages only)
- Use **Post Next** to actually send

---

## Minimap Button

- **Left-click** — Toggle GRIP window (Home)
- **Middle-click** — Open Settings
- **Right-click** — Open Ads
- **Drag** — Move around minimap
- Hide/show: `/grip minimap on|off|toggle`

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
/grip help           — show help
/grip build          — rebuild /who queue
/grip scan           — send next /who (hardware event)
/grip whisper        — start/stop whisper queue
/grip invite         — whisper+invite next candidate (hardware event)
/grip post           — send next queued post (hardware event)
/grip clear          — clear Potential list
/grip status         — print counts
/grip link           — show guild name + Guild Finder link resolution

/grip minimap on|off|toggle

/grip permbl list|add|remove|clear

/grip set levels <min> <max> [step]
/grip set whisper <message>
/grip set general <message>
/grip set trade <message>
/grip set blacklistdays <n>
/grip set interval <minutes>
/grip set dailycap <n>
/grip set sound on|off
/grip set zoneonly on|off
/grip set hidewhispers on|off
/grip set ghostmode on|off

/grip templates list
/grip templates add <message>
/grip templates remove <n>
/grip templates rotation seq|random

/grip ghost start|stop|status
/grip set cooldown <min>|on|off

/grip debug on|off
/grip debug dump [n]
/grip debug clear
/grip debug copy [n]
/grip debug capture on|off [max]
/grip debug status

/grip zones diag|reseed|deep|export
/grip tracegate on|off|toggle
```

---

## Important Notes

- **Silence penalties:** If players report your whispers as spam, Blizzard may
  apply a Silence penalty to your account. Use conservative intervals and
  personalized messages to minimize risk.
- **Guild Finder listing:** The `{guildlink}` template token only works if your
  guild has an active listing in the Guild Finder. Without one, GRIP falls back
  to your guild name.
- **Not affiliated with Blizzard:** GRIP is a third-party addon. Use at your
  own discretion.

---

## Notes

- `/who` results are server-throttled; GRIP enforces a minimum delay between scans.
- Whispers are not hardware-restricted but are server rate-limited.
- Instance/battleground/scenario characters are excluded by default.
- Blacklist entries expire automatically based on configuration.
- Debug logging can be enabled via slash commands and optionally persisted to SavedVariables.
- Opt-out detection auto-blacklists candidates who reply with common refusal phrases.
- Daily whisper cap resets at midnight (calendar date).
- Sound cues can be toggled individually in Settings.
- Ghost Mode is experimental and disabled by default. Enable in Settings, then `/grip ghost start`.
- Blacklists and no-response counters are account-wide (shared across all characters). Config, potential list, and filters are per-character.
