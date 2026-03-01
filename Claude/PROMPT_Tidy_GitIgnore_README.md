# Code Prompt: Repo Tidy — .gitignore, README, Claude/ Hygiene

> **Context:** GRIP v0.4.0 | Retail / Midnight 12.0.1+ | Interface 120001
>
> **Purpose:** Clean up the repo so GitHub only contains addon-essential files, the root README is user-facing, stale Claude/ files are archived, and the Research_Index tracks completed work properly.

---

## Task 1 — Replace `.gitignore`

Replace the current `.gitignore` (which only has `*.ffs_db`) with a comprehensive one that excludes all non-addon files from Git tracking.

**Replace the entire contents of `.gitignore` with:**

```gitignore
# ── Development / AI research (local only) ──────────────────
CLAUDE.md
Claude/

# ── Docs folder (internal quick-start, changelog — local only) ──
Docs/

# ── Sync tool databases ─────────────────────────────────────
*.ffs_db

# ── OS junk ─────────────────────────────────────────────────
.DS_Store
Thumbs.db
Desktop.ini

# ── Editor / IDE ────────────────────────────────────────────
*.swp
*.swo
*~
.vscode/
.idea/
```

**After saving**, run these commands to remove the now-ignored files from Git tracking (without deleting them from disk):

```
git rm -r --cached Claude/
git rm --cached CLAUDE.md
git rm -r --cached Docs/
git rm --cached sync.ffs_db
```

> **Important:** `git rm --cached` only removes files from the Git index. They remain on disk untouched. The next commit will record their removal from the repo, and future commits won't include them.

---

## Task 2 — Replace Root `README.md`

Replace the entire contents of `README.md` (root, NOT `Docs/README.md`) with the following user-facing content:

```markdown
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
```

---

## Task 3 — Claude/ Folder Hygiene

### 3a — Delete completed PROMPT files

These prompts have been fully executed and verified. They're historical artifacts with no future use:

```
Claude/PROMPT_12_0_1_Fixes.md
Claude/PROMPT_Cleanup_March2026.md
Claude/PROMPT_GuildName_GuildLink_Fix.md
```

Delete all three files.

### 3b — Add correction header to Research_02

Research_02 contains two false claims that Research_07 corrects. Add a prominent warning at the top of `Claude/Research_02_Midnight_12_0_Changes.md`, immediately after the existing first line:

Insert after line 1 (`<!-- Rev 2 -->`):

```markdown

> ⚠️ **SUPERSEDED (2026-03-01):** This document contains two incorrect claims:
> 1. It says `GetChannelList()` was removed in 12.0 — **FALSE**, still available in 12.0.1
> 2. It says `ChatFrame_AddMessageEventFilter()` was removed in 12.0 — **FALSE**, still available in 12.0.1
>
> See **Research_07** for the corrected, verified API audit. All other content in this file remains accurate.

```

### 3c — Update Research_Index.md

Replace the entire contents of `Claude/Research_Index.md` with:

```markdown
# GRIP Research Index

> Compiled March 2026 for GRIP v0.4.0 targeting Retail / Midnight (12.0.1+).

---

## Documents

| # | Document | Focus | Status |
|---|----------|-------|--------|
| 01 | [API Reference](Research_01_API_Reference.md) | Full signatures, return types, quirks for every WoW API GRIP uses | ✅ Current |
| 02 | [Midnight / 12.0 Changes](Research_02_Midnight_12_0_Changes.md) | Deprecations, removals, additions since TWW/11.0 | ⚠️ Partially superseded by R07 |
| 03 | [Hardware Event Mechanics](Research_03_Hardware_Events.md) | What counts as a hardware event, propagation, taint system | ✅ Current |
| 04 | [Chat & Channel Throttling](Research_04_Chat_Throttling.md) | Rate limits on whispers, channels, /who — safe intervals, Silence system | ✅ Current |
| 05 | [Club Finder / Guild Finder API](Research_05_Club_Finder_API.md) | {guildlink} pipeline, fallback chain, reliability issues | ✅ Current |
| 06 | [Addon Policy & ToS](Research_06_Addon_Policy_ToS.md) | Blizzard rules, risk assessment, community context | ✅ Current |
| 07 | [12.0.1 API Audit](Research_07_12_0_1_Audit_March2026.md) | Verified API status for every GRIP dependency — corrects R02 errors | ✅ Current (authoritative) |
| 08 | [Codebase Cleanup Audit](Research_08_Codebase_Cleanup_March2026.md) | Header bloat, dead code, comment quality | ✅ Applied |
| 09 | [Guild Name & Guild Link Fix](Research_09_GuildName_GuildLink_Fix.md) | C_GuildInfo.GetGuildInfo doesn't exist, login timing, gsub leak | ✅ Applied |

---

## Completed Work

All items below have been implemented and verified:

- ✅ Replace `GuildInvite()` → `C_GuildInfo.Invite()` compat wrapper (R07)
- ✅ Fix `scanMaxLevel` fallback: 80 → 90 (R07)
- ✅ Strip revision headers from all .lua files (R08)
- ✅ Remove dead code: `STATIC_ZONES_BY_GROUP`, `U.AnySelected()` (R08)
- ✅ Fix `GetGuildName()` — remove dead API, improve cache, add events (R09)
- ✅ Fix `GetGuildFinderLink()` — cache with TTL, spam suppression (R09)
- ✅ Fix `ApplyTemplate()` — Lua gsub count leak (R09)
- ✅ Add `/grip debug copy` command (R09)

---

## Remaining Action Items

### Medium Priority
- Add Midnight zones to static zone list (Zul'Aman, Harandar, reimagined Eversong/Ghostlands)
- Byte-count messages, not char-count (emoji are multi-byte, 250-char message with emoji can exceed 255-byte limit)

### Low Priority
- Pass `origin` parameter to `C_FriendList.SendWho()` (optional but correct)
- Add Haranir to fallback race lists
- Consider daily whisper caps to protect users from Silence penalties
- Add `/grip link` debug command for {guildlink} troubleshooting
- Document for users that guild must have active Guild Finder listing for {guildlink}
```

### 3d — Delete this prompt file after execution

After all tasks are complete, delete `Claude/PROMPT_Tidy_GitIgnore_README.md` (this file) — it's a one-time prompt.

---

## Verification

After completing all tasks, provide the following:

### Git Commit (for GitHub Desktop)

```
Title: Repo tidy: .gitignore, README, Claude/ cleanup

Description:
- .gitignore now excludes Claude/, CLAUDE.md, Docs/, and sync files from GitHub
- Removed tracked Claude/ and Docs/ files from git index (files remain on disk)
- Replaced placeholder README.md with full user-facing documentation
- Deleted 3 completed PROMPT files from Claude/
- Added superseded warning to Research_02
- Updated Research_Index with status tracking and completed work log
```

### Cowork Verification

```
Cowork Verification:
- .gitignore: expanded from 1 rule to full exclusion set (Claude/, CLAUDE.md, Docs/, OS junk, editor files)
- git rm --cached: Claude/, CLAUDE.md, Docs/, sync.ffs_db removed from index (still on disk)
- README.md: replaced 2-line placeholder with full user-facing documentation (~120 lines)
- Deleted: PROMPT_12_0_1_Fixes.md, PROMPT_Cleanup_March2026.md, PROMPT_GuildName_GuildLink_Fix.md
- Research_02: added superseded warning header (R07 corrects two false claims)
- Research_Index.md: rebuilt with status column, completed work log, cleaned action items
- PROMPT_Tidy_GitIgnore_README.md: self-deleted after execution
```
