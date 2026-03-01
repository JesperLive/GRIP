<!-- Rev 2 -->
# GRIP – Guild Recruitment Automation

Target client: **Retail / Midnight**  
Interface: **120001** (build 12.0.1.66102)

GRIP assists guild recruitment by:

- Scanning `/who` results for **unguilded** characters
- Building a **Potential** list
- Whispering candidates (rate-limited queue)
- Sending guild invites (one per click/keybind; hardware-restricted)
- Queuing Trade/General recruitment posts (one per click/keybind; hardware-restricted)
- Blacklisting contacted/successful targets for configurable durations

---

## ⚠️ Blizzard Restrictions (Important)

Some actions require a **hardware event** (mouse click or key press).  
GRIP **cannot fully automate** the following:

- `/who` queries (`C_FriendList.SendWho()`)
- Guild invites (`GuildInvite()`)
- Posting to public channels (`SendChatMessage(..., "CHANNEL")`)

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

### Settings
- Adjust scan min/max/step
- Configure allowlists (zones / races / classes)
- Set whisper message (Save persists it)

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

Available under **Key Bindings → AddOns → GRIP**:

- Toggle GRIP window
- Send next `/who` scan
- Send next guild invite
- Send next Trade/General post

Keybindings satisfy hardware-event requirements for restricted actions.

---

## Slash Commands

- `/grip` — Toggle UI
- `/grip help` — Show help
- `/grip build` — Rebuild `/who` queue
- `/grip scan` — Send next `/who` query (hardware event)
- `/grip whisper` — Start/stop whisper queue
- `/grip invite` — Invite next candidate (hardware event)
- `/grip post` — Post next queued ad (hardware event)
- `/grip clear` — Clear Potential list
- `/grip status` — Print current counts
- `/grip minimap on|off|toggle` — Toggle minimap button

---

## Notes

- `/who` results are server-throttled; GRIP enforces a minimum delay between scans.
- Whispers are not hardware-restricted but are server rate-limited.
- Instance/battleground/scenario characters are excluded by default.
- Blacklist entries expire automatically based on configuration.
- Debug logging can be enabled via slash commands and optionally persisted to SavedVariables.