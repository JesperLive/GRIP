# GRIP – Guild Recruitment Automation

> **Version:** 0.4.0
> **Interface:** 120001 (Retail / Midnight 12.0.1+)
> **SavedVariables:** `GRIPDB`
> **Author:** GRIP
>
> **Before starting work, also read:** all `.md` files in the `Claude/` folder — these contain WoW API references, recent game changes, and design research that inform how this addon should be built.

GRIP automates the guild recruitment pipeline in World of Warcraft Retail. It scans `/who` for unguilded characters, queues whispers and guild invites, and schedules Trade/General channel recruitment posts — all while respecting Blizzard's hardware-event restrictions.

---

## Research & Reference Docs

The `Claude/` folder contains compiled research and API references. **Read the relevant file(s) before working on tasks that touch those areas.**

| File | When to Read |
|---|---|
| `Claude/API_REFERENCE.md` | Any task involving WoW API calls — check here for correct signatures, return values, and quirks |
| `Claude/MIDNIGHT_CHANGES.md` | Before using any API that may have changed in 12.0 — deprecations, replacements, new features |
| `Claude/HARDWARE_EVENTS.md` | Any task involving restricted APIs (SendWho, GuildInvite, CHANNEL sends) |
| `Claude/DESIGN_DECISIONS.md` | Before refactoring or questioning "why is it done this way?" |
| `Claude/ADDON_POLICIES.md` | Before adding features that interact with other players (whispers, invites, chat) |
| **`Claude/Research_07_12_0_1_Audit_March2026.md`** | **READ FIRST for any 12.0.1 work — corrects errors in earlier research, has verified API status for every GRIP dependency** |

See `Claude/README.md` for the full index and how to add new research files.

> ⚠️ **Important (2026-03-01):** Research_02 (Midnight Changes) contains two incorrect claims — it says `GetChannelList()` and `ChatFrame_AddMessageEventFilter()` were removed in 12.0. They were NOT. Both are still available and working in 12.0.1. See Research_07 for the corrected information and full API audit.

---

## Project Structure

```
GRIP/
├── GRIP.toc                  # Load order manifest (Rev 10)
├── Bindings.xml              # Keybind definitions (Rev 3)
│
├── Core/
│   ├── Core.lua              # Bootstrap, version, state, logger wrapper (Rev 8)
│   ├── Debug.lua             # Logger capture + SV ring buffer (Rev 5)
│   ├── Utils.lua             # Shared helpers, template engine, chat compat (Rev 10)
│   ├── GhostMode.lua         # Hardware-event gated chat send queue (Rev 2)
│   ├── Slash.lua             # /grip command handler (Rev 6)
│   └── Events.lua            # Event wiring — loads LAST in TOC (Rev 7)
│
├── Data/
│   └── Maps_Zones.lua        # Static shipped zone list + exclude patterns (Rev 2)
│
├── DB/
│   ├── DB_Util.lua           # Merge, list helpers, filter pruning (Rev 2)
│   ├── DB_Zones.lua          # Zone gathering, deep scan, export (Rev 3)
│   ├── DB_Init.lua           # SavedVariables defaults + EnsureDB (Rev 7)
│   ├── DB_Blacklist.lua      # Temp/perm blacklist + BL_ExecutionGate (Rev 8)
│   ├── DB_Filters.lua        # Candidate filtering (zones/races/classes) (Rev 2)
│   └── DB_Potential.lua      # Potential list add/remove/finalize (Rev 3)
│
├── Hooks/
│   └── UnitPopupInvite.lua   # Right-click "Invite to Guild" hook (Rev 2)
│
├── Recruit/
│   ├── Who.lua               # /who scanning + auto-expand saturated brackets (Rev 8)
│   ├── Whisper.lua           # Whisper queue + rate limiting (Rev 7)
│   ├── Invite.lua            # Guild invite pipeline + no-response timeout (Rev 11)
│   └── Post.lua              # Trade/General post scheduler (Rev 6)
│
├── UI/
│   ├── UI_Widgets.lua        # Reusable components (checkboxes, edits, checklists, scroll pages) (Rev 5)
│   ├── UI_Home.lua           # Home page: potential list, blacklist panel, action buttons (Rev 19)
│   ├── UI_Settings.lua       # Settings page: level range, filters, whisper editor (Rev 12)
│   ├── UI_Ads.lua            # Ads page: General/Trade message config, post scheduler (Rev 5)
│   ├── UI.lua                # UI controller: frame, tabs, page routing, resize (Rev 10)
│   └── Minimap.lua           # Minimap button with drag positioning (Rev 9)
│
└── Docs/
    ├── README.md             # Quick start guide
    └── CHANGELOG.md          # Version history

├── Claude/                         # Research & reference (NOT loaded by WoW)
│   ├── README.md                 # Index of all research files
│   ├── API_REFERENCE.md          # WoW API details relevant to GRIP
│   ├── MIDNIGHT_CHANGES.md       # 12.0 breaking changes / new APIs
│   ├── HARDWARE_EVENTS.md        # Hardware-event restriction deep dive
│   ├── DESIGN_DECISIONS.md       # Architecture rationale and tradeoffs
│   └── ADDON_POLICIES.md        # Blizzard addon policies & ToS notes
```

### TOC Load Order (Critical)

Files load in this exact sequence. Dependencies flow downward — a file can only call functions defined in files above it.

```
Core/Core.lua           ← bootstrap: GRIP table, state, logger, keybinds
Core/Debug.lua          ← overrides Logger.Capture
Core/Utils.lua          ← Now(), ApplyTemplate, SendChatMessageCompat, GlobalStringToPattern
Core/GhostMode.lua      ← optional module (inert unless config flag set)
Data/Maps_Zones.lua     ← GRIP.STATIC_ZONES, exclude patterns/exact lists
DB/DB_Util.lua          ← Merge, EnsureInList, SortUnique, PruneFilterKeys
DB/DB_Zones.lua         ← zone gathering, deep scan, ShouldIncludeZoneName
DB/DB_Init.lua          ← EnsureDB (merges defaults, seeds lists, migrates SV schema)
DB/DB_Blacklist.lua     ← IsBlacklisted, BL_ExecutionGate, Blacklist, BlacklistPermanent
Hooks/UnitPopupInvite.lua ← right-click guild invite (depends on blacklist gate)
DB/DB_Filters.lua       ← FiltersAllowWhoInfo
DB/DB_Potential.lua     ← AddPotential, RemovePotential, MaybeFinalize
Recruit/Who.lua         ← BuildWhoQueue, SendNextWho, ProcessWhoResults
Recruit/Whisper.lua     ← whisper queue management
Recruit/Invite.lua      ← invite pipeline + no-response timeout
Recruit/Post.lua        ← post scheduler + queue management
UI/UI_Widgets.lua       ← reusable widget constructors
UI/UI_Home.lua          ← home page (potential list, blacklist panel)
UI/UI_Settings.lua      ← settings page (filters, whisper editor)
UI/UI_Ads.lua           ← ads page (post messages, scheduler)
UI/UI.lua               ← main frame, tabs, page routing
UI/Minimap.lua          ← minimap button
Core/Slash.lua          ← /grip command registration
Core/Events.lua         ← event frame (ADDON_LOADED, PLAYER_LOGIN, WHO_LIST_UPDATE, etc.)
```

---

## Architecture Overview

### Addon Table Pattern

All modules share state through the addon table `GRIP` (passed via `local ADDON_NAME, GRIP = ...`). Runtime state lives in `GRIP.state`. Persisted data lives in `_G.GRIPDB` (SavedVariables).

### Recruitment Pipeline

```
/who scan → Potential list → Whisper queue → Invite → Finalize/Blacklist
                                          ↗
            Trade/General post scheduler ─┘ (independent channel)
```

1. **Who.lua** — Sends `/who` queries by level bracket. Auto-expands saturated results (50/50) by class. Filters through `FiltersAllowWhoInfo` and `BL_ExecutionGate` before adding to Potential.
2. **Whisper.lua** — Drains whisper queue with configurable delay. Uses `SendChatMessageCompat` (not hardware-restricted). Tracks pending whispers for system message attribution.
3. **Invite.lua** — Hardware-event gated (`GuildInvite` is restricted). One invite per click/keybind. 70-second no-response timeout. Escalates repeat no-responses to 24h temp blacklist, then permanent.
4. **Post.lua** — Schedules Trade/General channel messages. Queue is populated by ticker; actual send requires hardware event (`SendChatMessage` to CHANNEL is restricted). Ghost Mode can queue these further.

### Blacklist System (Critical Safety Layer)

Two tiers:
- **Temp blacklist** (`GRIPDB.blacklist`): `[fullName] = expiryEpochSeconds` — auto-expires, configurable days.
- **Perm blacklist** (`GRIPDB.blacklistPerm`): `[fullName] = { at=epoch, reason="string" }` — for players who ignored us, or manually added.

**BL_ExecutionGate** (`DB_Blacklist.lua`) is the "last-line defense" — called immediately before every whisper, invite, or post execution. It checks all name variants (Name, Name-Realm, base name). If blocked, execution is refused. Every pipeline module calls this gate; it is not optional.

### Ghost Mode (Optional)

Off by default. When enabled, CHANNEL sends are queued and only flushed from hardware events. Phase 1 scope: only CHANNEL sends are routed through Ghost Mode; whispers/SAY/YELL remain direct.

---

## Hardware-Event Restrictions (Blizzard)

These WoW APIs require a hardware event (mouse click, keybind press, or `/slash` command) in the call stack:

| API | Used By | Gate |
|---|---|---|
| `C_FriendList.SendWho()` | Who.lua | Keybind / slash / button click |
| `GuildInvite()` | Invite.lua, UnitPopupInvite.lua | Keybind / slash / button click |
| `SendChatMessage(..., "CHANNEL", ...)` | Post.lua | Keybind / slash / button click |

**Non-restricted** (can be called from tickers/timers): `SendChatMessage(..., "WHISPER", ...)`, most C_Map/C_GuildInfo/C_Club APIs.

Never attempt to circumvent hardware-event requirements. Code that runs from `C_Timer.After`, `C_Timer.NewTicker`, or event handlers CANNOT call restricted APIs.

---

## SavedVariables Schema (GRIPDB)

```lua
GRIPDB = {
  config = {
    enabled = true,
    -- /who scan
    scanMinLevel = 1, scanMaxLevel = 90, scanStep = 5,
    scanZoneOnly = false, suppressWhoUI = true,
    -- Whisper
    whisperEnabled = true, whisperMessage = "...", whisperDelay = 2.5,
    suppressWhisperEcho = false,  -- alias: hideOutgoingWhispers
    -- Invite
    inviteEnabled = true, blacklistDays = 7,
    -- Posts
    postEnabled = true, postIntervalMinutes = 15,
    postMessageGeneral = "...", postMessageTrade = "...", postQueueMax = 20,
    -- Throttles
    minWhoInterval = 15, minPostInterval = 8,
    -- Debug
    debug = false, debugVerbosity = 2, debugWindowName = "Debug",
    debugMirrorPrint = true, debugPersist = false, debugPersistMax = 800,
    debugCapture = false, debugCaptureMax = 800,  -- aliases for debugPersist*
    -- Gate trace
    traceExecutionGate = false,
    -- Ghost Mode
    ghostModeEnabled = false,
  },
  minimap = { hide = false, angle = 225 },
  lists = { zones = {}, zonesAll = {}, races = {}, classes = {} },
  filters = { zones = {}, races = {}, classes = {} },
  potential = {},           -- [fullName] = { name, level, class, race, area, ... }
  blacklist = {},           -- [fullName] = expiryEpochSeconds (temp)
  blacklistPerm = {},       -- [fullName] = { at=epoch, reason="..." } (permanent)
  counters = { noResponse = {} },  -- [fullName] = count
  debugLog = { lines = {}, dropped = 0, lastAt = "" },
}
```

### Config Alias Pairs (kept in sync by DB_Init + Debug.lua)

- `suppressWhisperEcho` ↔ `hideOutgoingWhispers`
- `debugPersist` ↔ `debugCapture`
- `debugPersistMax` ↔ `debugCaptureMax`

When changing one, always set both, or call `NormalizeConfigAliases`.

---

## Coding Conventions

### Nil-Safety First

Every module guards against missing `GRIPDB`, missing sub-tables, and nil inputs. Pattern:

```lua
local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
end
```

Always check before indexing: `if not _G.GRIPDB or type(GRIPDB.potential) ~= "table" then return end`

### Shared State Access

- `GRIP.state` — runtime-only (clears on reload). Contains queues, pending maps, tickers, UI refs.
- `_G.GRIPDB` — persisted (SavedVariables). Config, potential list, blacklists, counters, debug log.

### Name Key Handling

WoW names can be `"Name"` or `"Name-Realm"`. All blacklist/potential lookups must handle both variants. `CollectBlacklistKeys()` in DB_Blacklist.lua and `BuildNameKeyVariants()` in Who.lua handle expansion. Always use full `Name-Realm` as the canonical key where possible.

### Debug Logging

```lua
GRIP:Debug(...)   -- level 2, general debug
GRIP:Trace(...)   -- level 3, verbose
GRIP:Info(...)    -- level 1, important
GRIP:Print(msg)   -- always shown in default chat (green "GRIP:" prefix)
```

Logger outputs to a dedicated chat window (default name: "Debug"). Falls back to DEFAULT_CHAT_FRAME. Optionally persists plain-text lines to `GRIPDB.debugLog` for copy/paste from WTF folder.

### Template Engine

`GRIP:ApplyTemplate(template, targetFullName)` replaces:
- `{player}` / `{name}` → short name (no realm)
- `{guild}` → guild name
- `{guildlink}` → clickable Club Finder link (with fallback to guild name)

The `{guildlink}` token gets special "non-droppable" treatment: space is reserved so truncation at 250 chars doesn't clip the link.

### Chat Send Routing

All chat sends go through `GRIP:SendChatMessageCompat(msg, chatType, languageID, target)`:
- Sanitizes via `SafeTruncateChat` (250 char limit, strip newlines)
- Skips blank messages
- Handles whisper echo suppression buffer
- Routes CHANNEL sends through Ghost Mode when enabled
- Falls back from `C_ChatInfo.SendChatMessage` to `SendChatMessage`

### Error-Safe Pattern Matching

`GRIP:GlobalStringToPattern(gs)` converts WoW GlobalStrings (like `ERR_GUILD_JOIN_S`) into Lua patterns. Events.lua uses `NormGS()` to strip grammar tokens (`|3-6(%s)`) first.

---

## UI Architecture

### Frame Hierarchy

```
GRIPFrame (DIALOG strata, movable, resizable, min 560×420)
├── Tab buttons: Home | Settings | Ads
├── Page container
│   ├── HomePage (FauxScrollFrame for potential list + blacklist panel)
│   ├── SettingsPage (ScrollFrame with filter checklists + whisper editor)
│   └── AdsPage (ScrollFrame with General/Trade message editors + scheduler)
└── Minimap button (LibDBIcon-style ring anchor)
```

### UI Patterns

- **UI_Widgets.lua** provides constructors: `MakeCheckbox`, `MakeMultiLineEdit`, `MakeChecklist`, `MakeScrollPage`.
- **Dirty tracking** on edit boxes: `eb._gripDirty` prevents ticker/refresh from overwriting user-in-progress edits.
- **Programmatic sets**: `eb._gripProgrammatic = true` before `SetText()`, checked in `OnTextChanged` to distinguish user vs code changes.
- **Responsive layout**: Pages have `LayoutForWidth(w)` hooks called on resize (throttled/coalesced).
- **UpdateUI coalescing**: `GRIP:UpdateUI()` is throttled to prevent refresh storms from rapid events/tickers.
- **Modal behavior**: While GRIP UI is shown, all keystrokes are swallowed (`SetPropagateKeyboardInput(false)`) so WASD/etc. don't move the character. ESC closes UI without opening Game Menu.

---

## Key Keybinds (Bindings.xml)

| Binding | Function | Notes |
|---|---|---|
| `GRIP_TOGGLE` | `GRIP_ToggleUI()` | Show/hide main UI |
| `GRIP_WHO_NEXT` | `GRIP_WhoNext()` | Send next /who scan (hardware event) |
| `GRIP_INVITE_NEXT` | `GRIP_InviteNext()` | Send next guild invite (hardware event) |
| `GRIP_POST_NEXT` | `GRIP_PostNext()` | Send next Trade/General post (hardware event) |

---

## Slash Commands (/grip)

```
/grip                - toggle UI
/grip build          - rebuild /who queue
/grip scan           - send next /who (hardware event)
/grip whisper        - start/stop whisper queue
/grip invite         - whisper+invite next candidate (hardware event)
/grip post           - send next queued post (hardware event)
/grip clear          - clear Potential list
/grip status         - print counts
/grip permbl list|add|remove|clear   - manage permanent blacklist
/grip tracegate on|off|toggle        - execution gate diagnostics
/grip debug on|off
/grip debug dump [n]
/grip debug clear
/grip debug capture on|off [max]
/grip debug status
/grip zones diag|reseed|deep [maxMapID]|deep stop|export
/grip minimap on|off|toggle
/grip set whisper|general|trade|blacklistdays|interval|zoneonly|levels|debugwindow|verbosity|hidewhispers
```

---

## Common Development Tasks

### Adding a New Config Key

1. Add default value to `DEFAULT_DB.config` in **DB_Init.lua**.
2. If it has aliases, add sync logic in `NormalizeConfigAliases()`.
3. Add slash command toggle in **Slash.lua** `HandleSlash()`.
4. Add UI control in the appropriate settings page.

### Adding a New Pipeline Stage

1. Create `Recruit/NewStage.lua`.
2. Add to GRIP.toc in the Recruit section (after its dependencies).
3. Wire events/callbacks in Events.lua if needed.
4. Call `BL_ExecutionGate()` immediately before any restricted action.
5. Track pending state in `GRIP.state` (runtime only, cleared on reload).
6. Call `GRIP:UpdateUI()` after state changes.

### Adding a New UI Page

1. Create `UI/UI_NewPage.lua` with a `GRIP:CreateNewPage(parent)` constructor.
2. Add to GRIP.toc before `UI/UI.lua`.
3. Add tab button and page routing in UI.lua's `CreateUI()`.
4. Add a `LayoutForWidth(w)` hook if the page needs responsive behavior.

---

## WoW API Notes

> **Updated 2026-03-01 for 12.0.1 (66192).** See `Claude/Research_07_12_0_1_Audit_March2026.md` for full audit.

- **`C_FriendList.SendWho(filter [, origin])`** — requires hardware event. Filter format: `"1-10"`, `"1-10 c-\"Warrior\""`, `"1-10 z-\"Stormwind City\""`. Optional `origin` param (Enum.SocialWhoOrigin) added in 10.2.0.
- **`C_FriendList.GetNumWhoResults()`** — returns `(numWhos, totalCount)`. Some clients swap these; `NormalizeWhoCounts()` handles it.
- **`C_GuildInfo.Invite(name)`** — **preferred** guild invite API (replaces `GuildInvite`). Requires hardware event. Same restrictions as old API.
- **`GuildInvite(fullName)`** — **deprecated since 10.2.6**. Still works in 12.0.1 but will be removed. Use `C_GuildInfo.Invite()` instead.
- **`C_ChatInfo.SendChatMessage(msg, type, langID, target)`** — **preferred** chat send API (since 11.2.0). CHANNEL requires hardware event everywhere; SAY/YELL require hardware event outdoors only. WHISPER does not require hardware event.
- **`SendChatMessage(msg, type, langID, target)`** — **deprecated since 11.2.0**. Still works in 12.0.1. Use `C_ChatInfo.SendChatMessage()` instead.
- **`ChatFrame_AddMessageEventFilter(event, fn)`** — still available in 12.0.1. NOT deprecated. Used for whisper echo suppression.
- **`GetChannelList()`** — still available in 12.0.1. NOT deprecated. Returns triplets: id, name, disabled.
- **`C_Map.GetMapChildrenInfo(mapID, mapType, allDescendants)`** — used for zone gathering. Some clients return nil for root(0).
- **`C_Club.GetGuildClubId()`** + `ClubFinderGetCurrentClubListingInfo()` + `GetClubFinderLink()` — for clickable guild finder links. Requires `Blizzard_ClubFinder` addon to be loaded.
- **`GetTime()`** — returns session uptime in seconds (float). Used for runtime cooldowns.
- **`time()`** — returns epoch seconds (integer). Used for persisted expiry timestamps. Wrapped as `GRIP:Now()`.

### Midnight 12.0 Impact Summary

GRIP is **not affected** by Midnight's major "addon disarmament" (Secret Values, combat log removal, boss mod restrictions). All of GRIP's APIs (recruitment, chat, /who, guild) remain fully functional. The only required changes are migrating from deprecated `GuildInvite()` → `C_GuildInfo.Invite()` and updating the level cap default from 80 → 90.

---

## Testing Checklist

When making changes, verify:

- [ ] `/grip status` shows correct counts
- [ ] Blacklisted names never receive whispers or invites (BL_ExecutionGate)
- [ ] `/who` results don't add blacklisted names to Potential
- [ ] Hardware-event actions (scan/invite/post) only work from click/keybind/slash
- [ ] Timer-based actions (whisper queue) work without hardware events
- [ ] UI opens/closes cleanly; ESC doesn't open Game Menu
- [ ] Edit boxes retain user text during refresh cycles (dirty tracking)
- [ ] SavedVariables survive /reload (check WTF/Account/.../GRIP.lua)
- [ ] No Lua errors in default chat or BugSack on fresh login
- [ ] `GRIPDB.config` alias pairs stay in sync after toggling either key

---

## Gotchas & Known Patterns

- **Events.lua loads last** so all module functions exist before event handlers fire.
- **ReconcileAfterReload** (Core.lua) clears zombie pending states after `/reload`. Called from Events.lua ADDON_LOADED, after EnsureDB.
- **DB_Init.lua's MigrateLegacyBlacklistStrings** moves old string-value blacklist entries to blacklistPerm. This runs every EnsureDB call.
- **Zone exclusion** happens at multiple levels: `ShouldIncludeZoneName` (pattern + exact match), `BuildExcludedZoneNames` (dungeons/raids/BGs from Encounter Journal + BG APIs), and `FiltersAllowWhoInfo` (user selections).
- **FauxScrollFrame** in UI_Home uses manual row management, not a modern scroll list. Row count is calculated from available height.
- **Whisper echo suppression** works by buffering recent outgoing whispers and filtering `CHAT_MSG_WHISPER_INFORM` via `ChatFrame_AddMessageEventFilter`. This is cosmetic only — the event still fires for pipeline processing.
- **The `wipe()` function** is a WoW global that clears a table in-place (like `table.wipe`). It's used extensively — don't replace with `= {}` unless you intentionally want to break references.
