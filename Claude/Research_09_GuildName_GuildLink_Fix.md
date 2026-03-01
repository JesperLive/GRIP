# Research 09 — Guild Name & Guild Link Resolution Fix

> **Compiled:** 2026-03-01
> **GRIP version:** 0.4.0
> **Severity:** High — affects all `{guild}` and `{guildlink}` template tokens

---

## 1. Problem Statement

Two user-visible bugs:

1. **Settings → Preview button** doesn't show the guild name or guild link in the whisper preview. Both `{guild}` and `{guildlink}` resolve to empty string or the fallback "your guild".
2. **Debug window error spam** — when debug is enabled, `GetGuildName()` and `GetGuildFinderLink()` produce trace-level spam on every call that fails, which is every call during early login and potentially indefinitely if the guild name API returns nil.

A third issue (not user-facing but important): there is no way to copy/paste from the WoW debug chat window. Users need a dedicated copyable text frame for debug output.

---

## 2. Root Cause Analysis

### 2a. `C_GuildInfo.GetGuildInfo` Does Not Exist

**This is the primary bug.** In `Core/Utils.lua` lines 95–100:

```lua
if C_GuildInfo and C_GuildInfo.GetGuildInfo then
    local ok, info = pcall(C_GuildInfo.GetGuildInfo, "player")
    if ok and type(info) == "table" and type(info.guildName) == "string" then
        name = info.guildName
    end
end
```

**`C_GuildInfo.GetGuildInfo` is not a real WoW API function.** The `C_GuildInfo` namespace contains exactly 16 functions (verified against Wowpedia, March 2026):

1. `CanEditOfficerNote`
2. `CanSpeakInGuildChat`
3. `CanViewOfficerNote`
4. `GetGuildNewsInfo`
5. `GetGuildRankOrder`
6. `GetGuildTabardInfo`
7. `GuildControlGetRankFlags`
8. `GuildRoster`
9. `Invite`
10. `IsGuildOfficer`
11. `IsGuildRankAssignmentAllowed`
12. `MemberExistsByName`
13. `QueryGuildMemberRecipes`
14. `QueryGuildMembersForRecipe`
15. `RemoveFromGuild`
16. `SetGuildRankOrder`
17. `SetNote`

**There is no `GetGuildInfo` in `C_GuildInfo`.** The `if C_GuildInfo.GetGuildInfo then` check correctly evaluates to `false`, so this code path is dead. It never executes.

### 2b. `GetGuildInfo("player")` Returns Nil During Early Login

The fallback path (lines 103–108) correctly uses the legacy global `GetGuildInfo("player")`:

```lua
if name == "" and GetGuildInfo then
    local g = GetGuildInfo("player")
    if type(g) == "string" then
        name = g
    end
end
```

**The real API signature is:**
```lua
guildName, guildRankName, guildRankIndex, realm = GetGuildInfo(unit)
```

It returns **multiple values** (not a table). The code correctly takes just the first value.

**However**, `GetGuildInfo("player")` returns `nil` for the guild name during early login — before `PLAYER_GUILD_UPDATE` or `GUILD_ROSTER_UPDATE` events fire. This is a known, documented WoW API behavior:

> "If using with UnitId 'player' on loading, it happens that this value is nil even if the player is in a guild." — Warcraft Wiki

### 2c. No Event-Driven Cache Warming

GRIP's Events.lua registers for:
- `ADDON_LOADED`
- `PLAYER_LOGIN`
- `WHO_LIST_UPDATE`
- `CHAT_MSG_WHISPER_INFORM`
- `CHAT_MSG_SYSTEM`

**It does NOT register for any guild data events:**
- ❌ `PLAYER_GUILD_UPDATE` — fires when guild membership info becomes available
- ❌ `GUILD_ROSTER_UPDATE` — fires when roster data is ready
- ❌ `INITIAL_CLUBS_LOADED` — fires when Club (guild/community) system is ready

This means GRIP never learns when guild data becomes available. Every call to `GetGuildName()` during the early login window returns "" and sets `state._gripLastGuildName = ""`. The cache is poisoned with an empty value and only recovers if a later call happens to succeed — which may not happen until the user does something that triggers `GetGuildName()` again (like clicking Preview).

### 2d. `GetGuildFinderLink()` Timing

Even after guild name becomes available, `GetGuildFinderLink()` depends on:
1. `C_Club.GetGuildClubId()` — returns nil before `INITIAL_CLUBS_LOADED`
2. `ClubFinderGetCurrentClubListingInfo()` — requires Blizzard_ClubFinder loaded AND cache populated
3. The guild must have an active Guild Finder listing

Step 1 is the timing issue. `INITIAL_CLUBS_LOADED` fires well after `PLAYER_LOGIN`, sometimes 5–30 seconds into the session. Until then, the entire guild link pipeline fails silently.

### 2e. Debug Spam

Every failed call to `GetGuildFinderLink()` produces up to 4 trace-level debug messages (one per pipeline step). With debug verbosity at 3 (trace), this creates significant spam:

```
GetGuildFinderLink: missing C_Club.GetGuildClubId
GetGuildFinderLink: ClubFinder link APIs unavailable
GetGuildFinderLink: no clubId from C_Club.GetGuildClubId
GetGuildFinderLink: no listing info
```

These fire on every whisper, every preview click, every template expansion — not just once.

---

## 3. Event Timing During Login

Based on documentation and community reports, the approximate order is:

```
ADDON_LOADED (per addon)
    ↓
PLAYER_LOGIN
    ↓
PLAYER_ENTERING_WORLD
    ↓ (varying delays, not guaranteed order below)
PLAYER_GUILD_UPDATE    ← guild name becomes available via GetGuildInfo
GUILD_ROSTER_UPDATE    ← full roster data ready
    ↓ (potentially 5-30 seconds later)
INITIAL_CLUBS_LOADED   ← C_Club.GetGuildClubId() starts working
CLUB_STREAMS_LOADED    ← club data fully hydrated
```

**Key insight:** `GetGuildInfo("player")` reliably returns the guild name after `PLAYER_GUILD_UPDATE` fires. `C_Club.GetGuildClubId()` reliably returns a value after `INITIAL_CLUBS_LOADED`. These are two separate windows.

---

## 4. Recommended Fix

### 4a. Fix `GetGuildName()` — Remove Dead API Path, Add `IsInGuild()` Fallback

1. **Remove the `C_GuildInfo.GetGuildInfo` code path** entirely — it's dead code that never executes.
2. **Use `IsInGuild()` as a fast check** — this returns true/false reliably even during early login (before guild name is available).
3. **Keep `GetGuildInfo("player")` as the primary source** — it's the correct API.
4. **Cache aggressively** — once we have a guild name, don't lose it unless `IsInGuild()` returns false.

### 4b. Add Event-Driven Guild Data Warming

In `Events.lua`, register for:
- `PLAYER_GUILD_UPDATE` — warm guild name cache
- `GUILD_ROSTER_UPDATE` — warm guild name cache (backup)
- `INITIAL_CLUBS_LOADED` — warm guild link cache

On each event, proactively call `GetGuildName()` and (for `INITIAL_CLUBS_LOADED`) `GetGuildFinderLink()` to populate the caches. Store the results in `GRIP.state`.

### 4c. Add Throttled Guild Link Resolution

Instead of trying `GetGuildFinderLink()` on every call and producing spam, add a cooldown:
- Cache the guild link result (success or failure) with a timestamp
- On success: cache for 5 minutes (link could change if listing is updated)
- On failure: cache for 30 seconds (retry after cooldown)
- Reset cache on `INITIAL_CLUBS_LOADED` event

### 4d. Reduce Debug Spam

- `GetGuildFinderLink()` should only log at TRACE level on the **first** failure after cache reset, not on every call
- Use a flag like `state._gripGuildLinkLoggedFailure` that resets when the cache timer expires or on `INITIAL_CLUBS_LOADED`

### 4e. Add `/grip debug copy` — Copyable Debug Frame

Create a simple scrollable text frame with an EditBox that contains the persisted debug log. The user can Ctrl+A, Ctrl+C to copy the contents.

Implementation:
- New slash command: `/grip debug copy [n]` — opens a copyable frame with the last `n` lines (default 200)
- Uses a `ScrollFrame` containing a `MultiLineEditBox` (read-only appearance)
- Populates from `GRIPDB.debugLog.lines`
- Close button + ESC to dismiss

---

## 5. Specific Code Changes Required

### File: Core/Utils.lua — `GetGuildName()`

**Remove** lines 95–100 (dead `C_GuildInfo.GetGuildInfo` path).

**Keep** the `GetGuildInfo("player")` fallback, the `IsInGuild()` check, and the cache logic.

**Add** a positive cache check: don't clear cache if `IsInGuild()` returns true but `GetGuildInfo` returns nil (this means data isn't ready yet, not that we left the guild).

### File: Core/Utils.lua — `GetGuildFinderLink()`

**Add** a cache layer with timestamp-based expiry:
```lua
-- In GRIP.state:
--   _gripGuildLinkCache = { link="...", at=GetTime(), ok=bool }
```

**Add** spam suppression: only log failures once per cache cycle.

### File: Core/Events.lua

**Register** for `PLAYER_GUILD_UPDATE`, `GUILD_ROSTER_UPDATE`, and `INITIAL_CLUBS_LOADED`.

**Add handlers** that warm caches:
```lua
if event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
    GRIP:GetGuildName()  -- warm the cache
    GRIP:Debug("Guild data event:", event, "guild=", GRIP:GetGuildName())
end

if event == "INITIAL_CLUBS_LOADED" then
    -- Reset guild link cache so it retries with now-available data
    if state._gripGuildLinkCache then
        state._gripGuildLinkCache = nil
    end
    GRIP:Debug("INITIAL_CLUBS_LOADED: guild link cache reset")
end
```

### File: Core/Slash.lua

**Add** `/grip debug copy [n]` subcommand that opens the copyable frame.

### New behavior in Core/Core.lua or Core/Debug.lua

**Add** `GRIP:ShowDebugCopyFrame(n)` — creates and shows the copyable text frame.

---

## 6. Debug Copy Frame Design

```
+-----------------------------------------------+
| GRIP Debug Log                           [X]  |
+-----------------------------------------------+
| [12:01:05] DEBUG Event: PLAYER_LOGIN          |
| [12:01:05] DEBUG ADDON_LOADED complete.       |
| [12:01:06] TRACE EVENT: WHO_LIST_UPDATE       |
| [12:01:06] DEBUG WHO_LIST_UPDATE received.    |
| ...                                           |
| (scrollable, selectable, Ctrl+A/Ctrl+C)       |
+-----------------------------------------------+
| Lines: 142 | Ctrl+A to select, Ctrl+C to copy |
+-----------------------------------------------+
```

- Frame strata: DIALOG (above GRIP main UI)
- Size: 600×400, resizable
- ESC closes
- Uses a `ScrollFrame` + `EditBox` (multiline, non-editable feel but technically editable for select/copy)
- Populated from `GRIPDB.debugLog.lines` (persisted log) or from a snapshot of the current debug window

---

## 7. Summary of Changes

| # | File | Change | Risk |
|---|------|--------|------|
| 1 | Core/Utils.lua | Remove dead `C_GuildInfo.GetGuildInfo` path in `GetGuildName()` | None — code never executes |
| 2 | Core/Utils.lua | Fix `GetGuildName()` cache logic for early-login nil | Low — behavioral improvement |
| 3 | Core/Utils.lua | Add guild link cache with expiry in `GetGuildFinderLink()` | Low — reduces API calls |
| 4 | Core/Utils.lua | Suppress repeated trace spam in `GetGuildFinderLink()` | None — log quality improvement |
| 5 | Core/Events.lua | Register PLAYER_GUILD_UPDATE, GUILD_ROSTER_UPDATE, INITIAL_CLUBS_LOADED | Low — new event handlers |
| 6 | Core/Events.lua | Warm caches on guild events | Low — proactive cache population |
| 7 | Core/Slash.lua | Add `/grip debug copy [n]` command | None — new feature |
| 8 | Core/Debug.lua or Core/Core.lua | Add `ShowDebugCopyFrame(n)` | None — new feature |

**Zero changes to the recruitment pipeline, blacklist system, or UI pages.**

---

## Sources

- [C_GuildInfo namespace — Wowpedia](https://wowpedia.fandom.com/wiki/Category:API_namespaces/C_GuildInfo) — confirms no `GetGuildInfo` function exists
- [GetGuildInfo — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetGuildInfo) — return values, nil-on-loading behavior
- [GetGuildInfo — Wowpedia](https://wowpedia.fandom.com/wiki/API_GetGuildInfo) — additional notes on nil returns
- [C_Club.GetGuildClubId — Wowpedia](https://wowpedia.fandom.com/wiki/API_C_Club.GetGuildClubId) — timing and nil conditions
- [AddOn loading process — Warcraft Wiki](https://warcraft.wiki.gg/wiki/AddOn_loading_process) — login event sequence
- [Events — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Events) — INITIAL_CLUBS_LOADED, PLAYER_GUILD_UPDATE
